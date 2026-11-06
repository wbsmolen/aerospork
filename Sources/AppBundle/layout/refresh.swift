import AppKit
import Common

@MainActor
var activeRefreshTask: Task<(), any Error>? = nil // Made internal for RefreshDebouncer access

@MainActor
let refreshDebouncer = RefreshDebouncer()

@MainActor
func runRefreshSessionDebounced(
    _ event: RefreshSessionEvent,
    screenIsDefinitelyUnlocked: Bool,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) {
    refreshDebouncer.debounce(
        event: event,
        screenIsDefinitelyUnlocked: screenIsDefinitelyUnlocked,
        optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces,
    )
}

@MainActor
func runRefreshSession(
    _ event: RefreshSessionEvent,
    screenIsDefinitelyUnlocked: Bool, // todo rename
    optimisticallyPreLayoutWorkspaces: Bool = false,
    debounce: Bool = true, // New parameter to control debouncing
) {
    if debounce {
        // Use debounced refresh for most cases
        runRefreshSessionDebounced(event, screenIsDefinitelyUnlocked: screenIsDefinitelyUnlocked, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
    } else {
        // Immediate refresh for critical operations
        if screenIsDefinitelyUnlocked { resetClosedWindowsCache() }
        activeRefreshTask?.cancel()
        activeRefreshTask = Task { @MainActor in
            try checkCancellation()
            try await runRefreshSessionBlocking(event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
        }
    }
}

@MainActor
func runRefreshSessionBlocking(
    _ event: RefreshSessionEvent,
    layoutWorkspaces shouldLayoutWorkspaces: Bool = true,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) async throws {
    let startTime = Date()
    debugLog("REFRESH: Starting blocking refresh for event: \(event)")

    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer {
        signposter.endInterval(#function, state)
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        debugLog("REFRESH: Completed blocking refresh in \(String(format: "%.1f", elapsed))ms")
    }
    if !TrayMenuModel.shared.isEnabled { return }
    try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            MacApp.timedOutThisPass = []
            try await syncFocusFromMacOs()

            if shouldLayoutWorkspaces && optimisticallyPreLayoutWorkspaces { try await layoutWorkspaces() }

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

    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer {
        signposter.endInterval(#function, state)
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        debugLog("SESSION: Completed in \(String(format: "%.1f", elapsed))ms")
    }
    activeRefreshTask?.cancel() // Give priority to runSession
    activeRefreshTask = nil
    return try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            resetClosedWindowsCache()
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

            let focusAfter = focus.windowOrNil

            updateTrayText()
            try await layoutWorkspaces()
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
            runRefreshSession(event, screenIsDefinitelyUnlocked: false, debounce: false) // Don't debounce within critical sessions
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

@MainActor
private func refresh() async throws {
    let mapping = try await MacApp.refreshAllAndGetAliveWindowIds(frontmostAppBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    // Set, not Array: this is membership-tested once per window below, so an Array made it O(W^2).
    let aliveWindowIds = Set(mapping.values.flatMap { $0 })

    for window in MacWindow.allWindows {
        if !aliveWindowIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false)
        }
    }
    for (app, windowIds) in mapping {
        for windowId in windowIds {
            if MacWindow.allWindowsMap[windowId] == nil {
                try await MacWindow.getOrRegister(windowId: windowId, macApp: app)
            }
        }
    }

    // Garbage collect workspaces after apps, because workspaces contain apps.
    Workspace.garbageCollectUnusedWorkspaces()
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
/// Not `RefreshDebouncer`: every new event cancels its pending task, so a retry queued there is
/// replaced by a refresh that fires too early to help and never comes back. Each call is its own
/// one-shot, so callers bound how many they make.
@MainActor func scheduleFollowUpRefresh(after delay: TimeInterval, _ reason: String) {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(delay))
        if !TrayMenuModel.shared.isEnabled { return }
        runRefreshSession(.globalObserver(reason), screenIsDefinitelyUnlocked: false)
    }
}

/// Runs `body` where the caller's cancellation cannot reach it.
///
/// For work that must not stop halfway. An `on-window-detected` rule is a sequence of commands, none
/// of them idempotent, and a refresh is cancelled whenever a newer event arrives. Cancelled between
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

@MainActor
private func layoutWorkspaces() async throws {
    if !TrayMenuModel.shared.isEnabled {
        for workspace in Workspace.all {
            workspace.allLeafWindowsRecursive.compactMap { $0 as? MacWindow }.forEach { $0.unhideFromCorner() }
            try await workspace.layoutWorkspace() // Unhide tiling windows from corner
        }
        return
    }
    let monitors = monitors

    // to reduce flicker, first unhide visible workspaces, then hide invisible ones
    for monitor in monitors {
        let workspace = monitor.activeWorkspace
        workspace.allLeafWindowsRecursive.compactMap { $0 as? MacWindow }.forEach { $0.unhideFromCorner() }
        try await workspace.layoutWorkspace()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        let monitor = workspace.workspaceMonitor
        let others = monitors.map(\.rect).filter { $0.topLeftCorner != monitor.rect.topLeftCorner }
        for window in workspace.allLeafWindowsRecursive {
            try await (window as? MacWindow)?.hideInCorner(on: monitor.visibleRect, otherMonitors: others)
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
