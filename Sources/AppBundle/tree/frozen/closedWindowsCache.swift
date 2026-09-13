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
    let monitor: FrozenMonitor // todo drop this property, once monitor to workspace assignment migrates to TreeNode
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
        let prevRoot = workspace.rootTilingContainer // Save prevRoot into a variable to avoid it being garbage collected earlier than needed
        let potentialOrphans = prevRoot.allLeafWindowsRecursive
        prevRoot.unbindFromParent()
        restoreTreeRecursive(frozenContainer: frozenWorkspace.rootTilingNode, parent: workspace, index: INDEX_BIND_LAST)
        for window in (potentialOrphans - workspace.rootTilingContainer.allLeafWindowsRecursive) {
            try await window.relayoutWindow(on: workspace, forceTile: true)
        }
    }

    for monitor in closedWindowsCache.monitors {
        _ = topLeftCornerToMonitor[monitor.topLeftCorner]?
            .singleOrNil()?
            .setActiveWorkspace(Workspace.get(byName: monitor.visibleWorkspace))
    }
    return true
}

@discardableResult
@MainActor
private func restoreTreeRecursive(frozenContainer: FrozenContainer, parent: NonLeafTreeNodeObject, index: Int) -> Bool {
    let container = TilingContainer(
        parent: parent,
        adaptiveWeight: frozenContainer.weight,
        frozenContainer.orientation,
        frozenContainer.layout,
        index: index,
    )

    for (index, child) in frozenContainer.children.enumerated() {
        switch child {
            case .window(let w):
                // Stop the loop if can't find the window, because otherwise all the subsequent windows will have incorrect index
                guard let window = MacWindow.get(byId: w.id) else { return false }
                window.bind(to: container, adaptiveWeight: w.weight, index: index)
            case .container(let c):
                // There is no reason to continue
                if !restoreTreeRecursive(frozenContainer: c, parent: container, index: index) { return false }
        }
    }
    return true
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
