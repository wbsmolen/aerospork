import AppKit
import Common

/// First line of defence against lock screen
///
/// When you lock the screen, all accessibility API becomes unobservable (all attributes become empty, window id
/// becomes nil, etc.) which tricks AeroSpork into thinking that all windows were closed.
/// That's why every time a window dies AeroSpork caches the "entire world" (unless window is already presented in the cache)
/// so that once the screen is unlocked, AeroSpork could restore windows to where they were
@MainActor private var closedWindowsCache = FrozenWorld(workspaces: [], monitors: [])

struct FrozenMonitor: Sendable {
    let topLeftCorner: CGPoint
    let visibleWorkspace: String

    @MainActor init(_ monitor: Monitor) {
        topLeftCorner = monitor.rect.topLeftCorner
        visibleWorkspace = monitor.activeWorkspace.name
    }
}

struct FrozenWorkspace: Sendable {
    let name: String
    let monitor: FrozenMonitor
    let rootTilingNode: FrozenContainer
    let floatingWindows: [FrozenWindow]
    let macosUnconventionalWindows: [FrozenWindow]

    @MainActor init(_ workspace: Workspace) {
        name = workspace.name
        monitor = FrozenMonitor(workspace.workspaceMonitor)
        rootTilingNode = FrozenContainer(workspace.rootTilingContainer)
        floatingWindows = workspace.floatingWindows.map(FrozenWindow.init)
        macosUnconventionalWindows =
            workspace.macOsNativeHiddenAppsWindowsContainer.children.map { FrozenWindow($0 as! Window) } +
            workspace.macOsNativeFullscreenWindowsContainer.children.map { FrozenWindow($0 as! Window) }
    }
}

@MainActor func cacheClosedWindowIfNeeded(window: Window) {
    if closedWindowsCache.windowIds.contains(window.windowId) {
        return // already cached
    }
    closedWindowsCache = FrozenWorld(
        workspaces: Workspace.all.map { FrozenWorkspace($0) },
        monitors: monitors.map(FrozenMonitor.init),
    )
    // Why the original `check(cache.windowIds.contains(window.windowId))` stays commented out.
    //
    // It is false whenever the dying window is not reachable from `Workspace.all`, which is what
    // `FrozenWorkspace` walks. `isBound` does NOT rule that out: it only means `parent != nil`, and
    // a window can be bound to a container that has itself been detached, so the chain never reaches
    // a workspace. Re-adding this as a fatal `check(!window.isBound || ...)` shipped a crash --
    // `globalObserverLeftMouseUp` closing a window took the whole app down.
    //
    // The severity was the real mistake. This is a best-effort cache for restoring windows after the
    // screen unlocks; failing to capture one degrades that restore for one window and nothing else.
    // `check` calls `die`. Never trade a live window manager for a diagnostic about a cache.
    if !closedWindowsCache.windowIds.contains(window.windowId) {
        debugLog("closedWindowsCache: window \(window.windowId) not captured (workspace: \(window.nodeWorkspace?.name ?? "none")); it will not be restorable")
    }
}

@MainActor func restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: Window) async throws -> Bool {
    if !closedWindowsCache.windowIds.contains(newlyDetectedWindow.windowId) {
        return false
    }
    AppLog.session.notice("closed-windows cache restored by window \(newlyDetectedWindow.windowId, privacy: .public): rebinding \(closedWindowsCache.windowIds.count, privacy: .public) windows across \(closedWindowsCache.workspaces.count, privacy: .public) workspaces")
    let monitors = monitors
    let topLeftCornerToMonitor = monitors.grouped { $0.rect.topLeftCorner }

    for frozenWorkspace in closedWindowsCache.workspaces {
        let workspace = Workspace.get(byName: frozenWorkspace.name)
        _ = topLeftCornerToMonitor[frozenWorkspace.monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(workspace)
        for frozenWindow in frozenWorkspace.floatingWindows {
            MacWindow.get(byId: frozenWindow.id)?.bindAsFloatingWindow(to: workspace)
        }
        for frozenWindow in frozenWorkspace.macosUnconventionalWindows { // Will get fixed by normalizations
            MacWindow.get(byId: frozenWindow.id)?.bindAsFloatingWindow(to: workspace)
        }
        try await restoreTilingTree(of: workspace, from: frozenWorkspace.rootTilingNode) { MacWindow.get(byId: $0) }
    }

    for monitor in closedWindowsCache.monitors {
        _ = topLeftCornerToMonitor[monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(Workspace.get(byName: monitor.visibleWorkspace))
    }
    return true
}

/// Rebuilds `workspace`'s tiling tree from `frozen` with the windows `windows` can find. Anything else that
/// was on the workspace stays on it, placed like any new window.
@MainActor
func restoreTilingTree(of workspace: Workspace, from frozen: FrozenContainer, windows: (UInt32) -> Window?) async throws {
    let mru = workspace.mostRecentWindowRecursive
    let prevRoot = workspace.rootTilingContainer // Save prevRoot into a variable to avoid it being garbage collected earlier than needed
    let potentialOrphans = prevRoot.allLeafWindowsRecursive
    prevRoot.unbindFromParent()
    restoreTreeRecursive(frozenContainer: frozen, parent: workspace, windows)
    for window in (potentialOrphans - workspace.rootTilingContainer.allLeafWindowsRecursive) {
        try await window.relayoutWindow(on: workspace, forceTile: true)
    }
    // Rebinding raises every window it touches, and this isn't anybody choosing one.
    mru?.markAsMostRecentChild()
}

@MainActor
private func restoreTreeRecursive(frozenContainer: FrozenContainer, parent: NonLeafTreeNodeObject, _ windows: (UInt32) -> Window?) {
    let container = TilingContainer(
        parent: parent,
        adaptiveWeight: frozenContainer.weight,
        frozenContainer.orientation,
        frozenContainer.layout,
        index: INDEX_BIND_LAST,
    )
    // In the unit of the weights, because an entry that isn't here becomes a share of the whole sequence.
    let total = frozenContainer.children.reduce(0) { sum, child in
        switch child {
            case .window(let w): sum + max(0, w.weight)
            case .container(let c): sum + max(0, c.weight)
        }
    }
    var preceding: [UInt32] = []
    for child in frozenContainer.children {
        switch child {
            case .window(let w):
                if let window = windows(w.id) {
                    window.bind(to: container, adaptiveWeight: w.weight, index: INDEX_BIND_LAST)
                } else {
                    // Not here yet: a slow app, or a window minimized at the time. It keeps its place, and the
                    // rest keep their order around it.
                    container.awayWindows.append(AwayWindow(id: w.id, share: total > 0 ? max(0, w.weight) / total : 0, after: preceding))
                }
                preceding.append(w.id)
            case .container(let c):
                let ids = c.allWindowIds
                if ids.contains(where: { windows($0) != nil }) {
                    restoreTreeRecursive(frozenContainer: c, parent: container, windows)
                } else {
                    // Not an empty container, which would hold an empty tile. Its windows keep a place here.
                    let share = total > 0 ? max(0, c.weight) / total / CGFloat(max(ids.count, 1)) : 0
                    for (i, id) in ids.enumerated() {
                        container.awayWindows.append(AwayWindow(id: id, share: share, after: preceding + ids[..<i]))
                    }
                }
                preceding += ids
        }
    }
}

// Consider the following case:
// 1. Close window
// 2. The previous step lead to caching the whole world
// 3. Change something in the layout
// 4. Lock the screen
// 5. The cache won't be updated because all alive windows are already cached
// 6. Unlock the screen
// 7. The wrong cache is used
//
// That's why we have to reset the cache every time layout changes. The layout can only be changed by running commands
// and with mouse manipulations
@MainActor func resetClosedWindowsCache() {
    closedWindowsCache = FrozenWorld(workspaces: [], monitors: [])
}

@MainActor var isClosedWindowsCacheEmpty: Bool { closedWindowsCache.windowIds.isEmpty }
