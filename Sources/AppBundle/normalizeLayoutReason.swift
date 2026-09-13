@MainActor
func normalizeLayoutReason() async throws {
    for workspace in Workspace.all {
        try checkCancellation()
        let windows: [Window] = workspace.allLeafWindowsRecursive
        try await _normalizeLayoutReason(workspace: workspace, windows: windows)
    }
    try await _normalizeLayoutReason(workspace: focus.workspace, windows: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self))
    try await validateStillPopups()
}

@MainActor
private func validateStillPopups() async throws {
    for node in macosPopupWindowsContainer.children {
        let popup = (node as! MacWindow)
        if try await popup.isWindowHeuristic() {
            // The same commitment as registration: once relaid out it is no longer a popup, so this is
            // the only run its rules get.
            try await shieldedFromCancellation {
                try await popup.relayoutWindow(on: focus.workspace)
                try await tryOnWindowDetected(popup)
            }
        }
    }
}

@MainActor
private func _normalizeLayoutReason(workspace: Workspace, windows: [Window]) async throws {
    // Prefetch both AX reads for every window concurrently. These used to be two sequential
    // `await`s inside the mutation loop, i.e. 2 serialized MainActor<->app-thread round trips per
    // window per refresh, over every window of every workspace -- the dominant cost of a refresh,
    // and enough on its own to exceed the 50ms debounce and cause refresh cancellation thrash.
    // Same fan-out pattern as MacApp.refreshAllAndGetAliveWindowIds. The loop below stays serial
    // because it rebinds tree nodes.
    let states: [(full: Bool, mini: Bool)] = try await withThrowingTaskGroup(of: (Int, Bool, Bool).self) { group in
        for (i, window) in windows.enumerated() {
            group.addTask { @Sendable @MainActor in
                // One hop per window, not two. `macosNativeState` reads both flags inside a single
                // `runInLoop` and keeps the same short-circuit (a fullscreen window is never asked
                // whether it is minimized).
                let state = try await window.macosNativeState()
                return (i, state.fullscreen, state.minimized)
            }
        }
        var result = [(full: Bool, mini: Bool)](repeating: (false, false), count: windows.count)
        for try await (i, full, mini) in group { result[i] = (full, mini) }
        return result
    }

    for (i, window) in windows.enumerated() {
        // The `.standard` branch below is entirely synchronous, so without this a cancelled
        // refresh rebound the whole tree instead of stopping at the first window.
        try checkCancellation()
        // An earlier iteration's await may have let a concurrent session garbage collect this
        // window; binding it below would resurrect a dead node.
        guard window.parent != nil else { continue }

        // Does the prefetched snapshot say we are about to move this window? Everything else is a
        // no-op, and in steady state that is essentially every window -- which is what keeps the
        // re-read below off the hot path. `||` short-circuits, so the app is still only asked
        // whether it is hidden when the window is neither fullscreen nor minimized, same as before.
        let snapshotIsUnconventional = states[i].full || states[i].mini ||
            (!config.automaticallyUnhideMacosHiddenApps && window.isMacosAppHidden)
        let willMutate = switch window.layoutReason {
            case .standard: snapshotIsUnconventional
            case .macos: !snapshotIsUnconventional
        }
        if !willMutate { continue }

        // Re-read before acting. The snapshot was taken before the loop and the loop releases the
        // main actor on every await (exitMacOsNativeUnconventionalState -> relayoutWindow), so a
        // window can be un-minimized or un-fullscreened underneath us -- and acting on the stale
        // answer binds a now-visible window into the minimized/fullscreen container.
        let fresh = try await window.macosNativeState()
        let isMacosFullscreen = fresh.fullscreen
        let isMacosMinimized = fresh.minimized
        let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized &&
            !config.automaticallyUnhideMacosHiddenApps && window.isMacosAppHidden
        switch window.layoutReason {
            case .standard:
                guard let parent = window.parent else { continue }
                let prevWorkspaceName = window.nodeWorkspace?.name
                // Every rebind here is bookkeeping -- a window went fullscreen, was minimized, or
                // was hidden -- not the user choosing a window. But `TreeNode.bind` pushes whatever
                // it binds to the front of the MRU, all the way to the root, and the MRU is what
                // `Workspace.toLiveFocus()` reads, which is what the derived global `focus` falls
                // back to. The fullscreen and hidden containers hang off the workspace, so without
                // this a window going fullscreen silently became its workspace's focused window --
                // and `runSession` then pushed that to macOS. Same compensation
                // `normalizeContainers` already does around its flatten.
                let mruBefore = window.nodeWorkspace?.mostRecentWindowRecursive
                defer { restoreMru(mruBefore, movedWindow: window) }
                if isMacosFullscreen {
                    window.layoutReason = .macos(prevParentKind: parent.kind, prevWorkspaceName: prevWorkspaceName)
                    window.bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                } else if isMacosMinimized {
                    window.layoutReason = .macos(prevParentKind: parent.kind, prevWorkspaceName: prevWorkspaceName)
                    window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
                } else if isMacosWindowOfHiddenApp {
                    window.layoutReason = .macos(prevParentKind: parent.kind, prevWorkspaceName: prevWorkspaceName)
                    window.bind(to: workspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
                }
            case .macos(let prevParentKind, let prevWorkspaceName):
                if !isMacosFullscreen && !isMacosMinimized && !isMacosWindowOfHiddenApp {
                    // Back to where it was, not to `workspace`. For the workspace-scoped pass the
                    // two agree; for the minimized pass, `workspace` is `focus.workspace`, which is
                    // how un-minimizing used to move a window between workspaces.
                    //
                    // The window's OWN workspace first, and the recorded name only when it has
                    // none. `prevWorkspaceName` is stamped once on the way in and never rewritten, so
                    // trusting it unconditionally silently undid any `move-node-to-workspace` or
                    // `move-node-to-monitor` performed while the window was fullscreen or its app
                    // hidden -- those containers hang off the workspace, so `nodeWorkspace` is live
                    // and authoritative there. Only the global minimized container is workspace-less,
                    // which is the exact case the recorded name was added for.
                    //
                    // `existing`, never `get`: minimizing the last window on a workspace leaves it
                    // empty, and empty invisible workspaces are collected. `get(byName:)` would mint
                    // a namesake with no `assignedMonitorPoint`, which reports `mainMonitor` -- so
                    // the window would come back on the wrong display. If the workspace is gone,
                    // `workspace` is no worse than what this replaced.
                    let target = window.nodeWorkspace
                        ?? prevWorkspaceName.flatMap { Workspace.existing(byName: $0) }
                        ?? workspace
                    // The MRU of the workspace being rebound INTO, which on the minimized pass is
                    // not `workspace`. Coming back from minimized is not the user picking this
                    // window, so it must not displace whatever that workspace's focus falls back to.
                    let mruBefore = target.mostRecentWindowRecursive
                    try await exitMacOsNativeUnconventionalState(window: window, prevParentKind: prevParentKind, workspace: target)
                    restoreMru(mruBefore, movedWindow: window)
                }
        }
    }
}

/// Puts a workspace's most-recent window back after a bookkeeping rebind moved it.
///
/// Skips the window that just moved -- it left, or it arrived, and either way it is not what the
/// workspace's focus should fall back to. Skips an unbound node too: the window that moved may be
/// the one that was most recent, and `markAsMostRecentChild` on a detached node does nothing useful.
@MainActor
private func restoreMru(_ mruBefore: Window?, movedWindow: Window) {
    guard let mruBefore, mruBefore !== movedWindow, mruBefore.parent != nil else { return }
    mruBefore.markAsMostRecentChild()
}

/// The native state a window's place in the tree already records: the answer that moves nothing.
///
/// What `MacWindow` reports when its app does not answer. Reported as "neither fullscreen nor minimized",
/// as it used to be, a timeout pulled a minimized or fullscreen window out of its container and tiled it,
/// then put it back once the app answered -- a window->workspace change every time an app stalled.
@MainActor func nativeStateTheTreeRecords(for window: Window) -> (fullscreen: Bool, minimized: Bool) {
    switch window.parent?.cases {
        case .macosFullscreenWindowsContainer: (true, false)
        case .macosMinimizedWindowsContainer: (false, true)
        default: (false, false)
    }
}

@MainActor
func exitMacOsNativeUnconventionalState(window: Window, prevParentKind: NonLeafTreeNodeKind, workspace: Workspace) async throws {
    window.layoutReason = .standard
    switch prevParentKind {
        case .workspace:
            window.bindAsFloatingWindow(to: workspace)
        case .tilingContainer:
            try await window.relayoutWindow(on: workspace, forceTile: true)
        case .macosPopupWindowsContainer: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            try await window.relayoutWindow(on: workspace)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer: // wtf case, should never be possible. But If encounter it, let's just re-layout window
            try await window.relayoutWindow(on: workspace)
    }
}
