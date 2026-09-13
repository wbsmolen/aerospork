@testable import AppBundle
import AppKit
import XCTest

/// "The settings window never appears" and "two copies running" (#40).
///
/// AeroSpork registered its own process like any other app, so its Settings window was bound to a
/// workspace and parked off screen on the next switch. The menu item opened the scene without
/// activating the app, so the window could open behind everything. Launching the binary by hand while
/// the login item ran started a second window manager that took over the CLI socket.
@MainActor
final class OwnWindowsAndSingleInstanceTest: XCTestCase {
    private var savedOpener: (() -> Void)?

    override func setUp() async throws { savedOpener = settingsOpener }
    override func tearDown() async throws { settingsOpener = savedOpener }

    // MARK: - Our own windows

    /// A source check: registering a real `MacApp` spawns an AX thread, and in a test process whose
    /// subscription fails anyway, a behavioural check would pass with the guard deleted.
    func testAeroSporkNeverRegistersItsOwnProcess() throws {
        let body = try sourceBody("static func getOrRegister(_ nsApp: NSRunningApplication)", in: "Sources/AppBundle/tree/MacApp.swift", length: 1200)
        let guardLine = try XCTUnwrap(
            body.range(of: "if nsApp.processIdentifier == ProcessInfo.processInfo.processIdentifier { return nil }"),
            "AeroSpork manages its own windows again",
        )
        let firstLookup = try XCTUnwrap(body.range(of: "allAppsMap[pid]"))
        XCTAssertLessThan(guardLine.lowerBound, firstLookup.lowerBound, "an already-registered self would skip the guard")
    }

    func testTheMenuItemGoesThroughTheFunctionThatActivatesTheApp() throws {
        let source = try withoutComments(String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/MenuBar.swift"), encoding: .utf8))
        XCTAssertFalse(source.contains("SettingsLink"), "SettingsLink opens Settings without activating the app")
        XCTAssertTrue(source.contains(#"Button("Settings…") { openSettingsWindow() }"#))
    }

    func testOpeningSettingsPutsTheWindowInFront() throws {
        let open = try sourceBody("func openSettingsWindow()", in: "Sources/AppBundle/ui/MenuBar.swift", length: 400)
        XCTAssertTrue(open.contains("bringSettingsWindowForward()"), "reopening an existing window leaves it behind")
        let window = try sourceBody("override func viewDidMoveToWindow()", in: "Sources/AppBundle/ui/ConfigurationWindow.swift", length: 800)
        XCTAssertTrue(window.contains("bringSettingsWindowForward()"), "a first open leaves the new window behind")
    }

    /// Finder, Spotlight or `open -a` on the running app did nothing visible.
    func testReopeningTheRunningAppOpensSettings() {
        var opened = 0
        settingsOpener = { opened += 1 }

        let handledByAppKit = AeroSporkAppDelegate().applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)

        assertEquals(opened, 1)
        XCTAssertFalse(handledByAppKit)
    }

    // MARK: - One copy at a time

    func testTheNewerCopyYieldsToTheOlderOne() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        assertEquals(runningCopyToYieldTo(me: (pid: 50, launchDate: newer), others: [(pid: 60, launchDate: older)]), 60)
        assertEquals(runningCopyToYieldTo(me: (pid: 60, launchDate: older), others: [(pid: 50, launchDate: newer)]), nil)
    }

    /// The login item and a hand launch at the same moment: exactly one of the two must keep running.
    func testTwoCopiesStartingTogetherLeaveExactlyOne() {
        let same = Date(timeIntervalSince1970: 100)
        for (a, b) in [((pid_t(10), Optional(same)), (pid_t(20), Optional(same))), ((10, nil), (20, same)), ((10, nil), (20, nil))] {
            let aYields = runningCopyToYieldTo(me: (pid: a.0, launchDate: a.1), others: [(pid: b.0, launchDate: b.1)]) != nil
            let bYields = runningCopyToYieldTo(me: (pid: b.0, launchDate: b.1), others: [(pid: a.0, launchDate: a.1)]) != nil
            XCTAssertTrue(aYields != bYields, "both or neither yielded for \(a) vs \(b)")
        }
    }

    /// The inputs, not just the decision. In `App.init`, where the check runs,
    /// `NSRunningApplication.current` reports pid -1 and no launch date, so every new copy would look
    /// oldest and none would ever yield -- while the table tests above still passed.
    func testThisCopyIsIdentifiedByItsRealPidAndStartTime() throws {
        let me = currentCopyIdentity()
        assertEquals(me.pid, ProcessInfo.processInfo.processIdentifier)
        let started = try XCTUnwrap(me.launchDate, "no start time for this process")
        XCTAssertLessThanOrEqual(started, Date())
        let launchd = try XCTUnwrap(processStartDate(1), "no start time for launchd")
        XCTAssertLessThan(launchd, started, "the clock does not order processes")
    }

    func testTheCheckNeverAsksAppKitWhoThisProcessIs() throws {
        let body = try sourceBody("private func exitIfAnotherCopyIsRunning()", in: "Sources/AppBundle/initAppBundle.swift", length: 900)
        XCTAssertFalse(body.contains("NSRunningApplication.current"), "pid -1 before NSApplication exists")
        XCTAssertTrue(body.contains("runningCopyToYieldTo(me: currentCopyIdentity()"))
    }

    func testAloneItRuns() {
        assertEquals(runningCopyToYieldTo(me: (pid: 10, launchDate: Date()), others: [(pid: 10, launchDate: Date())]), nil)
        assertEquals(runningCopyToYieldTo(me: (pid: 10, launchDate: Date()), others: []), nil)
    }

    /// Yielding after the socket is bound would already have taken the running copy's socket.
    func testTheCheckRunsBeforeAnythingWithSideEffects() throws {
        let body = try sourceBody("public func initAppBundle()", in: "Sources/AppBundle/initAppBundle.swift", length: 4000)
        let check = try XCTUnwrap(body.range(of: "exitIfAnotherCopyIsRunning()"))
        for sideEffect in ["sendCommandToReleaseServer", "interceptTermination(SIGINT)", "WorkspaceMemory.load()", "startUnixSocketServer()"] {
            let site = try XCTUnwrap(body.range(of: sideEffect), sideEffect)
            XCTAssertLessThan(check.lowerBound, site.lowerBound, "\(sideEffect) runs before the single-instance check")
        }
    }
}
