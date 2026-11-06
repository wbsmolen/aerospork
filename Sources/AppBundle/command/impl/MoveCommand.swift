import AppKit
import Common

struct MoveCommand: Command {
    let args: MoveCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let direction = args.direction.val

        guard let target = args.resolveTargetOrReportError(env, io) else {
            return false
        }
        guard let currentWindow = target.windowOrNil else {
            return io.err(noWindowIsFocused)
        }

        guard let parent = currentWindow.parent else { return false }
        switch parent.cases {
            case .tilingContainer(let parent):
                let indexOfCurrent = currentWindow.ownIndex.orDie()
                let indexOfSiblingTarget = indexOfCurrent + direction.focusOffset
                if parent.orientation == direction.orientation && parent.children.indices.contains(indexOfSiblingTarget) {
                    switch parent.children[indexOfSiblingTarget].tilingTreeNodeCasesOrDie() {
                        case .tilingContainer(let topLevelSiblingTargetContainer):
                            return deepMoveIn(window: currentWindow, into: topLevelSiblingTargetContainer, moveDirection: direction)
                        case .window: // "swap windows"
                            let prevBinding = currentWindow.unbindFromParent()
                            currentWindow.bind(to: parent, adaptiveWeight: prevBinding.adaptiveWeight, index: indexOfSiblingTarget)
                            return true
                    }
                } else {
                    return moveOut(window: currentWindow, direction: direction, io, args, env)
                }
            case .workspace(let workspace): // floating window
                return try await moveFloating(currentWindow, on: workspace, direction, args, env, io)
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
                return io.err(moveOutMacosUnconventionalWindow)
            case .macosPopupWindowsContainer:
                return false // Impossible
        }
    }
}

/// How far `move` takes a floating window.
private let floatingMoveStep: CGFloat = 50

/// Keeps it on its monitor, which is another workspace's screen past the edge. At the edge
/// `--boundaries all-monitors-outer-frame` carries it over, and otherwise it stays put.
@MainActor private func moveFloating(
    _ window: Window,
    on workspace: Workspace,
    _ direction: CardinalDirection,
    _ args: MoveCmdArgs,
    _ env: CmdEnv,
    _ io: CmdIo,
) async throws -> Bool {
    guard workspace.isVisible else { return io.err(floatingWindowIsParked) }
    guard let rect = try await window.getAxRect() else { return false }
    let step = direction.isPositive ? floatingMoveStep : -floatingMoveStep
    let moved = rect.topLeftCorner.addingOffset(direction.orientation, step)
    let target = keptInside(workspace.workspaceMonitor.visibleRect, moved, rect.size)
    if target != rect.topLeftCorner {
        window.setAxTopLeftCorner(target)
        return true
    }
    if args.boundaries == .allMonitorsOuterFrame,
       let (monitors, index) = window.nodeMonitor?.findRelativeMonitor(inDirection: direction),
       monitors.getOrNil(atIndex: index) != nil
    {
        let moveNodeToMonitorArgs = MoveNodeToMonitorCmdArgs(target: .direction(direction))
            .copy(\.focusFollowsWindow, true)
            .copy(\.windowId, args.windowId)
        return MoveNodeToMonitorCommand(args: moveNodeToMonitorArgs).run(env, io)
    }
    return args.boundariesAction != .fail
}

@MainActor private func hitWorkspaceBoundaries(
    _ window: Window,
    _ workspace: Workspace,
    _ io: CmdIo,
    _ args: MoveCmdArgs,
    _ direction: CardinalDirection,
    _ env: CmdEnv,
) -> Bool {
    switch args.boundaries {
        case .workspace:
            return switch args.boundariesAction {
                case .stop: true
                case .fail: false
                case .createImplicitContainer:
                    (createImplicitContainerAndMoveWindow(window, workspace, direction), true).1
            }
        case .allMonitorsOuterFrame:
            guard let (monitors, index) = window.nodeMonitor?.findRelativeMonitor(inDirection: direction) else {
                return io.err("Should never happen. Can't find the current monitor")
            }

            guard monitors.getOrNil(atIndex: index) != nil else {
                return hitAllMonitorsOuterFrameBoundaries(window, workspace, io, args, direction)
            }

            let moveNodeToMonitorArgs = MoveNodeToMonitorCmdArgs(target: .direction(direction))
                .copy(\.focusFollowsWindow, true)
                .copy(\.windowId, args.windowId)

            return MoveNodeToMonitorCommand(args: moveNodeToMonitorArgs).run(env, io)
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ window: Window,
    _ workspace: Workspace,
    _ io: CmdIo,
    _ args: MoveCmdArgs,
    _ direction: CardinalDirection,
) -> Bool {
    switch args.boundariesAction {
        case .stop: true
        case .fail: false
        case .createImplicitContainer: (createImplicitContainerAndMoveWindow(window, workspace, direction), true).1
    }
}

// moveOutMacosUnconventionalWindow is now defined in CommandErrors.swift

@MainActor private func moveOut(
    window: Window,
    direction: CardinalDirection,
    _ io: CmdIo,
    _ args: MoveCmdArgs,
    _ env: CmdEnv,
) -> Bool {
    let innerMostChild = window.parents.first(where: {
        return switch $0.parent?.cases {
            case .tilingContainer(let parent): parent.orientation == direction.orientation
            // Stop searching
            case .workspace, .macosMinimizedWindowsContainer, nil, .macosFullscreenWindowsContainer,
                 .macosHiddenAppsWindowsContainer, .macosPopupWindowsContainer: true
        }
    }) as? TilingContainer
    guard let innerMostChild else { return false }
    guard let parent = innerMostChild.parent else { return false }
    switch parent.nodeCases {
        case .tilingContainer(let parent):
            check(parent.orientation == direction.orientation)
            guard let ownIndex = innerMostChild.ownIndex else { return false }
            window.bind(to: parent, adaptiveWeight: WEIGHT_AUTO, index: ownIndex + direction.insertionOffset)
            return true
        case .workspace(let parent):
            return hitWorkspaceBoundaries(window, parent, io, args, direction, env)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
            return io.err(moveOutMacosUnconventionalWindow)
        case .macosPopupWindowsContainer:
            return false // Impossible
        case .window:
            die("Window can't contain children nodes")
    }
}

@MainActor private func createImplicitContainerAndMoveWindow(
    _ window: Window,
    _ workspace: Workspace,
    _ direction: CardinalDirection,
) {
    let prevRoot = workspace.rootTilingContainer
    prevRoot.unbindFromParent()
    // Force tiles layout
    _ = TilingContainer(parent: workspace, adaptiveWeight: WEIGHT_AUTO, direction.orientation, .tiles, index: 0)
    check(prevRoot != workspace.rootTilingContainer)
    prevRoot.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: 0)
    window.bind(to: workspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: direction.insertionOffset)
}

@MainActor private func deepMoveIn(window: Window, into container: TilingContainer, moveDirection: CardinalDirection) -> Bool {
    let deepTarget = container.tilingTreeNodeCasesOrDie().findDeepMoveInTargetRecursive(moveDirection.orientation)
    switch deepTarget {
        case .tilingContainer(let deepTarget):
            window.bind(to: deepTarget, adaptiveWeight: WEIGHT_AUTO, index: 0)
        case .window(let deepTarget):
            guard let parent = deepTarget.parent as? TilingContainer else { return false }
            window.bind(
                to: parent,
                adaptiveWeight: WEIGHT_AUTO,
                index: deepTarget.ownIndex.orDie() + 1,
            )
    }
    return true
}

extension TilingTreeNodeCases {
    @MainActor fileprivate func findDeepMoveInTargetRecursive(_ orientation: Orientation) -> TilingTreeNodeCases {
        return switch self {
            case .window:
                self
            case .tilingContainer(let container):
                if container.orientation == orientation {
                    .tilingContainer(container)
                } else {
                    container.mostRecentChild.orDie("Empty containers must be detached during normalization")
                        .tilingTreeNodeCasesOrDie()
                        .findDeepMoveInTargetRecursive(orientation)
                }
        }
    }
}
