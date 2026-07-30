import AppKit
import Common

@MainActor private var workspaceNameToWorkspace: [String: Workspace] = [:]

@MainActor private var screenPointToPrevVisibleWorkspace: [CGPoint: String] = [:]
@MainActor private var screenPointToVisibleWorkspace: [CGPoint: Workspace] = [:]
@MainActor private var visibleWorkspaceToScreenPoint: [Workspace: CGPoint] = [:]

// The returned workspace must be invisible and it must belong to the requested monitor
@MainActor func getStubWorkspace(for monitor: Monitor) -> Workspace {
    getStubWorkspace(forPoint: monitor.rect.topLeftCorner)
}

@MainActor
private func getStubWorkspace(forPoint point: CGPoint) -> Workspace {
    if let prev = screenPointToPrevVisibleWorkspace[point].map({ Workspace.get(byName: $0) }),
       !prev.isVisible && prev.workspaceMonitor.rect.topLeftCorner == point && prev.forceAssignedMonitor == nil
    {
        return prev
    }
    if let candidate = Workspace.all
        .first(where: { !$0.isVisible && $0.workspaceMonitor.rect.topLeftCorner == point })
    {
        return candidate
    }
    // Prefer a workspace the user actually BOUND. Otherwise an idle monitor shows a name no
    // keybinding can reach: the fallback below counts up from 1 and skips every preserved name, so
    // a config binding 1-9 gets "10", 11, ... -- workspaces the user cannot switch to, on the
    // monitor they are looking at. Ordered by the same logical sort as `Workspace.all`, so "2"
    // comes before "10" and before "A".
    //
    // Materializes lazily: the first suitable name wins, so this costs one or two objects rather
    // than re-instantiating the whole keymap (the bloat `garbageCollectUnusedWorkspaces` removes).
    let isSuitable = { (ws: Workspace) in
        ws.isEffectivelyEmpty && !ws.isVisible && ws.forceAssignedMonitor == nil
    }
    if let bound = config.preservedWorkspaceNames
        .sorted(by: { $0.toLogicalSegments() < $1.toLogicalSegments() })
        .lazy
        .map({ Workspace.get(byName: $0) })
        .first(where: isSuitable)
    {
        return bound
    }
    // Every bound name is taken (or the config binds none). Fall back to inventing one, skipping
    // preserved names so a stub never hijacks a name the user has bound to something else.
    let preservedNames = config.preservedWorkspaceNames.toSet()
    return (1 ... Int.max).lazy
        .map { Workspace.get(byName: String($0)) }
        .first { isSuitable($0) && !preservedNames.contains($0.name) }
        .orDie("Can't create empty workspace")
}

class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let name: String
    private nonisolated let nameLogicalSegments: StringLogicalSegments
    /// `assignedMonitorPoint` must be interpreted only when the workspace is invisible
    fileprivate var assignedMonitorPoint: CGPoint? = nil

    @MainActor
    private init(_ name: String) {
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor static var all: [Workspace] {
        workspaceNameToWorkspace.values.sorted()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = workspaceNameToWorkspace[name] {
            return existing
        } else {
            let workspace = Workspace(name)
            workspaceNameToWorkspace[name] = workspace
            return workspace
        }
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.nameLogicalSegments < rhs.nameLogicalSegments
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    @MainActor
    var description: String {
        let preservedNames = config.preservedWorkspaceNames.toSet()
        let description = [
            ("name", name),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("doKeepAlive", String(preservedNames.contains(name))),
        ].map { "\($0.0): '\(String(describing: $0.1))'" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    @MainActor
    static func garbageCollectUnusedWorkspaces() {
        // Workspaces are created on demand by `get(byName:)` and are pure identity when empty, so
        // there is nothing to preserve about an empty invisible one -- switching to it recreates it
        // indistinguishably.
        //
        // This used to force-materialize every name mentioned in any keybinding, then exempt those
        // names from collection. With a normal i3-style keymap (alt-1..9, alt-a..z) that is ~30
        // live objects that exist only because a shortcut mentions them: every refresh then walked
        // all of them for layout, normalization and tray text, and the menu bar listed all of them.
        // `preservedWorkspaceNames` still matters -- `getStubWorkspace` must not hijack a name the
        // user has bound -- but that only needs the NAME SET, not instantiated workspaces.
        workspaceNameToWorkspace = workspaceNameToWorkspace.filter { (_, workspace: Workspace) in
            !workspace.isEffectivelyEmpty ||
                workspace.isVisible ||
                workspace.name == focus.workspace.name
        }
    }

    /// Identity, same as the inherited ``TreeNode/==``.
    ///
    /// It used to be `===` *guarded* by `check((lhs === rhs) == (lhs.name == rhs.name))` -- a fatal
    /// assertion that `get(byName:)` interning is never broken. `garbageCollectUnusedWorkspaces`
    /// breaks it on purpose: it drops empty invisible workspaces from the registry, so anything
    /// still holding one -- a local in an `async` function that released the main actor across an
    /// `await`, which `layoutWorkspaces` does per workspace -- then meets the freshly created
    /// namesake. Comparing the two took the whole window manager down.
    ///
    /// Not switched to name equality, tempting as that is: this overload is only picked at call
    /// sites where BOTH sides are statically `Workspace`. Generic contexts (`Dictionary`, `Set`,
    /// `assertEquals`) go through the `Equatable` witness, which `TreeNode` already provides and a
    /// subclass cannot replace -- so name equality here would mean `a == b` answering differently
    /// depending on the static type of the expression. Identity is the answer that agrees with
    /// every other path.
    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool { lhs === rhs }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension Workspace {
    @MainActor
    var isVisible: Bool { visibleWorkspaceToScreenPoint.keys.contains(self) }
    @MainActor
    var workspaceMonitor: Monitor {
        forceAssignedMonitor
            ?? visibleWorkspaceToScreenPoint[self]?.monitorApproximation
            ?? assignedMonitorPoint?.monitorApproximation
            ?? mainMonitor
    }

    // MARK: - Container Access

    @MainActor var rootTilingContainer: TilingContainer {
        let containers = children.filterIsInstance(of: TilingContainer.self)
        switch containers.count {
            case 0:
                let orientation: Orientation = switch config.defaultRootContainerOrientation {
                    case .horizontal: .h
                    case .vertical: .v
                    case .auto: workspaceMonitor.then { $0.width >= $0.height } ? .h : .v
                }
                return TilingContainer(parent: self, adaptiveWeight: 1, orientation, config.defaultRootContainerLayout, index: INDEX_BIND_LAST)
            case 1:
                return containers.singleOrNil().orDie()
            default:
                die("Workspace must contain zero or one tiling container as its child")
        }
    }

    var floatingWindows: [Window] {
        children.filterIsInstance(of: Window.self)
    }

    @MainActor var macOsNativeFullscreenWindowsContainer: MacosFullscreenWindowsContainer {
        let containers = children.filterIsInstance(of: MacosFullscreenWindowsContainer.self)
        return switch containers.count {
            case 0: MacosFullscreenWindowsContainer(parent: self)
            case 1: containers.singleOrNil().orDie()
            default: dieT("Workspace must contain zero or one MacosFullscreenWindowsContainer")
        }
    }

    @MainActor var macOsNativeHiddenAppsWindowsContainer: MacosHiddenAppsWindowsContainer {
        let containers = children.filterIsInstance(of: MacosHiddenAppsWindowsContainer.self)
        return switch containers.count {
            case 0: MacosHiddenAppsWindowsContainer(parent: self)
            case 1: containers.singleOrNil().orDie()
            default: dieT("Workspace must contain zero or one MacosHiddenAppsWindowsContainer")
        }
    }

    /// Pins an *invisible* workspace to a monitor.
    ///
    /// `assignedMonitorPoint` is otherwise only written when a workspace becomes visible or is
    /// force-assigned, so a workspace materialized by name -- as `WorkspaceMemory` does when
    /// restoring after a restart -- had no monitor at all and `workspaceMonitor` answered
    /// `mainMonitor` for it.
    @MainActor func assignMonitor(_ monitor: Monitor) {
        assignedMonitorPoint = monitor.rect.topLeftCorner
    }

    @MainActor var forceAssignedMonitor: Monitor? {
        guard let monitorDescriptions = config.workspaceToMonitorForceAssignment[name] else {
            return nil
        }
        let sortedMonitors = sortedMonitors
        // No logging here. This is the first thing `workspaceMonitor` checks, and that runs from
        // layout, focus, tray updates and hideInCorner -- i.e. many times per refresh.
        return monitorDescriptions.lazy
            .compactMap { $0.resolveMonitor(sortedMonitors: sortedMonitors) }
            .first
    }
}

extension Monitor {
    @MainActor
    var activeWorkspace: Workspace {
        let point = rect.topLeftCorner
        if let existing = screenPointToVisibleWorkspace[point] {
            return existing
        }
        // Monitor configuration changed (frame.origin moved), so rebuild the mapping -- ONCE.
        // This used to `return self.activeWorkspace`, which is unbounded recursion, not a retry:
        // `rearrangeWorkspacesOnMonitors` only ever populates points belonging to the CURRENT
        // `monitors`, so any `Monitor` value whose rect is no longer among them (a stale one held
        // across an `await`, or one rejected below) recursed until the stack ran out.
        rearrangeWorkspacesOnMonitors()
        return screenPointToVisibleWorkspace[point] ?? getStubWorkspace(forPoint: point)
    }

    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        rect.topLeftCorner.setActiveWorkspace(workspace)
    }
}

@MainActor
func gcMonitors() {
    if screenPointToVisibleWorkspace.count != monitors.count {
        rearrangeWorkspacesOnMonitors()
    }
}

extension CGPoint {
    @MainActor
    fileprivate func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        if !isValidAssignment(workspace: workspace, screen: self) {
            return false
        }
        if let prevMonitorPoint = visibleWorkspaceToScreenPoint[workspace] {
            visibleWorkspaceToScreenPoint.removeValue(forKey: workspace)
            screenPointToPrevVisibleWorkspace[prevMonitorPoint] =
                screenPointToVisibleWorkspace.removeValue(forKey: prevMonitorPoint)?.name
        }
        if let prevWorkspace = screenPointToVisibleWorkspace[self] {
            screenPointToPrevVisibleWorkspace[self] =
                screenPointToVisibleWorkspace.removeValue(forKey: self)?.name
            visibleWorkspaceToScreenPoint.removeValue(forKey: prevWorkspace)
        }
        visibleWorkspaceToScreenPoint[workspace] = self
        screenPointToVisibleWorkspace[self] = workspace
        workspace.assignedMonitorPoint = self
        return true
    }
}

@MainActor
private func rearrangeWorkspacesOnMonitors() {
    var oldVisibleScreens: Set<CGPoint> = screenPointToVisibleWorkspace.keys.toSet()

    let newScreens = monitors.map(\.rect.topLeftCorner)
    var newScreenToOldScreenMapping: [CGPoint: CGPoint] = [:]
    for newScreen in newScreens {
        if let oldScreen = oldVisibleScreens.minBy({ ($0 - newScreen).vectorLength }) {
            check(oldVisibleScreens.remove(oldScreen) != nil)
            newScreenToOldScreenMapping[newScreen] = oldScreen
        }
    }

    let oldScreenPointToVisibleWorkspace = screenPointToVisibleWorkspace
    screenPointToVisibleWorkspace = [:]
    visibleWorkspaceToScreenPoint = [:]

    for newScreen in newScreens {
        if let existingVisibleWorkspace = newScreenToOldScreenMapping[newScreen].flatMap({ oldScreenPointToVisibleWorkspace[$0] }),
           newScreen.setActiveWorkspace(existingVisibleWorkspace)
        {
            continue
        }
        let stubWorkspace = getStubWorkspace(forPoint: newScreen)
        if !newScreen.setActiveWorkspace(stubWorkspace) {
            // Was a `check`, i.e. fatal. It fires when the chosen stub turns out to be
            // force-assigned to a different monitor, which `getStubWorkspace` filters for -- but
            // against `monitors` as they are read *inside* it, and a DisplayLink dock reconfigures
            // in several stages, so the two reads need not agree. The screen is left without a
            // visible workspace; `Monitor.activeWorkspace` now answers with a stub rather than
            // recursing, so this degrades to "that monitor shows a stub" instead of a crash.
            debugLog("rearrangeWorkspacesOnMonitors: stub \(stubWorkspace.name) rejected for monitor \(newScreen)")
        }
    }
}

@MainActor
func autoMoveWorkspacesToAssignedMonitors() {
    for workspace in Workspace.all {
        // Resolved once. `forceAssignedMonitor` rebuilds and sorts the entire monitor list on every
        // read; this loop used to read it twice per workspace, plus a third time inside
        // `workspaceMonitor`.
        guard let assignedMonitor = workspace.forceAssignedMonitor else { continue }
        let assignedPoint = assignedMonitor.rect.topLeftCorner

        // Where the workspace actually IS. Deliberately not `workspaceMonitor`, which answers
        // `forceAssignedMonitor` FIRST -- so the old "already on its assigned monitor?" test
        // compared the assignment against itself. It was therefore true for every workspace whose
        // assignment resolves, and false-then-`continue` for every one whose assignment does not:
        // every path bailed, and `auto-move-workspaces-on-monitor-connect` moved nothing, ever.
        // Pinned by MonitorIdentityTest.testAutoMoveActuallyMovesAWorkspaceToItsAssignedMonitor.
        let currentPoint = visibleWorkspaceToScreenPoint[workspace] ?? workspace.assignedMonitorPoint
        if currentPoint == assignedPoint { continue }

        guard workspace.isVisible else {
            workspace.assignedMonitorPoint = assignedPoint
            continue
        }
        // On screen: hand the assigned monitor to this workspace, and give whatever was there to the
        // monitor this workspace is vacating -- otherwise that monitor is left showing nothing.
        // `displaced` is read BEFORE the first swap, which is what clears that entry.
        let displaced = screenPointToVisibleWorkspace[assignedPoint]
        _ = assignedPoint.setActiveWorkspace(workspace)
        if let displaced, let currentPoint {
            _ = currentPoint.setActiveWorkspace(displaced)
        }
    }
}

@MainActor
private func isValidAssignment(workspace: Workspace, screen: CGPoint) -> Bool {
    if let forceAssigned = workspace.forceAssignedMonitor, forceAssigned.rect.topLeftCorner != screen {
        return false
    } else {
        return true
    }
}
