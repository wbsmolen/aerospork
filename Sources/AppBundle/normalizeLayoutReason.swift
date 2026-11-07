import AppKit
import Common

@MainActor
func normalizeLayoutReason() async throws {
    settleBackgroundTabs()
    let zeroAlpha = isUnitTest ? [] : windowIdsWithZeroAlpha().intersection(MacWindow.allWindowsMap.keys)
    if updateTransparentWindowIds(zeroAlpha: zeroAlpha, now: Date()) {
        scheduleFollowUpRefresh(after: 1.1, "transparencyRecheck") // nothing else re-checks once the grace is up
    }
    let states = try await prefetchNativeStates(
        Workspace.all.flatMap(\.allLeafWindowsRecursive) + macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self),
    )
    for workspace in Workspace.all {
        try checkCancellation()
        let windows: [Window] = workspace.allLeafWindowsRecursive
        try await _normalizeLayoutReason(workspace: workspace, windows: windows, states: states)
    }
    try await _normalizeLayoutReason(workspace: focus.workspace, windows: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self), states: states)
    try await validateStillPopups()
}

@MainActor
private func validateStillPopups() async throws {
    for node in macosPopupWindowsContainer.children {
        let popup = (node as! MacWindow)
        if !shouldRecheckPopup(registeredAt: popup.registeredAt, now: Date()) { continue }
        if try await popup.isWindowHeuristic() {
            // The same commitment as registration: once relaid out it is no longer a popup, so this is
            // the only run its rules get.
            try await shieldedFromCancellation {
                let home = popup.workspaceNameAtRegistration.flatMap { Workspace.existing(byName: $0) }
                try await popup.relayoutWindow(on: home ?? focus.workspace)
                try await tryOnWindowDetected(popup)
            }
        }
    }
}

/// A window that is still a popup this long after it appeared is one: re-reading its heuristic on every
/// refresh, forever, is several AX reads per popup. Generous, because an app still drawing its first window
/// looks like a popup too, and on a busy machine that can take a while.
func shouldRecheckPopup(registeredAt: Date, now: Date) -> Bool {
    now.timeIntervalSince(registeredAt) < 30
}

/// Both AX reads for every window concurrently, in one task group. These used to be two sequential
/// `await`s inside the mutation loop, i.e. 2 serialized MainActor<->app-thread round trips per window per
/// refresh, over every window of every workspace -- the dominant cost of a refresh. Same fan-out pattern
/// as MacApp.refreshAllAndGetAliveWindowIds.
@MainActor
private func prefetchNativeStates(_ windows: [Window]) async throws -> [UInt32: (full: Bool, mini: Bool)] {
    try await withThrowingTaskGroup(of: (UInt32, Bool, Bool).self) { group in
        for window in windows {
            group.addTask { @Sendable @MainActor in
                // One hop per window, not two. `macosNativeState` reads both flags inside a single
                // `runInLoop` and keeps the same short-circuit (a fullscreen window is never asked
                // whether it is minimized).
                let state = try await window.macosNativeState()
                return (window.windowId, state.fullscreen, state.minimized)
            }
        }
        var result: [UInt32: (full: Bool, mini: Bool)] = [:]
        for try await (id, full, mini) in group { result[id] = (full, mini) }
        return result
    }
}

@MainActor
private func _normalizeLayoutReason(workspace: Workspace, windows: [Window], states: [UInt32: (full: Bool, mini: Bool)]) async throws {
    for window in windows {
        // The `.standard` branch below is entirely synchronous, so without this a cancelled
        // refresh rebound the whole tree instead of stopping at the first window.
        try checkCancellation()
        // An earlier iteration's await may have let a concurrent session garbage collect this
        // window; binding it below would resurrect a dead node.
        guard window.parent != nil, let state = states[window.windowId] else { continue }

        // Does the prefetched snapshot say we are about to move this window? Everything else is a
        // no-op, and in steady state that is essentially every window -- which is what keeps the
        // re-read below off the hot path. `||` short-circuits, so the app is still only asked
        // whether it is hidden when the window is neither fullscreen nor minimized, same as before.
        let snapshotIsUnconventional = state.full || state.mini ||
            (!config.automaticallyUnhideMacosHiddenApps && window.isMacosAppHidden) || window.isTransparent || window.isBackgroundTab
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
        let isOutOfSight = !isMacosFullscreen && !isMacosMinimized && (window.isTransparent || window.isBackgroundTab)
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
                    window.leaveTilesForMacos(workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER)
                } else if isMacosMinimized {
                    window.layoutReason = .macos(prevParentKind: parent.kind, prevWorkspaceName: prevWorkspaceName)
                    window.leaveTilesForMacos(macosMinimizedWindowsContainer, adaptiveWeight: 1)
                } else if isMacosWindowOfHiddenApp || isOutOfSight {
                    // A transparent window or a background tab is parked with the hidden app's: it keeps
                    // its workspace, and leaves the tiling as a window you cannot see should.
                    window.layoutReason = .macos(prevParentKind: parent.kind, prevWorkspaceName: prevWorkspaceName)
                    window.leaveTilesForMacos(workspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER)
                }
            case .macos(let prevParentKind, let prevWorkspaceName):
                if !isMacosFullscreen && !isMacosMinimized && !isMacosWindowOfHiddenApp && !isOutOfSight {
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

/// Each background tab of a native tab group, with the selected tab of that group.
///
/// A tab group is one window to the user, and macOS makes each tab a window of its own. Tiled as such, every
/// background tab held open a tile with nothing in it. So the selected tab holds the group's one tile, and the
/// others wait out of the tiles, keeping no place of their own: when the selection moves, the new tab takes the
/// old one's place and size exactly. Written by `refresh`, and by `takePlace` so the answer holds until then.
@MainActor var backgroundTabs: [UInt32: UInt32] = [:]

/// Gives each group's tile to its selected tab, before `_normalizeLayoutReason` takes the others out of the tiles.
@MainActor
func settleBackgroundTabs() {
    for (tabId, selectedId) in backgroundTabs.sorted(by: { $0.key < $1.key }) {
        guard let tab = Window.get(byId: tabId), let selected = Window.get(byId: selectedId), tab.isBound, selected.isBound else { continue }
        // A selected tab that has a place of its own is two windows merged into one group: the other's tile closes.
        if tab.holdsTabPlace, selected.layoutReason != .standard {
            selected.takePlace(of: tab)
        } else if tab.nodeWorkspace?.mostRecentWindowRecursive === tab {
            selected.markAsMostRecentChild()
        }
        // A command moved the selected tab. The rest of the group go with it, or they'd keep the old workspace
        // alive, with nothing on it to see.
        if tab.parent is MacosHiddenAppsWindowsContainer, let workspace = selected.nodeWorkspace, tab.nodeWorkspace != workspace {
            let mruBefore = workspace.mostRecentWindowRecursive
            tab.bind(to: workspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
            restoreMru(mruBefore, movedWindow: tab)
        }
    }
}

extension Window {
    /// In the tiles or floating, where a background tab can't stay.
    @MainActor var holdsTabPlace: Bool { layoutReason == .standard && (parent is TilingContainer || parent is Workspace) }

    /// This is a tab of the same group as `tab`, and becomes the group's selected one: it goes where `tab` is, at
    /// its size and with what else made that its place, and `tab` goes behind it.
    @MainActor
    func takePlace(of tab: Window) {
        let wasFocused = focusedWindowId == tab.windowId
        let mruBefore = tab.nodeWorkspace?.mostRecentWindowRecursive
        swapWindows(tab, self)
        swap(&layoutReason, &tab.layoutReason)
        swap(&isFullscreen, &tab.isFullscreen)
        swap(&noOuterGapsInFullscreen, &tab.noOuterGapsInFullscreen)
        nodeWorkspace?.rootTilingContainer.forgetAway { $0 == self.windowId } // it has its place now
        WorkspaceMemory.stopRestoringLayouts() // the file names the tab that held this place, and can't any more
        // Where this was is a place too, if it just opened: a tile of its own, which has to go at once.
        if tab.layoutReason == .standard, let workspace = nodeWorkspace {
            tab.layoutReason = .macos(prevParentKind: tab.parent?.kind ?? .tilingContainer, prevWorkspaceName: workspace.name)
            tab.bind(to: workspace.macOsNativeHiddenAppsWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
        }
        markAsMostRecentChild()
        if wasFocused { _ = focusWindow() } else { restoreMru(mruBefore, movedWindow: tab) }
        for (id, selected) in backgroundTabs where selected == tab.windowId { backgroundTabs[id] = windowId }
        backgroundTabs[windowId] = nil
        backgroundTabs[tab.windowId] = windowId
    }

    /// The selected tab of a group closed. macOS selects another, which needs its tile. Whichever tab this
    /// picks, the next refresh sees which one macOS picked and moves the tile there.
    @MainActor
    func passTabPlaceOn() {
        let heir = backgroundTabs.filter { $0.value == windowId }.keys.max().flatMap { Window.get(byId: $0) }
        heir?.takePlace(of: self)
        backgroundTabs[windowId] = nil
    }
}

/// Managed windows WindowServer has drawn fully transparent (alpha 0) for at least a second.
///
/// AX has no alpha, so such a window looked like any other and was tiled: an empty tile you can neither
/// see nor get rid of (a Chrome PDF window, measured on screen at alpha 0). The second of grace keeps a
/// window that is fading in or out from being parked.
@MainActor private(set) var transparentWindowIds: Set<UInt32> = []
@MainActor private var zeroAlphaSince: [UInt32: Date] = [:]

/// Returns whether a window turned transparent this time, i.e. one whose grace still has to run out.
@MainActor func updateTransparentWindowIds(zeroAlpha: Set<UInt32>, now: Date) -> Bool {
    let isNew = !zeroAlpha.isSubset(of: zeroAlphaSince.keys)
    zeroAlphaSince = zeroAlpha.reduce(into: [:]) { $0[$1] = zeroAlphaSince[$1] ?? now }
    transparentWindowIds = Set(zeroAlphaSince.filter { now.timeIntervalSince($0.value) >= 1 }.keys)
    return isNew
}

/// One WindowServer call per refresh. The on-screen list (~0.3 ms) rather than a lookup of the managed
/// ids (~1.6 ms): a transparent window that matters is one that is on screen.
private func windowIdsWithZeroAlpha() -> Set<UInt32> {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []
    return Set(list.compactMap { info in
        (info[kCGWindowAlpha] as? Double) == 0 ? (info[kCGWindowNumber] as? Int).map(UInt32.init) : nil
    })
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
            if let slot = workspace.rootTilingContainer.takeAwaySlot(of: window.windowId) {
                window.bind(to: slot.parent, adaptiveWeight: slot.adaptiveWeight, index: slot.index)
            } else {
                try await window.relayoutWindow(on: workspace, forceTile: true)
            }
        case .macosPopupWindowsContainer: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            try await window.relayoutWindow(on: workspace)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer: // wtf case, should never be possible. But If encounter it, let's just re-layout window
            try await window.relayoutWindow(on: workspace)
    }
}
