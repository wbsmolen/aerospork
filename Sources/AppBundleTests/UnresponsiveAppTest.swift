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
        let body = try sourceBody("override func macosNativeState()", in: "Sources/AppBundle/tree/MacWindow.swift", length: 300)
        XCTAssertTrue(body.contains("?? nativeStateTheTreeRecords(for: self)"), "an unanswered read is reported as \"neither\" again")
    }

    func testEveryPassStartsWithACleanSlate() throws {
        for declaration in ["func runRefreshSessionBlocking(", "func runSession<T>("] {
            let body = try sourceBody(declaration, in: "Sources/AppBundle/layout/refresh.swift", length: 1800)
            let reset = try XCTUnwrap(body.range(of: "MacApp.timedOutThisPass = []"), "\(declaration) does not clear the record, so a recovered app stays skipped")
            let firstRead = try XCTUnwrap(body.range(of: "try await syncFocusFromMacOs()"))
            XCTAssertLessThan(reset.lowerBound, firstRead.lowerBound, "\(declaration) clears the record after its first AX read")
        }
    }

    func testAnAppThatTimedOutIsNotAskedAgainInTheSamePass() throws {
        let read = try sourceBody("private func withWindow<T>(", in: "Sources/AppBundle/tree/MacApp.swift", length: 900)
        XCTAssertTrue(read.contains("if MacApp.timedOutThisPass.contains(pid) { return nil }"))
        XCTAssertTrue(read.contains("MacApp.timedOutThisPass.insert(pid)"))

        let focused = try sourceBody("func getFocusedWindow()", in: "Sources/AppBundle/tree/MacApp.swift", length: 2600)
        XCTAssertTrue(focused.contains("if MacApp.timedOutThisPass.contains(pid) { throw NativeFocusUnknown() }"))
        XCTAssertTrue(focused.contains("MacApp.timedOutThisPass.insert(pid)"))

        let alive = try sourceBody("private func refreshAndGetAliveWindowIds", in: "Sources/AppBundle/tree/MacApp.swift", length: 2600)
        XCTAssertTrue(alive.contains("if timedOut { return true }"), "the alive filter asks every window of a stopped app")
        XCTAssertTrue(alive.contains("if !timedOut {"), "the window list is read from a stopped app")
    }
}
