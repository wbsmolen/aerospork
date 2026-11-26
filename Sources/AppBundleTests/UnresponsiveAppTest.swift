@testable import AppBundle
import Common
import XCTest

/// An app that stops answering Accessibility must cost one timeout per refresh pass, not one per call,
/// and must not have its windows moved on the strength of a question it never answered.
///
/// Since the #39 fix, a busy app's windows stay in the tree, and every pass asks about each of them, a
/// second at a time, on that app's single AX thread: with the app stopped, switching away from a few of
/// its windows could take ten seconds. Those answers are all "timed out", so skipping the rest of the
/// pass after the first changes how long a pass takes, not what it decides.
@MainActor
final class UnresponsiveAppTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        resetFocusCacheForTests()
    }

    func testOnlyAWaitAsLongAsTheTimeoutCountsAsATimeout() {
        XCTAssertFalse(isAxTimeout(elapsedSeconds: 0.004), "a healthy round trip")
        XCTAssertFalse(isAxTimeout(elapsedSeconds: 0.5), "slow, but it answered")
        XCTAssertTrue(isAxTimeout(elapsedSeconds: 0.95))
        XCTAssertTrue(isAxTimeout(elapsedSeconds: 1.002), "a call to a stopped app on macOS 27")
    }

    // MARK: - A dead app is not a busy app

    /// Both answer AX with `.cannotComplete`, and a busy app keeps its windows. An app that exits with a
    /// launchd job still loaded never reports `isTerminated`, so the pid itself has to say it is gone, or
    /// its windows keep empty tiles forever (Discord after a self-update).
    func testAnExitedProcessIsGoneAndALiveOneIsNot() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit() // reaped, so the pid no longer exists
        XCTAssertTrue(processIsGone(child.processIdentifier))
        XCTAssertFalse(processIsGone(ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(processIsGone(1), "launchd is not ours to signal, which is EPERM, not gone")
    }

    /// `NSRunningApplication(processIdentifier:)` is nil for a bare child process, so no real gone app can
    /// be handed to `getOrRegister` here. Pinned in the source instead.
    func testADeadPidIsNotRegisteredOrReturned() throws {
        let body = try sourceBody("static func getOrRegister(_ nsApp: NSRunningApplication)", in: "Sources/AppBundle/tree/MacApp.swift")
        let guardLine = try XCTUnwrap(body.range(of: "if nsApp.isGone { return nil }"), "getOrRegister registers a dead pid again")
        let early = try XCTUnwrap(body.range(of: "if let existing = allAppsMap[pid] { return existing }"))
        XCTAssertLessThan(guardLine.lowerBound, early.lowerBound, "a gone app still in allAppsMap is returned before the guard")
    }

    /// The record the Discord incident lacked, and only for the case LaunchServices got wrong: a normal
    /// quit (`isTerminated`) must not write it.
    func testAGoneAppThatLaunchServicesStillListsIsLogged() throws {
        let body = try sourceBody("private func destroy()", in: "Sources/AppBundle/tree/MacApp.swift")
        let guardLine = try XCTUnwrap(body.range(of: "if !nsApp.isTerminated {"))
        let notice = try XCTUnwrap(body.range(of: "AppLog.session.notice(\"app "))
        XCTAssertLessThan(guardLine.lowerBound, notice.lowerBound)
        XCTAssertNil(body[..<guardLine.lowerBound].range(of: "AppLog"), "a log line in destroy() that every quit writes")
    }

    // MARK: - A stopped app shows in the log, once per episode

    func testAnAppUnansweredForAMinuteIsLoggedOnceAndAnAnswerRearmsIt() {
        let pid: pid_t = -113 // no real process
        let start = Date()
        XCTAssertFalse(MacApp.noteAnswer(pid: pid, answered: false, now: start), "the episode starts")
        XCTAssertFalse(MacApp.noteAnswer(pid: pid, answered: false, now: start + 59))
        XCTAssertTrue(MacApp.noteAnswer(pid: pid, answered: false, now: start + 60))
        XCTAssertFalse(MacApp.noteAnswer(pid: pid, answered: false, now: start + 61), "a record on every refresh")
        XCTAssertFalse(MacApp.noteAnswer(pid: pid, answered: true, now: start + 62))
        XCTAssertNil(MacApp.unansweredSince[pid], "an answer ends the episode")
        XCTAssertFalse(MacApp.noteAnswer(pid: pid, answered: false, now: start + 63))
        XCTAssertTrue(MacApp.noteAnswer(pid: pid, answered: false, now: start + 123), "the next episode gets its own record")
        _ = MacApp.noteAnswer(pid: pid, answered: true, now: start + 124)
    }

    /// Or the map keeps every pid that ever stopped answering. `destroy()` needs a real app.
    func testADestroyedAppsEpisodeIsForgotten() throws {
        let body = try sourceBody("private func destroy()", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(body.contains("MacApp.unansweredSince.removeValue(forKey: pid)"))
        let perApp = try sourceBody("private func refreshAndGetAliveWindowIds", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(perApp.contains("MacApp.noteAnswer(pid: pid, answered: !outcome.timedOut"), "the window-list read no longer notes answers")
    }

    // MARK: - State of the dead is let go

    /// A pass prunes failed registrations of processes that exited. The pass itself registers every running app,
    /// so it is not run here; the call into the prune is pinned in the source.
    func testAFailedRegistrationOfADeadPidIsForgottenByThePass() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        let dead = child.processIdentifier
        let alive = ProcessInfo.processInfo.processIdentifier
        let saved = MacApp.failedPids
        defer { MacApp.failedPids = saved }
        MacApp.failedPids[dead] = (nextAttempt: .now + 30, backoff: 30, launchDate: nil)
        MacApp.failedPids[alive] = (nextAttempt: .now + 30, backoff: 30, launchDate: nil)

        MacApp.forgetFailedRegistrationsOfGoneProcesses()

        XCTAssertNil(MacApp.failedPids[dead])
        XCTAssertNotNil(MacApp.failedPids[alive])
        let pass = try sourceBody("static func refreshAllAndGetAliveWindowIds(", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(pass.contains("forgetFailedRegistrationsOfGoneProcesses()"))
    }

    /// Each collected window's jobs stayed until its app quit.
    func testACollectedWindowsJobsAreForgotten() throws {
        let body = try sourceBody("func garbageCollect(skipClosedWindowsCache: Bool)", in: "Sources/AppBundle/tree/MacWindow.swift")
        XCTAssertTrue(body.contains("macApp.forget(windowId)"))
        let forget = try sourceBody("func forget(_ windowId: UInt32)", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(forget.contains("setFrameJobs.removeValue(forKey: windowId)?.cancel()"))
        XCTAssertTrue(forget.contains("nativeStateJobs.removeValue(forKey: windowId)?.cancel()"))
    }

    func testEachPassChecksLivenessOnceAndAgainAfterItsAwait() throws {
        let pass = try sourceBody("static func refreshAllAndGetAliveWindowIds(", in: "Sources/AppBundle/tree/MacApp.swift")
        let gone = try XCTUnwrap(pass.range(of: "let gone = Set("))
        XCTAssertEqual(pass.components(separatedBy: ".isGone").count - 1, 1, "liveness asked more than once per app per pass")
        XCTAssertNotNil(pass.range(of: "where gone.contains(pid)", range: gone.upperBound ..< pass.endIndex))
        let perApp = try sourceBody("private func refreshAndGetAliveWindowIds", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(perApp.contains("if nsApp.isGone {"), "an app that dies mid-pass is enumerated anyway")
    }

    // MARK: - Accessibility revoked at runtime

    /// Untrusted, a refresh could collect every window and save a memory file without them. A session
    /// collects and saves nothing, and gating it would make every CLI query fail.
    func testOnlyTheBackgroundRefreshWaitsForTrust() throws {
        let refresh = try sourceBody("func runRefreshSessionBlocking(", in: "Sources/AppBundle/layout/refresh.swift")
        let gate = try XCTUnwrap(refresh.range(of: "guard AXIsProcessTrusted() else { noteTrustLost(); return }"))
        for later in ["try await syncFocusFromMacOs()", "try await refresh()", "WorkspaceMemory.save()"] {
            let call = try XCTUnwrap(refresh.range(of: later), later)
            XCTAssertLessThan(gate.lowerBound, call.lowerBound, "\(later) runs before the trust gate")
        }
        let session = try sourceBody("func runSession<T>(", in: "Sources/AppBundle/layout/refresh.swift")
        XCTAssertFalse(session.contains("AXIsProcessTrusted"), "a session waits for trust, so the CLI stops answering")

        let sweep = try sourceBody("static func startRegularAppSweep()", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(sweep.contains("|| trustBack {"), "nothing refreshes once trust is granted again")
    }

    func testARevokedTrustLogsOncePerEpisode() {
        _ = noteTrustRegained(isTrusted: true) // whatever an earlier test left
        XCTAssertFalse(noteTrustRegained(isTrusted: true), "no episode, nothing to refresh for")
        XCTAssertTrue(noteTrustLost(), "the start of an episode is recorded")
        XCTAssertFalse(noteTrustLost(), "a record per skipped refresh")
        XCTAssertFalse(noteTrustRegained(isTrusted: false), "still revoked")
        XCTAssertTrue(noteTrustRegained(isTrusted: true))
        XCTAssertFalse(noteTrustRegained(isTrusted: true), "one refresh per episode")
        XCTAssertTrue(noteTrustLost(), "a second revocation is a new episode")
        _ = noteTrustRegained(isTrusted: true)
    }

    // MARK: - An unanswered native-state read moves nothing

    /// Read as "neither", a timeout pulled a minimized window out of the minimized container and tiled
    /// it -- then put it back once the app answered. A window->workspace change each time an app stalled,
    /// which `workspace-memory.json` recorded.
    func testAMinimizedWindowOfAnAppThatStopsAnsweringStaysMinimized() async throws {
        let workspace = Workspace.get(byName: "ws")
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.nativeState = (fullscreen: false, minimized: true)
        try await normalizeLayoutReason()
        XCTAssertTrue(window.parent === macosMinimizedWindowsContainer, "the test needs a minimized window")

        window.nativeState = nil
        try await normalizeLayoutReason()

        XCTAssertTrue(window.parent === macosMinimizedWindowsContainer, "an unanswered read un-minimized the window")
    }

    func testAFullscreenWindowOfAnAppThatStopsAnsweringStaysFullscreen() async throws {
        let workspace = Workspace.get(byName: "ws")
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.nativeState = (fullscreen: true, minimized: false)
        try await normalizeLayoutReason()
        XCTAssertTrue(window.parent === workspace.macOsNativeFullscreenWindowsContainer, "the test needs a fullscreen window")

        window.nativeState = nil
        try await normalizeLayoutReason()

        XCTAssertTrue(window.parent === workspace.macOsNativeFullscreenWindowsContainer, "an unanswered read tiled a fullscreen window")
    }

    func testATiledWindowOfAnAppThatStopsAnsweringStaysTiled() async throws {
        let workspace = Workspace.get(byName: "ws")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        window.nativeState = nil
        try await normalizeLayoutReason()

        XCTAssertTrue(window.parent === workspace.rootTilingContainer)
    }

    // MARK: - Wiring (needs a real MacApp and a real stopped app, so pinned in the source)

    func testMacWindowFallsBackToWhatTheTreeRecords() throws {
        let body = try sourceBody("override func macosNativeState()", in: "Sources/AppBundle/tree/MacWindow.swift")
        XCTAssertTrue(body.contains("?? nativeStateTheTreeRecords(for: self)"), "an unanswered read is reported as \"neither\" again")
    }

    func testEveryPassStartsWithACleanSlate() throws {
        for declaration in ["func runRefreshSessionBlocking(", "func runSession<T>("] {
            let body = try sourceBody(declaration, in: "Sources/AppBundle/layout/refresh.swift")
            let reset = try XCTUnwrap(body.range(of: "MacApp.timedOutThisPass = []"), "\(declaration) does not clear the record, so a recovered app stays skipped")
            let firstRead = try XCTUnwrap(body.range(of: "try await syncFocusFromMacOs()"))
            XCTAssertLessThan(reset.lowerBound, firstRead.lowerBound, "\(declaration) clears the record after its first AX read")
        }
    }

    func testAnAppThatTimedOutIsNotAskedAgainInTheSamePass() throws {
        let read = try sourceBody("private func withWindow<T>(", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(read.contains("if MacApp.timedOutThisPass.contains(pid) { return nil }"))
        XCTAssertTrue(read.contains("MacApp.timedOutThisPass.insert(pid)"))

        let focused = try sourceBody("func getFocusedWindow()", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(focused.contains("if MacApp.timedOutThisPass.contains(pid) { throw NativeFocusUnknown() }"))
        XCTAssertTrue(focused.contains("MacApp.timedOutThisPass.insert(pid)"))

        let alive = try sourceBody("private func refreshAndGetAliveWindowIds", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(alive.contains("if timedOut { return true }"), "the alive filter asks every window of a stopped app")
        XCTAssertTrue(alive.contains("if !timedOut {"), "the window list is read from a stopped app")
    }
}
