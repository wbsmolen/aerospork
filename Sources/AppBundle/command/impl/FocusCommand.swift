import AppKit
import Common

struct FocusCommand: Command {
    let args: FocusCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        // First, because a minimized window hangs off a global container: resolving a target fails on it.
        if case .windowId(let windowId) = args.target { try await Window.get(byId: windowId)?.exitMacosMinimizedOrHidden() }
        guard let target = args.resolveTargetOrReportError(env, io) else {
            return false
        }
        // Note: Floating windows are temporarily treated as tiling for directional focus.
        //       They should ideally be tracked in the same MRU stack to avoid potential issues.
        let floatingWindows = args.floatingAsTiling ? try await makeFloatingWindowsSeenAsTiling(workspace: target.workspace) : []
        defer {
            if args.floatingAsTiling {
                restoreFloatingWindows(floatingWindows: floatingWindows, workspace: target.workspace)
            }
        }

        switch args.target {
            case .direction(let direction):
                let window = target.windowOrNil
                if let (parent, ownIndex) = window?.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    guard let windowToFocus = parent.children[ownIndex + direction.focusOffset]
                        .findFocusTargetRecursive(snappedTo: direction.opposite)
                    else {
                        return false
                    }
                    return windowToFocus.focusWindow()
                } else {
                    return hitWorkspaceBoundaries(target, io, args, direction)
                }
            case .windowId(let windowId):
                if let windowToFocus = Window.get(byId: windowId) {
                    return windowToFocus.focusWindow()
                } else {
                    return io.err("Can't find window with ID \(windowId)")
                }
            case .dfsIndex(let dfsIndex):
                if let windowToFocus = target.workspace.rootTilingContainer.allLeafWindowsRecursive.getOrNil(atIndex: Int(dfsIndex)) {
                    return windowToFocus.focusWindow()
                } else {
                    return io.err("Can't find window with DFS index \(dfsIndex)")
                }
        }
    }
}

@MainActor private func hitWorkspaceBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
) -> Bool {
    switch args.boundaries {
        case .workspace:
            return switch args.boundariesAction {
                case .stop: true
                case .fail: false
                case .wrapAroundTheWorkspace: wrapAroundTheWorkspace(target, io, direction)
                case .wrapAroundAllMonitors: dieT("Must be discarded by args parser")
            }
        case .allMonitorsOuterFrame:
            let currentMonitor = target.workspace.workspaceMonitor
            guard let (monitors, index) = currentMonitor.findRelativeMonitor(inDirection: direction) else {
                return io.err("Should never happen. Can't find the current monitor")
            }

            if let targetMonitor = monitors.getOrNil(atIndex: index) {
                return targetMonitor.activeWorkspace.focusWorkspace()
            } else {
                guard let wrapped = monitors.get(wrappingIndex: index) else { return false }
                return hitAllMonitorsOuterFrameBoundaries(target, io, args, direction, wrapped)
            }
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
    _ wrappedMonitor: Monitor,
) -> Bool {
    switch args.boundariesAction {
        case .stop:
            return true
        case .fail:
            return false
        case .wrapAroundTheWorkspace:
            return wrapAroundTheWorkspace(target, io, direction)
        case .wrapAroundAllMonitors:
            wrappedMonitor.activeWorkspace.findFocusTargetRecursive(snappedTo: direction.opposite)?.markAsMostRecentChild()
            return wrappedMonitor.activeWorkspace.focusWorkspace()
    }
}

@MainActor private func wrapAroundTheWorkspace(_ target: LiveFocus, _ io: CmdIo, _ direction: CardinalDirection) -> Bool {
    guard let windowToFocus = target.workspace.findFocusTargetRecursive(snappedTo: direction.opposite) else {
        return io.err(noWindowIsFocused)
    }
    return windowToFocus.focusWindow()
}

@MainActor private func makeFloatingWindowsSeenAsTiling(workspace: Workspace) async throws -> [FloatingWindowData] {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    // Everything that awaits comes first, and the tree is only touched after it. Unbinding along the way
    // left the earlier windows detached when a later read threw, and a detached window crashes later on
    // "already unbound".
    var _targets: [(window: Window, center: CGPoint, parent: TilingContainer, index: Int)] = []
    let root = workspace.rootTilingContainer
    let hasNoTilingWindows = root.allLeafWindowsRecursive.isEmpty
    for window in workspace.floatingWindows {
        // Through the app's own thread, so after any frame write already queued for this window.
        let center = try await window.getCenter()
        guard let center else { continue }
        // Nothing to sit beside. In order among themselves, since the loop below binds in reverse.
        if hasNoTilingWindows {
            _targets.append((window, center, root, 0))
            continue
        }
        guard let target = center.coerceIn(rect: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)?
            .findIn(tree: workspace.rootTilingContainer, virtual: true) else { continue }
        guard let targetCenter = try await target.getCenter() else { continue }
        guard let tilingParent = target.parent as? TilingContainer else { continue }
        let index = center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
            ? target.ownIndex.orDie() + 1
            : target.ownIndex.orDie()
        _targets.append((window, center, tilingParent, index))
    }

    // Make floating windows be seen as tiling
    return _targets.sortedBy { $0.center.getProjection($0.parent.orientation) }.reversed().map { target in
        let data = target.window.unbindFromParent()
        target.window.bind(to: target.parent, adaptiveWeight: 1, index: target.index)
        return FloatingWindowData(window: target.window, center: target.center, parent: target.parent, adaptiveWeight: data.adaptiveWeight, index: target.index)
    }
}

@MainActor private func restoreFloatingWindows(floatingWindows: [FloatingWindowData], workspace: Workspace) {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    for floating in floatingWindows {
        floating.window.bind(to: workspace, adaptiveWeight: floating.adaptiveWeight, index: INDEX_BIND_LAST)
    }
}

private struct FloatingWindowData {
    let window: Window
    let center: CGPoint

    let parent: TilingContainer
    let adaptiveWeight: CGFloat
    let index: Int
}

extension TreeNode {
    @MainActor
    fileprivate func findFocusTargetRecursive(snappedTo direction: CardinalDirection) -> Window? {
        switch nodeCases {
            case .workspace(let workspace):
                return workspace.rootTilingContainer.findFocusTargetRecursive(snappedTo: direction)
            case .window(let window):
                return window
            case .tilingContainer(let container):
                if direction.orientation == container.orientation {
                    return (direction.isPositive ? container.children.last : container.children.first)?
                        .findFocusTargetRecursive(snappedTo: direction)
                } else {
                    return mostRecentChild?.findFocusTargetRecursive(snappedTo: direction)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                die("Impossible")
        }
    }
}
