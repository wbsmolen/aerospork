import AppKit
import Common
import os

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
    private let axObserver: ThreadGuardedValue<AXObserver> // one per app; every window subscribes on it
    private let appAxSubscription: ThreadGuardedValue<AxSubscription> // keep the subscription in memory
    private let windows: ThreadGuardedValue<[UInt32: AxWindow]> = .init([:])
    private var thread: Thread?
    private var setFrameJobs: [UInt32: RunLoopJob] = [:]
    /// Not `setFrameJobs`: the layout write that follows would cancel an un-fullscreen still in the queue.
    private var nativeStateJobs: [UInt32: RunLoopJob] = [:]
    @MainActor private static var focusJob: RunLoopJob? = nil
    /// Apps that have already made this refresh pass wait out `axMessagingTimeout`.
    ///
    /// Since #39 a busy app's windows stay in the tree, and a pass asks about each of them in turn --
    /// a frame read per hidden window, a native-state read per window -- on that app's one AX thread.
    /// With the app stopped every one of those waits the full second, so switching away from a few of
    /// its windows could take ten seconds. The answers are "timed out" regardless, so after the first,
    /// the rest of the pass skips the app. Cleared when a pass starts, so an app that recovers is asked
    /// again at once.
    @MainActor static var timedOutThisPass: Set<pid_t> = []
    /// Registered windows the sweep found gone from WindowServer, for the next pass to collect wherever AX
    /// cannot say so: an unreaped zombie, or an element whose remote end died while its app lives. The
    /// `.cannotComplete` such an element answers means "unanswered", not "destroyed" (#39), so only
    /// WindowServer can tell. Ids are never reused, so carrying them to a later pass is safe.
    @MainActor static var pendingDead: Set<UInt32> = []
    /// Since when each app's window list has gone unanswered, and whether that episode has its record yet.
    /// `timedOutThisPass` forgets every pass, so a stopped app left no trace in the logs.
    @MainActor private(set) static var unansweredSince: [pid_t: (since: Date, logged: Bool)] = [:]
    private static let unansweredLogAfter: TimeInterval = 60

    /// Notes whether an app answered its window-list read. True once per episode, when it has gone unanswered
    /// for a minute; an answer ends the episode. Never per refresh, since `AppLog` is kept (#logging).
    @MainActor static func noteAnswer(pid: pid_t, answered: Bool, now: Date) -> Bool {
        if answered {
            unansweredSince.removeValue(forKey: pid)
            return false
        }
        guard let episode = unansweredSince[pid] else {
            unansweredSince[pid] = (now, false)
            return false
        }
        if episode.logged || now.timeIntervalSince(episode.since) < unansweredLogAfter { return false }
        unansweredSince[pid]?.logged = true
        return true
    }

    /*conforms*/ let name: String? // Kept: reading `localizedName` asks LaunchServices, and the menu bar lists every window's app per refresh.
    /*conforms*/ var execPath: String? { nsApp.executableURL?.path }
    /*conforms*/ var bundlePath: String? { nsApp.bundleURL?.path }

    /// This app's background tabs, each with the selected tab of its group, as of the last refresh. See
    /// `backgroundTabs`, which `refresh` builds from these once it has collected the dead.
    @MainActor fileprivate(set) var backgroundTabsSeen: [UInt32: UInt32] = [:]

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
    ///
    /// Not private: the tests plant an entry for a dead pid, to check `forgetFailedRegistrationsOfGoneProcesses`.
    @MainActor static var failedPids: [pid_t: (nextAttempt: Date, backoff: TimeInterval, launchDate: Date?)] = [:]

    /// An entry leaves `failedPids` on a success or a pid reuse, so one for a process that exited stayed forever.
    /// A `kill(pid, 0)` per entry: not only the pass's `gone` set, which misses a process LaunchServices dropped.
    @MainActor static func forgetFailedRegistrationsOfGoneProcesses() {
        failedPids = failedPids.filter { !processIsGone($0.key) }
    }
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

    private init(_ nsApp: NSRunningApplication, _ axApp: AXUIElement, _ axObserver: AXObserver, _ axSubscription: AxSubscription, _ thread: Thread) {
        self.nsApp = nsApp
        self.axApp = .init(axApp)
        self.isZoom = nsApp.bundleIdentifier == "us.zoom.xos"
        self.pid = nsApp.processIdentifier
        self.bundleId = nsApp.bundleIdentifier
        self.name = nsApp.localizedName
        self.axObserver = .init(axObserver)
        self.appAxSubscription = .init(axSubscription)
        self.thread = thread
    }

    @MainActor
    @discardableResult
    static func getOrRegister(_ nsApp: NSRunningApplication) async throws -> MacApp? {
        // Don't perceive any of the lock screen windows as real windows
        // Otherwise, false positive ax notifications might trigger that lead to gcWindows
        if nsApp.bundleIdentifier == lockScreenAppBundleId { return nil }
        // Never our own windows. Registered, the Settings window was bound to whichever workspace was
        // focused and parked off screen on the next switch -- so it "never appeared" (#40).
        if nsApp.processIdentifier == ProcessInfo.processInfo.processIdentifier { return nil }
        // A dead pid, even one still in allAppsMap: `focusedApp` passes on whatever LaunchServices calls
        // frontmost, and a failed registration of it would re-arm the follow-up refreshes. See `isGone`.
        if nsApp.isGone { return nil }
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
                let observer = AXObserver.new(nsApp.processIdentifier, axNotified)
                // Main as well as focused: selecting a native tab changes the main window and not the focused one.
                let subscription = observer.flatMap { AxSubscription.subscribe($0, axApp, [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification]) }
                let app: MacApp?
                if let observer, let subscription {
                    CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
                    app = MacApp(nsApp, axApp, observer, subscription, Thread.current)
                } else {
                    app = nil
                }
                let isGood = app != nil
                Task { @MainActor in
                    allAppsMap[pid] = app // nil removes the key -- a failed registration publishes nothing
                    if isGood {
                        failedPids.removeValue(forKey: pid)
                    } else {
                        let backoff = failedPids[pid].map { min($0.backoff * 2, registrationRetryMaxDelay) } ?? registrationRetryMinDelay
                        failedPids[pid] = (nextAttempt: .now + backoff, backoff: backoff, launchDate: launchDate)
                        // Something has to look again. An app we could not subscribe to sends no AX events,
                        // and the launch burst that brought us here is over, so a window of an app that was
                        // merely still launching sat unmanaged until an unrelated event -- usually a click --
                        // refreshed (#40). Stops below the ceiling, after 1+2+4+8+16 seconds.
                        if backoff < registrationRetryMaxDelay {
                            scheduleFollowUpRefresh(after: backoff, "registrationRetry")
                        }
                    }
                    wipPids.remove(pid)
                    for (id, _) in registrationWaiters[pid] ?? [:] { resumeRegistrationWaiter(pid, id) }
                }
                // Must come after the publish above: this parks the thread for its lifetime.
                if isGood {
                    // Holds the loop open once the app dies and its AX source goes away. `perform(on:)`
                    // silently drops jobs for a thread that has left its loop, and the `await` behind a
                    // dropped job never returns. `destroy()` is what ends this thread.
                    RunLoop.current.add(NSMachPort(), forMode: .default)
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

    /// A collected window's pending jobs, each with a lock of its own, which stayed until the app quit. Every
    /// native tab is a window id, so a long-lived Finder or Terminal grew these for weeks. Cancelling is harmless:
    /// the window is dead, or if it is detected again, registration writes its frame again.
    @MainActor
    func forget(_ windowId: UInt32) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        nativeStateJobs.removeValue(forKey: windowId)?.cancel()
        if isDebugLoggingEnabled { parkTrace.withLock { $0.forget(windowId) } }
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

    @MainActor
    func getFocusedWindow() async throws -> Window? {
        if MacApp.timedOutThisPass.contains(pid) { throw NativeFocusUnknown() }
        let windowId: UInt32?
        do {
            windowId = try await thread?.runInLoop { [axObserver, axApp, windows] job in
                // Not `get(Ax.focusedWindowAttr)`, which collapses every failure to nil. An app that
                // misses `axMessagingTimeout` has not said it has no focused window, and reporting it as
                // if it had spends `updateFocusCache`'s record of what macOS last said -- so the app's
                // next, stale answer reads as a focus change and bounces the user back across a workspace
                // switch. On macOS 26 and 27 a busy app's read fails `.cannotComplete` after
                // the full timeout. (A window AeroSpork does not know yet costs a second AX call,
                // `_AXUIElementGetWindow`, which can still time out and read as nil; not covered.)
                var raw: AnyObject?
                let error = AXUIElementCopyAttributeValue(axApp.threadGuarded, Ax.focusedWindowAttr.key as CFString, &raw)
                // Without Accessibility access every read fails `.apiDisabled`, which is no answer either.
                if error == .cannotComplete || error == .apiDisabled { throw NativeFocusUnknown() }
                let element = error == .success ? raw.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil } : nil
                let axWindow = identifyWindows(element.map { [$0] } ?? [], known: knownElements(windows.threadGuarded)).first
                    .flatMap { windows.threadGuarded.getOrRegisterAxWindow(windowId: $0.windowId, $0.ax, axObserver.threadGuarded) }
                return axWindow?.windowId
            }
        } catch let unknown as NativeFocusUnknown {
            MacApp.timedOutThisPass.insert(pid)
            throw unknown
        }
        guard let windowId else { return nil }
        return try await MacWindow.getOrRegister(windowId: windowId, macApp: self)
    }

    @MainActor func nativeFocus(_ windowId: UInt32) {
        // Declare the request BEFORE issuing it: the AX calls below run on the app's thread, and
        // `runSession` asks for another refresh as soon as this returns. Without this, that refresh
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
            // An app clamps a size below its minimum and grows the window from its top-left: past its
            // tile, over its neighbours, off the monitor. Read back what it settled on so layout can
            // plan around it -- and so the frame it asks for next time is one the app can satisfy,
            // instead of re-writing an impossible one on every refresh.
            if let size, let got = window.get(Ax.sizeAttr), got.width > size.width + 1 || got.height > size.height + 1 {
                Task { @MainActor in
                    if MacWindow.allWindowsMap[windowId]?.noteRefusedSize(asked: size, got: got) == true {
                        scheduleFollowUpRefresh(after: 0, "minimumSizeLearned") // re-split the tiles around it
                    }
                }
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
            // Same no-op guard as setAxFrame and hideAxWindow.
            if isFrameSatisfied(window, point, nil) { return }
            disableAnimations(app: axApp.threadGuarded) {
                _ = window.set(Ax.topLeftCornerAttr, point)
            }
        }
    }

    /// Park a window at `spot(size)`. The size is read here, on the app's thread, so hiding a workspace
    /// awaits nothing: the spot depends on it because a parked window must not reach another monitor.
    func hideAxWindow(_ windowId: UInt32, at spot: @escaping @Sendable (CGSize) -> CGPoint) {
        setFrameJobs.removeValue(forKey: windowId)?.cancel()
        setFrameJobs[windowId] = thread?.runInLoopAsync { [windows, axApp, bundleId] job in
            guard let window = windows.threadGuarded[windowId] else { return }
            let check = parkAxWindow(window.ax, app: axApp.threadGuarded, at: spot, settled: &window.parkedSpot)
            if isDebugLoggingEnabled, let check { traceParkCheck(windowId, bundleId, check) }
        } ?? .cancelled
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
        try await withWindow(windowId) { window, job in axRect(window) }
    }

    /// The known tabs beside this window, if it's a tab beside any, rather than a new window. They're the ones off
    /// the list, which also tells it apart from a group first seen at startup, when no tab of it is known yet.
    @MainActor
    func knownTabsBeside(_ windowId: UInt32) async throws -> [UInt32] {
        try await withWindow(windowId) { [axApp, windows, bundleId] window, job in
            guard (window.tabTitles?.count ?? 0) > 1 else { return [] }
            let listed = Set(listedWindows(axApp.threadGuarded, bundleId, known: windows.threadGuarded).map(\.windowId))
            return windows.threadGuarded.keys.filter { !listed.contains($0) }
        } ?? []
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
        nativeStateJobs.removeValue(forKey: windowId)?.cancel()
        nativeStateJobs[windowId] = withWindowAsync(windowId) { window, job in
            window.set(Ax.isFullscreenAttr, value)
        }
    }

    func setNativeMinimized(_ windowId: UInt32, _ value: Bool) {
        nativeStateJobs.removeValue(forKey: windowId)?.cancel()
        nativeStateJobs[windowId] = withWindowAsync(windowId) { window, job in
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
    /// Inside the hop, both flags are one AX round trip too (`readMacosNativeState`).
    @MainActor
    func macosNativeState(_ windowId: UInt32) async throws -> (fullscreen: Bool, minimized: Bool)? {
        try await withWindow(windowId) { window, job in
            readMacosNativeState(window)
        }
    }

    /// The running apps with `.regular` activation policy, kept from NSWorkspace's notifications.
    ///
    /// Not asked for on each refresh: `activationPolicy` is a synchronous XPC to LaunchServices, and
    /// walking every running process with it on the main actor was 87% of a refresh and most of the
    /// app's idle CPU.
    ///
    /// `startRegularAppSweep` catches the one thing the notifications don't say: an app that turns regular
    /// without launching or activating, like an agent opening a window in the background.
    @MainActor private static var regularApps: [pid_t: NSRunningApplication] = Dictionary(
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map { ($0.processIdentifier, $0) },
        uniquingKeysWith: { _, newest in newest },
    )

    /// Adds any apps not known to be regular, and says whether there were any. Add-only: a sweep is older
    /// than whatever the notifications have said since, and one that turned back is merely asked for
    /// windows it doesn't have.
    @MainActor static func noteRegularApps(_ apps: [NSRunningApplication]) -> Bool {
        // LaunchServices keeps listing an app that exited with a job still loaded. See `isGone`.
        let new = apps.filter { regularApps[$0.processIdentifier] == nil && !processIsGone($0.processIdentifier) }
        for app in new { regularApps[app.processIdentifier] = app }
        return !new.isEmpty
    }

    /// Every 30 seconds, off the main thread: each app it asks about is a round trip to LaunchServices.
    static func startRegularAppSweep() {
        _ = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(30))
                let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                await MainActor.run {
                    // A gone app sends no events, so nothing else would refresh to collect its windows.
                    let anyGone = allAppsMap.values.contains { $0.nsApp.isGone }
                    // Nothing else says Accessibility was granted again, and refreshes skipped until then.
                    let trustBack = noteTrustRegained(isTrusted: AXIsProcessTrusted())
                    let deadWindows = noteWindowsGoneFromWindowServer()
                    if noteRegularApps(regular) || anyGone || deadWindows || trustBack { runRefreshSession(.globalObserver("regularAppSweep"), screenIsDefinitelyUnlocked: false) }
                }
            }
        }
    }

    /// Adds the registered windows WindowServer no longer has to `pendingDead`, and says whether there were any.
    /// One WindowServer read per sweep, never per refresh. In healthy operation nothing is found and no refresh runs.
    @MainActor static func noteWindowsGoneFromWindowServer() -> Bool {
        let registered = Set(MacWindow.allWindowsMap.keys) // first: then every id in it predates the read below
        let dead = windowsGoneFromWindowServer(registered: registered, alive: windowServerWindowIds(), backgroundTabs: backgroundTabs)
        pendingDead.formUnion(dead)
        return !dead.isEmpty
    }

    /// One app launched, activated, unhid or terminated.
    @MainActor static func noteAppChanged(_ nsApp: NSRunningApplication) {
        regularApps[nsApp.processIdentifier] = !nsApp.isTerminated && nsApp.activationPolicy == .regular ? nsApp : nil
    }

    @MainActor
    static func refreshAllAndGetAliveWindowIds(frontmostAppBundleId: String?) async throws -> [MacApp: [UInt32]] {
        // One liveness check per app per pass. `refreshAndGetAliveWindowIds` checks again after its
        // `await`, for an app that dies in the middle of the pass.
        let gone = Set((Array(regularApps.values) + allAppsMap.values.map(\.nsApp)).filter(\.isGone).map(\.processIdentifier))
        regularApps = regularApps.filter { !gone.contains($0.key) } // or the loop below registers it again
        forgetFailedRegistrationsOfGoneProcesses()
        for (pid, app) in MacApp.allAppsMap where gone.contains(pid) { // gc dead apps
            try checkCancellation()
            app.destroy()
        }
        return try await withThrowingTaskGroup(of: (pid_t, [UInt32]).self, returning: [MacApp: [UInt32]].self) { group in
            func refreshTheApp(_ nsApp: NSRunningApplication) {
                group.addTask { @Sendable @MainActor in
                    guard let app = try await getOrRegister(nsApp) else { return (nsApp.processIdentifier, []) }
                    return (nsApp.processIdentifier, try await app.refreshAndGetAliveWindowIds(frontmostAppBundleId: frontmostAppBundleId))
                }
            }
            // Regular apps, plus whatever else already got registered: "About this Mac", TouchID and a lot
            // of other utility windows. We don't monitor those actively, but a window of one that got
            // focused ends up in allAppsMap.
            for nsApp in regularApps.values where allAppsMap[nsApp.processIdentifier] == nil {
                try checkCancellation()
                refreshTheApp(nsApp)
            }
            for (_, app) in MacApp.allAppsMap {
                try checkCancellation()
                refreshTheApp(app.nsApp)
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
        if nsApp.isGone {
            destroy()
            return []
        }
        guard let thread else { return [] }
        let previousTabs = backgroundTabsSeen
        let pendingDead = MacApp.pendingDead
        let outcome = try await thread.runInLoop { [axObserver, windows, axApp, bundleId] (job) -> (ids: [UInt32], tabs: [UInt32: UInt32], timedOut: Bool) in
            var result: [UInt32: AxWindow] = windows.threadGuarded
            let listStart = DispatchTime.now()
            let listed = listedWindows(axApp.threadGuarded, bundleId, known: result)
            // Once one read has waited out the timeout the rest would too; keeping the window is what a
            // timed-out `isDestroyed()` answers anyway. See `timedOutThisPass`.
            var timedOut = isAxTimeout(since: listStart)
            // Second line of defence against lock screen. See the first line of defence: closedWindowsCache
            // Second and third lines of defence are technically needed only to avoid potential flickering
            if frontmostAppBundleId != lockScreenAppBundleId {
                let listedIds = Set(listed.map(\.windowId))
                result = try result.filter {
                    try job.checkCancellation()
                    // Before the timeout shortcut, which keeps everything: WindowServer answers where the app
                    // cannot. An app that answers and lists the window wins.
                    if pendingDead.contains($0.key) && !listedIds.contains($0.key) { return false }
                    if timedOut { return true }
                    // Listed means alive, so one read answers for most windows. The list leaves out
                    // windows on other macOS Spaces, which is why the rest get asked individually.
                    if listedIds.contains($0.key) { return true }
                    let start = DispatchTime.now()
                    // `isDestroyed()`, not `containingWindowId() != nil`. Everything absent from the
                    // returned set is garbage collected by `refresh()`, which unbinds the window and
                    // hands focus elsewhere -- so a window merely belonging to an app that missed the
                    // 1s `axMessagingTimeout` used to be treated as closed. See issue #39.
                    let destroyed = $0.value.ax.isDestroyed()
                    timedOut = isAxTimeout(since: start)
                    return !destroyed
                }
            }

            var tabs = previousTabs
            if !timedOut {
                for (id, window) in listed {
                    try job.checkCancellation()
                    result.getOrRegisterAxWindow(windowId: id, window, axObserver.threadGuarded)
                }
                tabs = findBackgroundTabs(known: result, listed: listed, previously: previousTabs)
            }

            windows.threadGuarded = result
            return (Array(result.keys), tabs, timedOut)
        }
        if outcome.timedOut { MacApp.timedOutThisPass.insert(pid) }
        if MacApp.noteAnswer(pid: pid, answered: !outcome.timedOut, now: .now) {
            let windowCount = MacWindow.allWindowsMap.values.count(where: { $0.macApp === self })
            AppLog.session.notice("app \(self.bundleId ?? "?", privacy: .public) (\(self.pid, privacy: .public)) has not answered Accessibility for a minute; keeping its \(windowCount, privacy: .public) windows; process gone: \(processIsGone(self.pid), privacy: .public)")
        }
        backgroundTabsSeen = outcome.tabs
        return outcome.ids
    }

    @MainActor
    private func destroy() {
        if !nsApp.isTerminated {
            // The Discord case (see `isGone`): the one record that says LaunchServices lied. Once per app.
            let windowCount = MacWindow.allWindowsMap.values.count(where: { $0.macApp === self })
            AppLog.session.notice("app \(self.bundleId ?? "?", privacy: .public) (\(self.pid, privacy: .public)) is gone but LaunchServices still lists it; removing \(windowCount, privacy: .public) windows")
        }
        MacApp.allAppsMap.removeValue(forKey: pid)
        MacApp.unansweredSince.removeValue(forKey: pid)
        for (_, job) in setFrameJobs {
            job.cancel()
        }
        setFrameJobs = [:]
        for (_, job) in nativeStateJobs {
            job.cancel()
        }
        nativeStateJobs = [:]
        thread?.runInLoopAsync { [windows, appAxSubscription, axObserver, axApp] job in
            // Destroy AX objects in reverse order of their creation
            appAxSubscription.destroy()
            windows.destroy()
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver.threadGuarded), .defaultMode)
            axObserver.destroy()
            axApp.destroy()
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        thread = nil // Disallow all future job submissions
    }

    @MainActor
    private func withWindow<T>(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) throws -> T?) async throws -> T? {
        // Already waited out once this pass: every read would answer "timed out" again, a second each.
        if MacApp.timedOutThisPass.contains(pid) { return nil }
        let outcome = try await thread?.runInLoop { [windows] (job) -> (value: T?, timedOut: Bool) in
            guard let window = windows.threadGuarded[windowId] else { return (nil, false) }
            let start = DispatchTime.now()
            let value = try body(window.ax, job)
            return (value, isAxTimeout(since: start))
        }
        if outcome?.timedOut == true { MacApp.timedOutThisPass.insert(pid) }
        return outcome?.value
    }

    private func withWindowAsync(_ windowId: UInt32, _ body: @Sendable @escaping (AXUIElement, RunLoopJob) -> ()) -> RunLoopJob {
        thread?.runInLoopAsync { [windows] job in
            guard let window = windows.threadGuarded[windowId] else { return }
            body(window.ax, job)
        } ?? .cancelled
    }
}

/// Did an AX call that started at `start` wait out `axMessagingTimeout`? Timed on the app's own
/// thread around the call, so time spent queued behind other jobs never counts.
private func isAxTimeout(since start: DispatchTime) -> Bool {
    isAxTimeout(elapsedSeconds: Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000)
}

/// A call to a stopped app returns after about 1000ms on macOS 27; a healthy round trip takes
/// single-digit milliseconds.
func isAxTimeout(elapsedSeconds: Double) -> Bool {
    elapsedSeconds >= Double(axMessagingTimeout) * 0.9
}

/// An app's windows on the current macOS Space, and of a tab group only the selected tab.
///
/// Finder's `AXWindows` is empty on macOS 27 whatever it has open, so it was only ever seen through its focused
/// window, and nothing showed which of its windows had left the screen.
/// ponytail: Finder only, the one app on a whole Mac that answers this way. The second read would otherwise fall
/// on every app without a window, on every refresh.
///
/// A window in `known` costs no window id read (`identifyWindows`), so with no new windows a refresh reads one list
/// per app and nothing per window.
private func listedWindows(_ axApp: AXUIElement, _ bundleId: String?, known: [UInt32: AxWindow]) -> [WindowIdAndAxUiElement] {
    let index = knownElements(known)
    let listed = identifyWindows(axApp.get(Ax.windowElementsAttr) ?? [], known: index)
    if !listed.isEmpty || bundleId != "com.apple.finder" { return listed }
    // Its other children are a menu bar and the desktop.
    let children = axApp.get(Ax.childrenAttr)?.compactMap(\.cast) ?? []
    return identifyWindows(children, known: index) { $0.get(Ax.roleAttr) == kAXWindowRole }
}

/// The reverse of an app's `windows`: which window each tracked element is.
private func knownElements(_ known: [UInt32: AxWindow]) -> [AXUIElement: UInt32] {
    Dictionary(known.map { ($0.value.ax, $0.key) }, uniquingKeysWith: { first, _ in first })
}

private func axRect(_ window: AXUIElement) -> Rect? {
    let frame = window.getFrame()
    guard let topLeftCorner = frame.topLeft, let size = frame.size else { return nil }
    return Rect(topLeftX: topLeftCorner.x, topLeftY: topLeftCorner.y, width: size.width, height: size.height)
}

/// Which of an app's windows are background tabs, each with the selected tab of its group.
///
/// macOS makes a tab a window of its own. Only the selected one of a group is on the app's list and has a tab
/// bar; the others stay alive, off the list, with the frame they last had. So a window off the list is a
/// background tab if the app is showing a tab bar with more than one tab in it. The reads only happen for an
/// app with such a window, which is not most apps on most refreshes.
///
/// A window on another macOS Space is off the list too. It's out of sight either way, so taking it for a tab
/// costs nothing but the tile it was holding open.
private func findBackgroundTabs(known: [UInt32: AxWindow], listed: [WindowIdAndAxUiElement], previously: [UInt32: UInt32]) -> [UInt32: UInt32] {
    let listedIds = Set(listed.map(\.windowId))
    let unlisted = known.filter { !listedIds.contains($0.key) }
    if unlisted.isEmpty { return [:] }
    let bars = listed.compactMap { window in window.ax.tabTitles.flatMap { $0.count > 1 ? (window: window, titles: $0) : nil } }
    let several = bars.count > 1
    let groups = bars.map { TabGroup(selected: $0.window.windowId, titles: $0.titles, frame: several ? axRect($0.window.ax) : nil) }
    var result: [UInt32: UInt32] = [:]
    for (id, window) in unlisted {
        // Not a Quick Look panel or the like, which can be open and off the list as well.
        if !groups.isEmpty, window.ax.get(Ax.subroleAttr) == kAXStandardWindowSubrole {
            let group = several
                ? tabGroup(titled: window.ax.get(Ax.titleAttr), at: axRect(window.ax), among: groups)
                : groups.first
            result[id] = group?.selected
        } else if let selected = previously[id], unlisted[selected] != nil {
            result[id] = selected // The whole group is out of sight, so there's no tab bar to go by.
        }
    }
    return result
}

struct TabGroup {
    let selected: UInt32
    let titles: [String]
    let frame: Rect?
}

/// Which group a background tab is in, when an app has several. By its title on a tab bar, which most apps keep
/// the same as the window's, though not Terminal. Among several or none of those, by frame: macOS hands a newly
/// selected tab the group's frame, so a tab selected until just now has the same one. Frame alone misleads, since
/// groups parked on a hidden workspace can all share one spot. A wrong answer moves a tile, it doesn't leave an
/// empty one, so the last resort can afford to be a guess.
func tabGroup(titled title: String?, at frame: Rect?, among groups: [TabGroup]) -> TabGroup? {
    let named = groups.filter { group in title.map(group.titles.contains) == true }
    let candidates = named.isEmpty ? groups : named
    return candidates.first { group in
        guard let a = group.frame, let b = frame else { return false }
        return a.topLeftCorner == b.topLeftCorner && a.size == b.size
    } ?? candidates.first
}

private class AxWindow {
    let windowId: UInt32
    let ax: AXUIElement
    private let axSubscription: AxSubscription // keep the subscription in memory
    /// Where macOS let this window settle the last time it was parked. See `ParkedSpot`.
    var parkedSpot: ParkedSpot?

    private init(windowId: UInt32, _ ax: AXUIElement, _ axSubscription: AxSubscription) {
        self.windowId = windowId
        self.ax = ax
        self.axSubscription = axSubscription
    }

    static func new(windowId: UInt32, _ ax: AXUIElement, _ observer: AXObserver) -> AxWindow? {
        _ = AXUIElementSetMessagingTimeout(ax, axMessagingTimeout)
        let keys = [kAXUIElementDestroyedNotification, kAXWindowDeminiaturizedNotification, kAXWindowMiniaturizedNotification, kAXMovedNotification, kAXResizedNotification]
        return AxSubscription.subscribe(observer, ax, keys, windowId: windowId).map { AxWindow(windowId: windowId, ax, $0) }
    }
}

extension [UInt32: AxWindow] {
    @discardableResult
    fileprivate mutating func getOrRegisterAxWindow(windowId id: UInt32, _ axWindow: AXUIElement, _ observer: AXObserver) -> AxWindow? {
        if let existing = self[id] { return existing }
        // Delay new window detection if mouse is down
        // It helps with apps that allow dragging their tabs out to create new windows
        // https://github.com/wbsmolen/aerospork/issues/1001
        if isLeftMouseButtonDown { return nil }

        if let window = AxWindow.new(windowId: id, axWindow, observer) {
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
    // Each read is a cross-thread AX round trip. Both values come in one batched read, which costs what one
    // single read does; a one-sided guard reads only the value it was asked about. See AxWriteTest.
    switch (topLeft, size) {
        case (nil, nil): return true
        case (let topLeft?, nil): return isAt(window.get(Ax.topLeftCornerAttr), topLeft)
        case (nil, let size?): return isSized(window.get(Ax.sizeAttr), size)
        case (let topLeft?, let size?):
            let actual = window.getFrame()
            return isSized(actual.size, size) && isAt(actual.topLeft, topLeft)
    }
}

/// AX rounds, so within a point is at the target. Unreadable is never satisfied: "unknown" means "write it".
private func isAt(_ actual: CGPoint?, _ target: CGPoint) -> Bool {
    guard let actual else { return false }
    return abs(actual.x - target.x) < 1 && abs(actual.y - target.y) < 1
}

private func isSized(_ actual: CGSize?, _ target: CGSize) -> Bool {
    guard let actual else { return false }
    return abs(actual.width - target.width) < 1 && abs(actual.height - target.height) < 1
}

/// Where macOS put a window that was parked at `spot`.
///
/// macOS keeps a window's title bar on screen, so a spot near the bottom edge of a display is clamped
/// upwards, by the height of that app's title bar (41 points for Chrome, 32 for Discord, on macOS 27).
/// Compared with the spot alone, a clamped window never looked parked, and every refresh wrote its
/// position again: one AX write per parked window per refresh, forever.
struct ParkedSpot: Equatable {
    var spot: CGPoint
    var settled: CGPoint

    /// A clamp moves a window by about a title bar. A write that did not take leaves it where it was,
    /// much further away, and must not be remembered as parked.
    static let maxClamp: CGFloat = 150

    init?(spot: CGPoint, settled: CGPoint?) {
        guard let settled, abs(settled.x - spot.x) <= Self.maxClamp, abs(settled.y - spot.y) <= Self.maxClamp else { return nil }
        self.spot = spot
        self.settled = settled
    }
}

/// The `hideAxWindow` body, generic so the tests can drive it. The spot depends on the size, and both come
/// from one batched read. Returns where the window should now be (the spot, or where macOS clamped it) and
/// where it was before any write, nil if unreadable.
@discardableResult
func parkAxWindow(_ window: some AxUiElementMock, app: some AxUiElementMock, at spot: (CGSize) -> CGPoint) -> (spot: CGPoint, actual: CGPoint?)? {
    var settled: ParkedSpot?
    return parkAxWindow(window, app: app, at: spot, settled: &settled)
}

@discardableResult
func parkAxWindow(
    _ window: some AxUiElementMock,
    app: some AxUiElementMock,
    at spot: (CGSize) -> CGPoint,
    settled: inout ParkedSpot?,
) -> (spot: CGPoint, actual: CGPoint?)? {
    let actual = window.getFrame()
    guard let size = actual.size else { return nil }
    let point = spot(size)
    // This runs for every window of every invisible workspace on every refresh; without the
    // guard that was an unconditional AX position write per hidden window, forever.
    if isAt(actual.topLeft, point) { return (point, actual.topLeft) }
    if let settled, settled.spot == point, isAt(actual.topLeft, settled.settled) { return (settled.settled, actual.topLeft) }
    disableAnimations(app: app) {
        _ = window.set(Ax.topLeftCornerAttr, point)
    }
    // One read per park, not per refresh.
    settled = ParkedSpot(spot: point, settled: window.get(Ax.topLeftCornerAttr))
    return (point, actual.topLeft)
}

/// Trace only: does an app move a parked window without the `kAXMoved`/`kAXResized` notification that
/// every window subscribes to? Re-reading parked windows on every layout could only be skipped if it never
/// does. Touched only while `AEROSPORK_DEBUG_LOG` is set: one insert per notification, one lookup per check.
private struct ParkTrace {
    /// Where the last check left each parked window.
    var parkedAt: [UInt32: CGPoint] = [:]
    /// Windows with a move or resize notification since their last check.
    var notified: Set<UInt32> = []
    mutating func forget(_ windowId: UInt32) {
        parkedAt.removeValue(forKey: windowId)
        notified.remove(windowId)
    }
}

/// Every app thread writes here, so one lock. Uncontended, and only while tracing.
private let parkTrace = OSAllocatedUnfairLock(initialState: ParkTrace())

/// Called for each move or resize notification, with its refcon, which carries the window id (`axRefcon`).
func noteFrameNotification(_ refcon: UnsafeMutableRawPointer?) {
    guard isDebugLoggingEnabled, let windowId = axRefconWindowId(refcon) else { return }
    parkTrace.withLock { _ = $0.notified.insert(windowId) }
}

private func traceParkCheck(_ windowId: UInt32, _ bundleId: String?, _ check: (spot: CGPoint, actual: CGPoint?)) {
    let (parkedAt, notified) = parkTrace.withLock { trace in
        defer { trace.parkedAt[windowId] = check.spot }
        return (trace.parkedAt[windowId], trace.notified.remove(windowId) != nil)
    }
    if parkedWindowMovedWithoutNotification(parkedAt: parkedAt, spot: check.spot, actual: check.actual, notified: notified) {
        debugLog("Parked window moved without a notification: \(bundleId ?? "no bundle id") window \(windowId) "
            + "was at \(check.actual.prettyDescription), parked at \(check.spot)")
    }
}

/// A re-check found the window away from the spot the previous check left it at, and no move or resize
/// notification arrived in between. Our own park write notifies too, so the check after a write never counts.
func parkedWindowMovedWithoutNotification(parkedAt: CGPoint?, spot: CGPoint, actual: CGPoint?, notified: Bool) -> Bool {
    guard !notified, let parkedAt, let actual else { return false }
    return isAt(parkedAt, spot) && !isAt(actual, spot)
}

/// The AX writes that hand focus to a window. Extracted from `MacApp.nativeFocus` so the sequence is
/// assertable -- the raise action and `nsApp.activate` around it need a real app thread.
///
/// `kAXFocusedAttribute` first, and it is the load-bearing one: it is what
/// `kAXFocusedWindowAttribute` reports back, which is what `getNativeFocusedWindow` reads. `isMain`
/// only changes which window the app considers primary for ordering.
/// The AX read behind `macosNativeState`, over the mockable element seam.
///
/// Extracted so the *read pattern* is assertable: both flags in one batched read. It used to skip the
/// minimized read for a fullscreen window, to save an IPC; a batch has no second IPC to save, so only
/// the answer is kept: a fullscreen window is never minimized.
func readMacosNativeState(_ window: some AxUiElementMock) -> (fullscreen: Bool, minimized: Bool) {
    let flags = window.getNativeFlags()
    let fullscreen = flags.fullscreen == true
    return (fullscreen, !fullscreen && flags.minimized == true)
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

extension NSRunningApplication {
    /// `isTerminated`, or the process is gone while LaunchServices still holds its record.
    ///
    /// An app that exits with a launchd job still loaded stays in `lsappinfo` as
    /// "exited-with-subordinates": Discord does this when its ShipIt updater relaunches it. No
    /// termination notification arrives, `isTerminated` stays false for good, and every AX read of the
    /// dead pid answers `.cannotComplete`, which is what a busy app answers. Since #39 a busy app keeps
    /// its windows, so the dead app's windows kept empty tiles until logout.
    var isGone: Bool { isTerminated || processIsGone(processIdentifier) }
}

/// `kill(pid, 0)` sends nothing; ESRCH means no such process. EPERM (not ours to signal) is alive.
func processIsGone(_ pid: pid_t) -> Bool { kill(pid, 0) != 0 && errno == ESRCH }
