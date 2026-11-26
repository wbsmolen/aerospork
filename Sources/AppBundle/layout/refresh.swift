import AppKit
import Common

@MainActor
let refreshScheduler = RefreshScheduler { request in
    if request.screenIsDefinitelyUnlocked { resetClosedWindowsCache() }
    // Dropped, not logged: the only thing a refresh throws is its own cancellation.
    try? await runRefreshSessionBlocking(request.event, optimisticallyPreLayoutWorkspaces: request.optimisticallyPreLayoutWorkspaces)
}

@MainActor
let sessionGate = FifoGate()

@MainActor
func runRefreshSession(
    _ event: RefreshSessionEvent,
    screenIsDefinitelyUnlocked: Bool,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) {
    refreshScheduler.request(RefreshRequest(
        event: event,
        screenIsDefinitelyUnlocked: screenIsDefinitelyUnlocked,
        optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces,
    ))
}

@MainActor
func runRefreshSessionBlocking(
    _ event: RefreshSessionEvent,
    layoutWorkspaces shouldLayoutWorkspaces: Bool = true,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) async throws {
    let startTime = Date()
    debugLog("REFRESH: Starting blocking refresh for event: \(event)")

    let state = signposter.beginInterval(#function, id: signposter.makeSignpostID(), "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer {
        signposter.endInterval(#function, state)
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        debugLog("REFRESH: Completed blocking refresh in \(String(format: "%.1f", elapsed))ms")
    }
    if !TrayMenuModel.shared.isEnabled { return }
    // Before anything collects windows or saves the memory file. See `noteTrustLost`.
    guard AXIsProcessTrusted() else { noteTrustLost(); return }
    try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            MacApp.timedOutThisPass = []
            try await syncFocusFromMacOs()
            // Before anything parks a sticky window. After cmd-tab to another workspace, the pre-layout below would
            // park it and the full layout bring it back.
            followVisibleWorkspaces()

            // Shows the workspace that became visible and parks what left the screen. Windows parked already wait for
            // the full layout below: their jobs would queue on each app's thread ahead of the enumeration `refresh()`.
            if shouldLayoutWorkspaces && optimisticallyPreLayoutWorkspaces { try await layoutWorkspaces(parkOnlyUnparked: true) }

            refreshModel()
            try await refresh()
            gcMonitors()

            updateTrayText()
            try await normalizeLayoutReason()
            if shouldLayoutWorkspaces { try await layoutWorkspaces() }
            // Here as well as at quit: a crash, a force quit and `killall -9` never reach the quit
            // path, and those are the restarts where remembering is worth the most. The snapshot is
            // one dictionary walk and returns early when nothing changed; the write is off-thread.
            WorkspaceMemory.save()
        }
    }
}

@MainActor
func runSession<T>(
    _ event: RefreshSessionEvent,
    _ token: RunSessionGuard,
    body: @MainActor () async throws -> T,
) async throws -> T {
    let startTime = Date()
    debugLog("SESSION: Starting session for event: \(event)")

    let state = signposter.beginInterval(#function, id: signposter.makeSignpostID(), "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer {
        signposter.endInterval(#function, state)
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        debugLog("SESSION: Completed in \(String(format: "%.1f", elapsed))ms")
    }
    let session = refreshScheduler.sessionWillStart() // Give priority to runSession
    defer { refreshScheduler.sessionDidEnd(session) }
    let ticket = await sessionGate.enter()
    refreshScheduler.sessionDidAcquireGate(session)
    defer { sessionGate.leave(ticket) }
    try checkCancellation() // superseded while queued, e.g. by the next step of a mouse drag
    return try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            resetClosedWindowsCache()
            // The ways a user changes a layout, for which see `WorkspaceMemory.restoreLayout`. A click isn't
            // one, a drag is `.ax`, and `.socketServer` is decided by the command, because a status bar
            // asking what is on screen isn't one either.
            switch event {
                case .hotkeyBinding, .menuBarButton, .ax, .resetManipulatedWithMouse: WorkspaceMemory.stopRestoringLayouts()
                default: break
            }
            MacApp.timedOutThisPass = []

            try await syncFocusFromMacOs()

            refreshModel()
            // AFTER `refreshModel()`, not before. That call is "catch the model up before we start",
            // and it rebinds tree nodes -- which moves the MRU, which moves the derived `focus`.
            // Reading the baseline before it therefore attributed the model's own catch-up to the
            // body, and the push below raised a window nobody asked for.
            let focusBefore = focus.windowOrNil
            debugLog("SESSION: Executing body")
            let result = try await body()
            refreshModel()

            updateTrayText()
            try await layoutWorkspaces()
            // After layout, which awaits: this is what gets pushed to macOS, so it must be the latest.
            let focusAfter = focus.windowOrNil
            // By window id, not by identity. `TreeNode.==` is `===`, so a window garbage collected
            // and re-registered during the session is a different object with the same id, and that
            // alone used to fire a focus request.
            //
            // Do not also skip when `lastKnownNativeFocusedWindowId` already names the target.
            // `updateFocusCache` deliberately does NOT update that variable while one of our own
            // requests is in flight, so it can name a window macOS is about to move away from; skipping
            // on it would drop a focus the user just asked for.
            if focusBefore?.windowId != focusAfter?.windowId {
                debugLog("SESSION: Focus changed from \(focusBefore?.windowId ?? 0) to \(focusAfter?.windowId ?? 0)")
                if !event.isUserInitiated {
                    AppLog.session.notice("focus synced to macOS by \(event.description, privacy: .public): \(focusBefore?.windowId ?? 0, privacy: .public) -> \(focusAfter?.windowId ?? 0, privacy: .public)")
                }
                focusAfter?.nativeFocus() // syncFocusToMacOs
            }
            runRefreshSession(event, screenIsDefinitelyUnlocked: false)
            return result
        }
    }
}

struct RunSessionGuard: Sendable {
    @MainActor
    static var isServerEnabled: RunSessionGuard? { TrayMenuModel.shared.isEnabled ? forceRun : nil }
    @MainActor
    static func isServerEnabled(orIsEnableCommand command: (any Command)?) -> RunSessionGuard? {
        command is EnableCommand ? .forceRun : .isServerEnabled
    }
    @MainActor
    static var checkServerIsEnabledOrDie: RunSessionGuard { .isServerEnabled ?? dieT("server is disabled") }
    static let forceRun = RunSessionGuard()
    private init() {}
}

@MainActor
func refreshModel() {
    // First: the collection below then releases a workspace whose only window was sticky, and the focus
    // callbacks see the move together with the switch that caused it, not as a focus change of its own.
    followVisibleWorkspaces()
    Workspace.garbageCollectUnusedWorkspaces()
    // Deliberately BEFORE layoutWorkspaces(), despite the temptation to move it after.
    //
    // `on-focused-workspace-changed` runs commands, and `move-mouse window-lazy-center` reads
    // `lastAppliedLayoutPhysicalRect`, which layout is what writes -- so firing the callback here
    // can hand it a frame from before the switch. Moving this call after `layoutWorkspaces()` was
    // tried and REVERTED: over 20 workspace switches the mouse got marginally better (3 misses -> 2)
    // while focus got worse (0 misses -> 2), because the callback spawns a nested `runSession` that
    // cancels the in-flight refresh, and doing that later in the cycle races differently. A wash
    // within sampling noise, on a concurrency-sensitive path -- not worth keeping unvalidated.
    //
    // The stale-frame symptom is handled where it can be handled safely instead: `move-mouse`
    // rejects a rect that is not on the target workspace's monitor (MoveMouseCommand.swift).
    checkOnFocusChangedCallbacks()
    normalizeContainers()
}

/// The windows `sticky` pinned, by id. Not cleared when a window is collected: the lock screen collects live
/// windows, and they come back with the same id. Ids are never reused within a WindowServer session.
/// ponytail: a closed sticky window costs one lookup per refresh until AeroSpork restarts; prune if that adds up.
@MainActor var stickyWindowIds: Set<UInt32> = []

/// Moves each sticky window off a workspace that left the screen, onto the one its monitor shows now, where it
/// keeps its frame. Here rather than in `setActiveWorkspace`, which focus, monitor rearranges and the restores all
/// call, sometimes halfway through rebuilding the tree: one pass per refresh covers every way the visible workspace
/// changes. An empty set is the whole cost for anyone without a sticky window.
@MainActor
func followVisibleWorkspaces() {
    for id in stickyWindowIds {
        guard let window = Window.get(byId: id) else { continue }
        switch window.parent {
            case let workspace as Workspace:
                if workspace.isVisible { continue }
                let target = workspace.workspaceMonitor.activeWorkspace
                if target == workspace { continue }
                // Not the target's focus fallback, unless it has nothing else: the switch goes where it went before.
                let mru = target.mostRecentWindowRecursive
                window.bindAsFloatingWindow(to: target)
                mru?.markAsMostRecentChild()
            case is TilingContainer:
                window.isSticky = false // tiled since: a sticky window is a floating one
            default:
                continue // minimized, hidden or native fullscreen: macOS has it, and `takeAwaySlot` brings it back
        }
    }
}

@MainActor
private func refresh() async throws {
    if shouldResetMouseManipulation(flag: currentlyManipulatedWithMouseWindowId != nil, buttonDown: isLeftMouseButtonDown) {
        try await resetManipulatedWithMouseIfPossible()
    }
    let mapping = try await MacApp.refreshAllAndGetAliveWindowIds(frontmostAppBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    // Set, not Array: this is membership-tested once per window below, so an Array made it O(W^2).
    let aliveWindowIds = Set(mapping.values.flatMap { $0 })

    var collected = 0
    for window in MacWindow.allWindows {
        if !aliveWindowIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false)
            collected += 1
        }
    }
    // Whether lock-aware GC is needed at all: one record if windows die while the screen is locked. A query,
    // not a flag kept from notifications, which one missed unlock would leave stuck. About 0.3 ms, so only here.
    if collected > 0, (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] != nil {
        AppLog.session.notice("collected \(collected, privacy: .public) windows while the screen is locked")
    }
    for (app, windowIds) in mapping {
        for windowId in windowIds {
            if MacWindow.allWindowsMap[windowId] == nil {
                try await MacWindow.getOrRegister(windowId: windowId, macApp: app)
            }
        }
    }

    // Only now. A selected tab that died above handed its tile on by what this said last time.
    backgroundTabs = currentBackgroundTabs()

    // Garbage collect workspaces after apps, because workspaces contain apps.
    Workspace.garbageCollectUnusedWorkspaces()
}

@MainActor
private func currentBackgroundTabs() -> [UInt32: UInt32] {
    MacApp.allAppsMap.values.reduce(into: [:]) { $0.merge($1.backgroundTabsSeen) { first, _ in first } }.filter { tab, selected in
        // A new window isn't registered while the mouse is down, and a tab holding the tile keeps it until
        // whatever replaces it is. Others are out of the tiles already and stay out.
        MacWindow.allWindowsMap[tab] != nil && (MacWindow.allWindowsMap[selected] != nil || MacWindow.allWindowsMap[tab]?.layoutReason != .standard)
    }
}

func refreshObs(_ obs: AXObserver, ax: AXUIElement, notif: CFString, data: UnsafeMutableRawPointer?) {
    let notif = notif as String
    Task { @MainActor in
        if !TrayMenuModel.shared.isEnabled { return }
        runRefreshSession(.ax(notif), screenIsDefinitelyUnlocked: false)
    }
}

/// A refresh some time from now that nothing else would trigger, and that no later event cancels.
///
/// Each call is its own one-shot, so callers bound how many they make. `stillNeeded` is asked when the
/// delay is up, so a retry that has become pointless costs no refresh.
@MainActor func scheduleFollowUpRefresh(
    after delay: TimeInterval,
    _ reason: String,
    if stillNeeded: @escaping @MainActor () -> Bool = { true },
) {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(delay))
        if !TrayMenuModel.shared.isEnabled || !stillNeeded() { return }
        runRefreshSession(.globalObserver(reason), screenIsDefinitelyUnlocked: false)
    }
}

/// Runs `body` where the caller's cancellation cannot reach it.
///
/// For work that must not stop halfway. An `on-window-detected` rule is a sequence of commands, none
/// of them idempotent, and a refresh is cancelled whenever a session starts. Cancelled between
/// `layout tiling` and `move-node-to-workspace`, the window was left tiled on the wrong workspace --
/// and never retried, because by then it was registered. The caller still sees its own cancellation
/// at its next check.
@MainActor func shieldedFromCancellation(_ body: sending @escaping @MainActor () async throws -> Void) async throws {
    try await Task { @MainActor in try await body() }.value
}

/// Where to park a window of an invisible workspace: hung off an edge of its own monitor, a `sliver`
/// left on it because macOS pulls a window that is wholly off screen back on. The bottom corners come
/// first (a 1 pt sliver at the corner), then the right and left edges just under the menu bar (a 1 pt
/// column).
///
/// The only constraint that matters is that the parked window reaches *no other monitor* -- there it is
/// in plain view on another workspace, and clicking it switches to its workspace. Only bottom corners
/// were tried once, so a monitor whose both bottom corners touch a display below it parked every hidden
/// window on that display. `size` is the window's own: a corner free for a small window is not free for
/// a tall one. When every spot reaches another monitor, the one that shows least of the window wins.
func hideSpot(for size: CGSize, on v: Rect, otherMonitors: [Rect], sliver: CGFloat) -> CGPoint {
    let right = v.maxX - sliver
    let left = v.minX + sliver - size.width
    // macOS keeps a title bar on some screen, so a window hung below a monitor with nothing under it is
    // lifted back up -- by how much is its call. Test the corners as if lifted by up to 10% of the
    // monitor's height, the margin the corner probes always allowed, so a neighbour beside the corner
    // counts. The edge spots start under the menu bar and are never lifted.
    let lift = v.height * 0.1
    let candidates: [(spot: CGPoint, lift: CGFloat)] = [
        (CGPoint(x: right, y: v.maxY - sliver), lift),
        (CGPoint(x: left, y: v.maxY - sliver), lift),
        (CGPoint(x: right, y: v.minY), 0),
        (CGPoint(x: left, y: v.minY), 0),
    ]
    func overlap(_ c: (spot: CGPoint, lift: CGFloat)) -> CGFloat {
        otherMonitors.reduce(0) { sum, m in
            let w = min(c.spot.x + size.width, m.maxX) - max(c.spot.x, m.minX)
            let h = min(c.spot.y + size.height, m.maxY) - max(c.spot.y - c.lift, m.minY)
            return sum + max(w, 0) * max(h, 0)
        }
    }
    return (candidates.first { overlap($0) == 0 } ?? candidates.min { overlap($0) < overlap($1) }!).spot
}

/// Which windows of an invisible workspace a layout parks. Not a native fullscreen window: macOS ignores the move,
/// so its frame never matches and it would be rewritten on every refresh, for as long as it stays fullscreen. Nor
/// a background tab, which gets the group's frame back when it's selected, wherever it was put in the meantime.
/// With `onlyUnparked`, not a window parked already, which only needs the re-check that a full layout gives it.
func shouldPark(inNativeFullscreen: Bool, isBackgroundTab: Bool, isParked: Bool, onlyUnparked: Bool) -> Bool {
    !inNativeFullscreen && !isBackgroundTab && !(onlyUnparked && isParked)
}

@MainActor
func layoutWorkspaces(parkOnlyUnparked: Bool = false) async throws {
    // No screens: every frame would be computed against a placeholder rect. The reconnect lays out again.
    let monitors = monitors
    if monitors.isEmpty { return }
    if !TrayMenuModel.shared.isEnabled {
        for workspace in Workspace.all {
            workspace.allLeafWindowsRecursive.compactMap { $0 as? MacWindow }.forEach { $0.unhideFromCorner() }
            try await workspace.layoutWorkspace() // Unhide tiling windows from corner
        }
        return
    }

    // to reduce flicker, first unhide visible workspaces, then hide invisible ones
    for monitor in monitors {
        let workspace = monitor.activeWorkspace
        workspace.allLeafWindowsRecursive.compactMap { $0 as? MacWindow }.forEach { $0.unhideFromCorner() }
        try await workspace.layoutWorkspace()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        let monitor = workspace.workspaceMonitor
        let others = monitors.map(\.rect).filter { $0.topLeftCorner != monitor.rect.topLeftCorner }
        for window in workspace.allLeafWindowsRecursive.compactMap({ $0 as? MacWindow }) where shouldPark(
            inNativeFullscreen: window.parent is MacosFullscreenWindowsContainer,
            isBackgroundTab: window.isBackgroundTab,
            isParked: window.isHiddenInCorner,
            onlyUnparked: parkOnlyUnparked,
        ) {
            try await window.hideInCorner(on: monitor.visibleRect, otherMonitors: others)
        }
    }
}

@MainActor
private func normalizeContainers() {
    // Can't do it only for visible workspace because most of the commands support --window-id and --workspace flags
    for workspace in Workspace.all {
        workspace.normalizeContainers()
    }
}
