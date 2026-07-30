import AppKit
import Common

/// Per-element AX message timeout, in seconds.
///
/// The AX default is 6s. A single wedged app therefore blocked a refresh -- and every task parked
/// behind its registration -- for 6s, i.e. 120 debounce windows. `AXUIElementSetMessagingTimeout`
/// is per-object (only the system-wide element sets a process-wide default), so it is applied to
/// both the app element and every window element we hold on to.
///
/// 1s is chosen as ~100x a healthy AX round trip (single-digit ms even for slow Electron apps), so
/// it cannot fail a responsive app, while bounding a wedged one to 1s instead of 6s.
private let axMessagingTimeout: Float = 1.0

// Potential alternative implementation
// https://github.com/swiftlang/swift-evolution/blob/main/proposals/0392-custom-actor-executors.md
// (only available since macOS 14)
final class MacApp: AbstractApp {
    /*conforms*/ let pid: Int32
    /*conforms*/ let bundleId: String?
    let nsApp: NSRunningApplication
    let isZoom: Bool
    private let axApp: ThreadGuardedValue<AXUIElement>
    private let appAxSubscriptions: ThreadGuardedValue<[AxSubscription]> // keep subscriptions in memory
    private let windows: ThreadGuardedValue<[UInt32: AxWindow]> = .init([:])
    private var thread: Thread?
    private var setFrameJobs: [UInt32: RunLoopJob] = [:]
    @MainActor private static var focusJob: RunLoopJob? = nil

    /*conforms*/ var name: String? { nsApp.localizedName }
    /*conforms*/ var execPath: String? { nsApp.executableURL?.path }
    /*conforms*/ var bundlePath: String? { nsApp.bundleURL?.path }

    // todo think if it's possible to fold this global mutable state into the tree
    //      and make deinitialization automatic in deinit
    @MainActor static var allAppsMap: [pid_t: MacApp] = [:]
    /// Registrations currently in flight. Not private: the tests drive the park/unpark paths of
    /// `awaitRegistration` through it, without needing a real app.
    @MainActor static var wipPids: Set<pid_t> = []
    /// Callers parked waiting on an in-flight registration for a pid, resumed when it publishes
    /// into `allAppsMap`. Carries no payload: `MacApp` is not Sendable, so waiters re-read the map
    /// on the main actor after waking. Keyed by waiter id so a cancelled waiter can remove exactly
    /// its own continuation and nobody else's.
    @MainActor private static var registrationWaiters: [pid_t: [Int: CheckedContinuation<Void, Never>]] = [:]
    @MainActor private static var nextWaiterId = 0

    /// Negative cache for pids whose `bulkSubscribe` came back empty.
    ///
    /// `refreshAllAndGetAliveWindowIds` calls `getOrRegister` for every `.regular` running app on
    /// every refresh, and a failed registration leaves nothing behind in `allAppsMap` -- so an app
    /// we cannot subscribe to used to cost a fresh `Thread` + `AXUIElementCreateApplication` +
    /// `AXObserverCreate` on every single refresh, forever.
    ///
    /// Never-retrying would be wrong: an app that is still launching becomes subscribable a moment
    /// later. Hence backoff -- first retry after 1s (short enough that a window of a just-launched
    /// app is tiled before the user notices), doubling to a 30s ceiling for apps that simply have
    /// no usable AX interface. At the ceiling that is ~1 probe/30s instead of ~20/s under the 50ms
    /// refresh debounce.
    @MainActor private static var failedPids: [pid_t: (nextAttempt: Date, backoff: TimeInterval, launchDate: Date?)] = [:]
    private static let registrationRetryMinDelay: TimeInterval = 1
    private static let registrationRetryMaxDelay: TimeInterval = 30

    /// Park until the in-flight registration for `pid` completes, or until the calling Task is
    /// cancelled.
    ///
    /// Cancellation matters: `bulkSubscribe` talks to an app that may be wedged, and every refresh
    /// parks a `withThrowingTaskGroup` child here per app. Without unparking on cancel, a cancelled
    /// refresh Task stayed alive -- holding its entire child set -- until the AX timeout expired,
    /// so cancelled refreshes piled up and were released as a thundering herd.
    @MainActor static func awaitRegistration(of pid: pid_t) async {
        let id = nextWaiterId
        nextWaiterId &+= 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                registrationWaiters[pid, default: [:]][id] = cont
                // Two ways this park could never be woken. Both are handled right here rather than
                // by the fragile "there must be no suspension point between `wipPids.insert(pid)`
                // and this line" invariant the previous version relied on:
                //   1. the registration already published -- its waiter drain ran before our
                //      continuation existed. `wipPids` is cleared in that same drain, so
                //      "not in flight" is exactly "already published".
                //   2. cancellation landed before `onCancel` below was installed, so the handler
                //      already ran and found nothing to remove.
                // Resuming from inside the continuation body is legal; it returns without parking.
                if !wipPids.contains(pid) || Task.isCancelled {
                    resumeRegistrationWaiter(pid, id)
                }
            }
        } onCancel: {
            // `onCancel` is non-isolated, so it has to hop. Both removal sites run on the main
            // actor and resume only what they removed, so the continuation resumes exactly once.
            Task { @MainActor in resumeRegistrationWaiter(pid, id) }
        }
    }

    @MainActor private static func resumeRegistrationWaiter(_ pid: pid_t, _ id: Int) {
        registrationWaiters[pid]?.removeValue(forKey: id)?.resume()
        if registrationWaiters[pid]?.isEmpty == true { registrationWaiters.removeValue(forKey: pid) }
    }

    private init(_ nsApp: NSRunningApplication, _ axApp: AXUIElement, _ axSubscriptions: [AxSubscription], _ thread: Thread) {
        self.nsApp = nsApp
        self.axApp = .init(axApp)
        self.isZoom = nsApp.bundleIdentifier == "us.zoom.xos"
        self.pid = nsApp.processIdentifier
        self.bundleId = nsApp.bundleIdentifier
        assert(!axSubscriptions.isEmpty)
        self.appAxSubscriptions = .init(axSubscriptions)
        self.thread = thread
    }

    @MainActor
    @discardableResult
    static func getOrRegister(_ nsApp: NSRunningApplication) async throws -> MacApp? {
        // Don't perceive any of the lock screen windows as real windows
        // Otherwise, false positive ax notifications might trigger that lead to gcWindows
        if nsApp.bundleIdentifier == lockScreenAppBundleId { return nil }
        let pid = nsApp.processIdentifier

        if let existing = allAppsMap[pid] { return existing }
        try checkCancellation()
        // Someone else is already registering this pid -- park instead of polling for them.
        if wipPids.contains(pid) {
            await awaitRegistration(of: pid)
            try checkCancellation()
            return allAppsMap[pid]
        }
        if let failure = failedPids[pid] {
            if failure.launchDate != nsApp.launchDate {
                // pid reuse. Otherwise a brand new process would inherit the dead one's backoff
                // and stay invisible to us for up to 30s.
                failedPids.removeValue(forKey: pid)
            } else if Date.now < failure.nextAttempt {
                return nil
            }
        }
        let launchDate = nsApp.launchDate

        // This used to be a `while true` that slept 100ms per iteration waiting for the spawned
        // thread to publish into allAppsMap. Because the publish happens in a hopped
        // `Task { @MainActor }`, the first re-poll always lost the race, so registering a single
        // app cost 100ms minimum and 200ms typically. getNativeFocusedWindow() calls this at the
        // top of every session, which made it the largest single cost of a workspace switch --
        // far larger than the AX traffic. Now registration wakes its waiters directly.
        //
        // Keep this insert and the `awaitRegistration` below in the same synchronous run if you
        // can -- but correctness no longer depends on it: `awaitRegistration` re-checks `wipPids`
        // after installing its continuation and unparks itself if the publish already happened.
        wipPids.insert(pid)
        let thread = Thread {
            $axTaskLocalAppThreadToken.withValue(AxAppThreadToken(pid: pid, idForDebug: nsApp.idForDebug)) {
                let axApp = AXUIElementCreateApplication(nsApp.processIdentifier)
                _ = AXUIElementSetMessagingTimeout(axApp, axMessagingTimeout)
                let handlers: HandlerToNotifKeyMapping = [
                    (refreshObs, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification]),
                ]
                let job = RunLoopJob()
                let subscriptions = (try? AxSubscription.bulkSubscribe(nsApp, axApp, job, handlers)) ?? []
                let isGood = !subscriptions.isEmpty
                let app = isGood ? MacApp(nsApp, axApp, subscriptions, Thread.current) : nil
                Task { @MainActor in
                    allAppsMap[pid] = app // nil removes the key -- a failed registration publishes nothing
                    if isGood {
                        failedPids.removeValue(forKey: pid)
                    } else {
                        let backoff = failedPids[pid].map { min($0.backoff * 2, registrationRetryMaxDelay) } ?? registrationRetryMinDelay
                        failedPids[pid] = (nextAttempt: .now + backoff, backoff: backoff, launchDate: launchDate)
                    }
                    wipPids.remove(pid)
                    for (id, _) in registrationWaiters[pid] ?? [:] { resumeRegistrationWaiter(pid, id) }
                }
                // Must come after the publish above: this parks the thread for its lifetime.
                if isGood {
                    CFRunLoopRun()
                }
            }
        }
        thread.name = "AxAppThread \(nsApp.idForDebug)"
        thread.start()
        await awaitRegistration(of: pid)
        try checkCancellation()
        return allAppsMap[pid]
    }

    @MainActor
    func closeAndUnregisterAxWindow(_ windowId: UInt32) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        _ = withWindowAsync(windowId) { [windows] window, job in
            guard let closeButton = window.get(Ax.closeButtonAttr) else { return }
            guard let castedCloseButton = closeButton.cast else { return }
            if AXUIElementPerformAction(castedCloseButton, kAXPressAction as CFString) == .success {
                windows.threadGuarded.removeValue(forKey: windowId)
            }
        }
    }

    @MainActor
    func getAxSize(_ windowId: UInt32) async throws -> CGSize? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.sizeAttr)
        }
    }

    // todo merge together with detectNewWindows
    @MainActor
    func getFocusedWindow() async throws -> Window? {
        let windowId = try await thread?.runInLoop { [nsApp, axApp, windows] job in
            let axWindow = try axApp.threadGuarded.get(Ax.focusedWindowAttr)
                .flatMap {
                    guard let casted = $0.ax.cast else { return nil as AxWindow? }
                    return try windows.threadGuarded.getOrRegisterAxWindow(windowId: $0.windowId, casted, nsApp, job)
                }
            return axWindow?.windowId
        }
        guard let windowId else { return nil }
        return try await MacWindow.getOrRegister(windowId: windowId, macApp: self)
    }

    @MainActor func nativeFocus(_ windowId: UInt32) {
        // Declare the request BEFORE issuing it: the AX calls below run on the app's thread, and
        // `runSession` kicks off another refresh as soon as this returns. Without this, that refresh
        // can read a half-applied focus out of the app and adopt it. See `updateFocusCache`.
        expectNativeFocus(windowId)
        MacApp.focusJob?.cancel()
        MacApp.focusJob = withWindowAsync(windowId) { [nsApp] window, job in
            // Point the APP at this window before touching order or activation. `isMain` and
            // `kAXRaiseAction` only reorder windows -- neither updates `kAXFocusedWindowAttribute`,
            // which is exactly what `getNativeFocusedWindow` reads back. Without that write, focusing
            // a window of an app that also has windows on another workspace left the app still
            // reporting the old one, and the next refresh adopted that and undid the switch.
            setAxFocus(window)
            // Raise so that by the time we activate the app, the window is already on top
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            nsApp.activate(options: .activateIgnoringOtherApps)
        }
    }

    func setAxFrame(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { [axApp] window, job in
            if isFrameSatisfied(window, topLeft, size) { return }
            disableAnimations(app: axApp.threadGuarded) {
                setFrame(window, topLeft, size)
            }
        }
    }

    @MainActor
    func setAxFrameBlocking(_ windowId: UInt32, _ topLeft: CGPoint?, _ size: CGSize?) async throws {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = nil
        try await withWindow(windowId) { [axApp] window, job in
            if isFrameSatisfied(window, topLeft, size) { return }
            disableAnimations(app: axApp.threadGuarded) {
                setFrame(window, topLeft, size)
            }
        }
    }

    func setAxSize(_ windowId: UInt32, _ size: CGSize) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { [axApp] window, job in
            disableAnimations(app: axApp.threadGuarded) {
                _ = window.set(Ax.sizeAttr, size)
            }
        }
    }

    func setAxTopLeftCorner(_ windowId: UInt32, _ point: CGPoint) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { [axApp] window, job in
            // Same no-op guard as setAxFrame. This one matters because hideInCorner calls it for
            // every window of every invisible workspace on every refresh -- previously an
            // unconditional AX position write per hidden window, forever.
            if isFrameSatisfied(window, point, nil) { return }
            disableAnimations(app: axApp.threadGuarded) {
                _ = window.set(Ax.topLeftCornerAttr, point)
            }
        }
    }

    @MainActor
    func getAxWindowsCount() async throws -> Int? {
        try await thread?.runInLoop { [axApp] job in
            axApp.threadGuarded.get(Ax.windowsAttr)?.count
        }
    }

    @MainActor
    func getAxTopLeftCorner(_ windowId: UInt32) async throws -> CGPoint? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.topLeftCornerAttr)
        }
    }

    @MainActor
    func getAxRect(_ windowId: UInt32) async throws -> Rect? {
        try await withWindow(windowId) { window, job in
            guard let topLeftCorner = window.get(Ax.topLeftCornerAttr) else { return nil }
            guard let size = window.get(Ax.sizeAttr) else { return nil }
            return Rect(topLeftX: topLeftCorner.x, topLeftY: topLeftCorner.y, width: size.width, height: size.height)
        }
    }

    @MainActor
    func isWindowHeuristic(_ windowId: UInt32) async throws -> Bool {
        try await withWindow(windowId) { [axApp, bundleId] window, job in
            window.isWindowHeuristic(axApp: axApp.threadGuarded, appBundleId: bundleId)
        } == true
    }

    @MainActor
    func getAxUiElementWindowType(_ windowId: UInt32) async throws -> AxUiElementWindowType {
        try await withWindow(windowId) { [axApp, bundleId] window, job in
            window.getWindowType(axApp: axApp.threadGuarded, appBundleId: bundleId)
        } ?? .window
    }

    @MainActor
    func isDialogHeuristic(_ windowId: UInt32) async throws -> Bool {
        try await withWindow(windowId) { [nsApp] window, job in
            window.isDialogHeuristic(appBundleId: nsApp.bundleIdentifier)
        } == true
    }

    func setNativeFullscreen(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { window, job in
            window.set(Ax.isFullscreenAttr, value)
        }
    }

    func setNativeMinimized(_ windowId: UInt32, _ value: Bool) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = withWindowAsync(windowId) { window, job in
            window.set(Ax.minimizedAttr, value)
        }
    }

    @MainActor
    func dumpWindowAxInfo(windowId: UInt32) async throws -> [String: Json] {
        try await withWindow(windowId) { window, job in
            dumpAxRecursive(window, .window)
        } ?? [:]
    }

    @MainActor
    func dumpAppAxInfo() async throws -> [String: Json] {
        try await thread?.runInLoop { [axApp] job in
            dumpAxRecursive(axApp.threadGuarded, .app)
        } ?? [:]
    }

    @MainActor
    func getAxTitle(_ windowId: UInt32) async throws -> String? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.titleAttr)
        }
    }

    @MainActor
    func isMacosNativeFullscreen(_ windowId: UInt32) async throws -> Bool? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.isFullscreenAttr)
        }
    }

    @MainActor
    func isMacosNativeMinimized(_ windowId: UInt32) async throws -> Bool? {
        try await withWindow(windowId) { window, job in
            window.get(Ax.minimizedAttr)
        }
    }

    /// Both native-state flags in ONE hop to the app's thread.
    ///
    /// `normalizeLayoutReason` needs the pair for every window of every workspace on every refresh,
    /// and asking through `isMacosNativeFullscreen` + `isMacosNativeMinimized` costs two separate
    /// `runInLoop` round trips per window -- two suspensions, two continuations, twice the
    /// opportunity for the refresh to be cancelled mid-window and start over.
    ///
    /// The short-circuit is preserved exactly: `minimized` is not read at all when the window is
    /// fullscreen, because a fullscreen window cannot be minimized and the read is an IPC to a
    /// possibly-wedged app.
    @MainActor
    func macosNativeState(_ windowId: UInt32) async throws -> (fullscreen: Bool, minimized: Bool)? {
        try await withWindow(windowId) { window, job in
            readMacosNativeState(window)
        }
    }

    @MainActor
    static func refreshAllAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [MacApp: [UInt32]] {
        for (_, app) in MacApp.allAppsMap { // gc dead apps
            try checkCancellation()
            if app.nsApp.isTerminated {
                app.destroy()
            }
        }
        return try await withThrowingTaskGroup(of: (pid_t, [UInt32]).self, returning: [MacApp: [UInt32]].self) { group in
            func refreshTheApp(_ nsApp: NSRunningApplication) {
                group.addTask { @Sendable @MainActor in
                    guard let app = try await getOrRegister(nsApp) else { return (nsApp.processIdentifier, []) }
                    return (nsApp.processIdentifier, try await app.refreshAndGetAliveWindowIds(frontmostAppBundleId: frontmostAppBundleId))
                }
            }
            // Register new apps
            for nsApp in NSWorkspace.shared.runningApplications {
                try checkCancellation()
                if nsApp.activationPolicy == .regular {
                    refreshTheApp(nsApp)
                }
            }
            for (_, app) in MacApp.allAppsMap {
                try checkCancellation()
                // "About this Mac" window, TouchID, and a lot of other utility windows
                // We don't monitor them actively as we do for regular apps, but if a window of one of those utility
                // apps got focused it will end up in allAppsMap
                if app.nsApp.activationPolicy != .regular {
                    refreshTheApp(app.nsApp)
                }
            }
            var result: [MacApp: [UInt32]] = [:]
            for try await (pid, windowIds) in group {
                if let app = allAppsMap[pid] {
                    result[app] = windowIds
                }
            }
            return result
        }
    }

    @MainActor
    private func refreshAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [UInt32] {
        if nsApp.isTerminated {
            destroy()
            return []
        }
        guard let thread else { return [] }
        return try await thread.runInLoop { [nsApp, windows, axApp] (job) -> [UInt32] in
            var result: [UInt32: AxWindow] = windows.threadGuarded
            // Second line of defence against lock screen. See the first line of defence: closedWindowsCache
            // Second and third lines of defence are technically needed only to avoid potential flickering
            if frontmostAppBundleId != lockScreenAppBundleId {
                result = try result.filter {
                    try job.checkCancellation()
                    return $0.value.ax.containingWindowId() != nil
                }
            }

            for (id, window) in axApp.threadGuarded.get(Ax.windowsAttr) ?? [] {
                try job.checkCancellation()
                try result.getOrRegisterAxWindow(windowId: id, window, nsApp, job)
            }

            windows.threadGuarded = result
            return Array(result.keys)
        }
    }

    @MainActor
    private func destroy() {
        MacApp.allAppsMap.removeValue(forKey: pid)
        for (_, job) in setFrameJobs {
            job.cancel()
        }
        setFrameJobs = [:]
        thread?.runInLoopAsync { [windows, appAxSubscriptions, axApp] job in
            appAxSubscriptions.destroy() // Destroy AX objects in reverse order of their creation
            windows.destroy()
            axApp.destroy()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        thread = nil // Disallow all future job submissions
    }

    @MainActor
    private func withWindow<T>(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> T?) async throws -> T? {
        try await thread?.runInLoop { [windows] job in
            guard let window = windows.threadGuarded[windowId] else { return nil }
            return try body(window.ax, job)
        }
    }

    private func withWindowAsync(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) -> ()) -> RunLoopJob {
        thread?.runInLoopAsync { [windows] job in
            guard let window = windows.threadGuarded[windowId] else { return }
            body(window.ax, job)
        } ?? .cancelled
    }
}

private class AxWindow {
    let windowId: UInt32
    let ax: AXUIElement
    private let axSubscriptions: [AxSubscription] // keep subscriptions in memory

    private init(windowId: UInt32, _ ax: AXUIElement, _ axSubscriptions: [AxSubscription]) {
        self.windowId = windowId
        self.ax = ax
        assert(!axSubscriptions.isEmpty)
        self.axSubscriptions = axSubscriptions
    }

    static func new(windowId: UInt32, _ ax: AXUIElement, _ nsApp: NSRunningApplication, _ job: RunLoopJob) throws -> AxWindow? {
        let handlers: HandlerToNotifKeyMapping = [
            (refreshObs, [kAXUIElementDestroyedNotification, kAXWindowDeminiaturizedNotification, kAXWindowMiniaturizedNotification]),
            (movedObs, [kAXMovedNotification]),
            (resizedObs, [kAXResizedNotification]),
        ]
        _ = AXUIElementSetMessagingTimeout(ax, axMessagingTimeout)
        let subscriptions = try AxSubscription.bulkSubscribe(nsApp, ax, job, handlers)
        return !subscriptions.isEmpty ? AxWindow(windowId: windowId, ax, subscriptions) : nil
    }
}

extension [UInt32: AxWindow] {
    @discardableResult
    fileprivate mutating func getOrRegisterAxWindow(windowId id: UInt32, _ axWindow: AXUIElement, _ nsApp: NSRunningApplication, _ job: RunLoopJob) throws -> AxWindow? {
        if let existing = self[id] { return existing }
        // Delay new window detection if mouse is down
        // It helps with apps that allow dragging their tabs out to create new windows
        // https://github.com/wbsmolen/aerospork/issues/1001
        if isLeftMouseButtonDown { return nil }

        if let window = try AxWindow.new(windowId: id, axWindow, nsApp, job) {
            self[id] = window
            return window
        } else {
            return nil
        }
    }
}

/// No-op guard: true when the window is already at the target frame, so no AX write is needed.
///
/// AX position/size WRITES are what cost us over DisplayLink/USB (each forces a framebuffer
/// repaint), and layout re-issues them on every refresh even when nothing moved. The reads here hit
/// the app's AX tree (not the display), so they're cheap over USB — and comparing against the
/// window's ACTUAL frame, rather than a cached intended rect, still corrects windows the app or OS
/// moved on their own.
///
/// Callers must check this *before* entering `disableAnimations`: that helper costs a read plus two
/// writes on the app element, so paying it for a frame we then skip defeats the point of the guard.
///
/// Takes `some AxUiElementMock` rather than `AXUIElement` purely so the tests can drive it against
/// an app that ignores, clamps or times out its writes. Every caller passes a concrete
/// `AXUIElement`, so the generic specializes to exactly the previous code.
func isFrameSatisfied(_ window: some AxUiElementMock, _ topLeft: CGPoint?, _ size: CGSize?) -> Bool {
    let tolerance = 1.0
    // Bail on the first disagreement. Each `get` is a cross-thread AX round trip, and the two used
    // to be evaluated unconditionally before being `&&`ed -- so every window that actually needed
    // moving (i.e. every window on the workspace you just switched to) paid a position read whose
    // answer could not change the outcome. See AxWriteTest.testGuardStopsReadingAtFirstDisagreement.
    if let size {
        guard let actual = window.get(Ax.sizeAttr),
              abs(actual.width - size.width) < tolerance, abs(actual.height - size.height) < tolerance
        else { return false }
    }
    if let topLeft {
        guard let actual = window.get(Ax.topLeftCornerAttr),
              abs(actual.x - topLeft.x) < tolerance, abs(actual.y - topLeft.y) < tolerance
        else { return false }
    }
    return true
}

/// The AX writes that hand focus to a window. Extracted from `MacApp.nativeFocus` so the sequence is
/// assertable -- the raise action and `nsApp.activate` around it need a real app thread.
///
/// `kAXFocusedAttribute` first, and it is the load-bearing one: it is what
/// `kAXFocusedWindowAttribute` reports back, which is what `getNativeFocusedWindow` reads. `isMain`
/// only changes which window the app considers primary for ordering.
/// The two AX reads behind `macosNativeState`, over the mockable element seam.
///
/// Extracted so the *read pattern* is assertable: that both flags come from one traversal, and that
/// a fullscreen window is never asked whether it is minimized.
func readMacosNativeState(_ window: some AxUiElementMock) -> (fullscreen: Bool, minimized: Bool) {
    let fullscreen = window.get(Ax.isFullscreenAttr) == true
    // Short-circuit: a fullscreen window is never minimized, and this read is an IPC.
    return (fullscreen, fullscreen ? false : window.get(Ax.minimizedAttr) == true)
}

func setAxFocus(_ window: some AxUiElementMock) {
    window.set(Ax.isFocused, true)
    window.set(Ax.isMainAttr, true)
}

func setFrame(_ window: some AxUiElementMock, _ topLeft: CGPoint?, _ size: CGSize?) {
    // Set size and then the position. The order is important https://github.com/wbsmolen/aerospork/issues/143
    //                                                        https://github.com/wbsmolen/aerospork/issues/335
    if let size { window.set(Ax.sizeAttr, size) }
    if let topLeft { window.set(Ax.topLeftCornerAttr, topLeft) } else { return }
    if let size { window.set(Ax.sizeAttr, size) }
}

// Some undocumented magic
// References: https://github.com/koekeishiya/yabai/commit/3fe4c77b001e1a4f613c26f01ea68c0f09327f3a
//             https://github.com/rxhanson/Rectangle/pull/285
func disableAnimations<T>(app: some AxUiElementMock, _ body: () -> T) -> T {
    let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
    if wasEnabled {
        app.set(Ax.enhancedUserInterfaceAttr, false)
    }
    defer {
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
    return body()
}
