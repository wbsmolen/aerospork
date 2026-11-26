@testable import AppBundle
import Common
import XCTest

/// Not on wall clock beyond the delays themselves: every wait is on a condition, with a generous ceiling.
@MainActor
final class RefreshSchedulerTest: XCTestCase {
    private final class Recorder {
        var started: [RefreshRequest] = []
        var finished = 0
        var cancelled = 0
        var hold = false
    }

    private func scheduler(_ recorder: Recorder, abandonAfter: Duration = .seconds(60)) -> RefreshScheduler {
        RefreshScheduler(delay: .milliseconds(5), abandonAfter: abandonAfter) { request in
            recorder.started.append(request)
            while recorder.hold, !Task.isCancelled { await Task.yield() }
            if Task.isCancelled { recorder.cancelled += 1 } else { recorder.finished += 1 }
        }
    }

    private func until(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            if ContinuousClock.now > deadline { return XCTFail("timed out", file: file, line: line) }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func request(_ event: RefreshSessionEvent = .globalObserver("x"), unlocked: Bool = false, preLayout: Bool = false) -> RefreshRequest {
        RefreshRequest(event: event, screenIsDefinitelyUnlocked: unlocked, optimisticallyPreLayoutWorkspaces: preLayout)
    }

    func testABurstBecomesOneRefreshAndKeepsEveryFlag() async {
        let recorder = Recorder()
        let scheduler = scheduler(recorder)
        scheduler.request(request(unlocked: true))
        scheduler.request(request(preLayout: true))
        scheduler.request(request())
        await until { recorder.finished == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        assertEquals(recorder.started.count, 1)
        assertEquals(recorder.started[0].screenIsDefinitelyUnlocked, true)
        assertEquals(recorder.started[0].optimisticallyPreLayoutWorkspaces, true)
    }

    func testStartupSurvivesTheEventsThatMergeAfterIt() {
        var merged = request(.startup)
        merged.merge(request(.ax("moved")))
        assertEquals(merged.event.isStartup, true)
        var late = request(.ax("moved"))
        late.merge(request(.startup))
        assertEquals(late.event.isStartup, true)
    }

    /// The starvation this replaced: an event stream cancelled every refresh before it could finish.
    func testAnEventNeverCancelsARunningRefreshAndRunsOnceAfterIt() async {
        let recorder = Recorder()
        recorder.hold = true
        let scheduler = scheduler(recorder)
        scheduler.request(request())
        await until { recorder.started.count == 1 }
        for _ in 0 ..< 5 {
            scheduler.request(request())
            try? await Task.sleep(for: .milliseconds(10))
        }
        assertEquals(recorder.started.count, 1)
        assertEquals(recorder.cancelled, 0)
        recorder.hold = false
        await until { recorder.started.count == 2 && recorder.finished == 2 }
        assertEquals(recorder.cancelled, 0)
    }

    func testASessionCancelsARunningRefreshAndHoldsBackTheNext() async {
        let recorder = Recorder()
        recorder.hold = true
        let scheduler = scheduler(recorder)
        scheduler.request(request())
        await until { recorder.started.count == 1 }

        scheduler.sessionWillStart()
        await until { recorder.cancelled == 1 }
        scheduler.request(request())
        try? await Task.sleep(for: .milliseconds(30))
        assertEquals(recorder.started.count, 1) // nothing starts underneath a session

        recorder.hold = false
        scheduler.sessionDidEnd()
        await until { recorder.started.count == 2 && recorder.finished == 1 }
    }

    /// A request cancelled by a session starting must still happen once the session is over.
    func testASessionDoesNotLoseARefreshThatWasWaiting() async {
        let recorder = Recorder()
        let scheduler = scheduler(recorder)
        scheduler.request(request(unlocked: true))
        scheduler.sessionWillStart()
        try? await Task.sleep(for: .milliseconds(30))
        assertEquals(recorder.started.count, 0)
        scheduler.sessionDidEnd()
        await until { recorder.finished == 1 }
        assertEquals(recorder.started[0].screenIsDefinitelyUnlocked, true)
    }

    func testAWedgedRefreshDoesNotEndRefreshesForGood() async {
        let recorder = Recorder()
        recorder.hold = true
        let scheduler = scheduler(recorder, abandonAfter: .milliseconds(20))
        scheduler.request(request())
        await until { recorder.started.count == 1 }
        try? await Task.sleep(for: .milliseconds(30))
        recorder.hold = false
        scheduler.request(request())
        await until { recorder.started.count == 2 }
    }

    // MARK: - Sessions run one at a time

    func testSessionsRunInTheOrderTheyArrivedWithoutOverlapping() async {
        let gate = FifoGate()
        var log: [String] = []
        var tasks: [Task<Void, Never>] = []
        for name in ["a", "b", "c"] {
            tasks.append(Task { @MainActor in
                let ticket = await gate.enter()
                log.append("\(name)-in")
                await Task.yield()
                await Task.yield()
                log.append("\(name)-out")
                gate.leave(ticket)
            })
            await Task.yield()
        }
        for task in tasks { await task.value }
        assertEquals(log, ["a-in", "a-out", "b-in", "b-out", "c-in", "c-out"])
    }

    func testAWedgedSessionDoesNotHoldEveryoneElseUpForever() async {
        let gate = FifoGate(abandonAfter: .milliseconds(10))
        _ = await gate.enter() // never leaves
        let second = await gate.enter()
        gate.leave(second)
        let third = await gate.enter() // a late `leave` from the first must not free this one's hold
        gate.leave(third)
    }

    /// `FifoGate` deadlocks on a session that awaits another, so nothing a session runs may start one.
    func testNoCommandStartsANestedSession() throws {
        for url in try sourceFiles(in: "Sources/AppBundle/command") {
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(withoutComments(source).contains("runSession("), "\(url.lastPathComponent) would deadlock on sessionGate")
        }
    }

    // MARK: - Wiring (needs real apps, so pinned in the source)

    func testARefreshDoesNotAskLaunchServicesAboutEveryProcess() throws {
        let body = try sourceBody("static func refreshAllAndGetAliveWindowIds", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertFalse(body.contains("activationPolicy"))
        XCTAssertFalse(body.contains("runningApplications"))
    }

    /// Its comment promised one comparison, and it was a round trip to LaunchServices on every refresh.
    func testARefreshDoesNotAskLaunchServicesAboutItself() throws {
        let body = try sourceBody("@MainActor func syncAppVisibility()", in: "Sources/AppBundle/ui/TrayMenuModel.swift")
        XCTAssertFalse(body.contains("NSApp.activationPolicy()"))
    }

    /// Reading `localizedName` asks LaunchServices, and the menu bar lists every window's app per refresh.
    /// Any computed `name` brings that back, not only the one spelling that used to be there.
    func testAnAppsNameIsKeptNotAskedFor() throws {
        let source = try String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/tree/MacApp.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("let name: String?"), "MacApp.name must be stored once, not computed on every read")
    }

    /// An app that turns regular without launching or activating. The sweep is how it gets noticed.
    func testASweepOnlyReportsAppsItDidNotKnow() throws {
        let app = NSRunningApplication.current
        try XCTSkipIf(app.activationPolicy == .regular, "this runner is already regular")
        MacApp.noteAppChanged(app) // not regular, so not known
        defer { MacApp.noteAppChanged(app) }

        XCTAssertTrue(MacApp.noteRegularApps([app]))
        XCTAssertFalse(MacApp.noteRegularApps([app]))
    }

    func testOneWindowListAnswersForEveryWindowItNames() throws {
        let body = try sourceBody("private func refreshAndGetAliveWindowIds", in: "Sources/AppBundle/tree/MacApp.swift")
        let listed = try XCTUnwrap(body.range(of: ".contains($0.key)"), "a listed window is asked about one by one")
        let alive = try XCTUnwrap(body.range(of: "return true", range: listed.upperBound ..< body.endIndex))
        let perWindow = try XCTUnwrap(body.range(of: "isDestroyed()"))
        XCTAssertLessThan(alive.lowerBound, perWindow.lowerBound)
    }

    func testAPopupIsOnlyRecheckedSoonAfterItAppeared() {
        let now = Date()
        assertEquals(shouldRecheckPopup(registeredAt: now - 5, now: now), true)
        assertEquals(shouldRecheckPopup(registeredAt: now - 300, now: now), false)
    }
}
