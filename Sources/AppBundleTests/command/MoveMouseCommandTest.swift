@testable import AppBundle
import Common
import XCTest

/// `move-mouse` with a `window-*` target on a workspace that has no window.
///
/// This is the last mile of "the mouse follows the workspace": with
/// `on-focused-workspace-changed = ['move-mouse window-lazy-center']`, switching to an EMPTY
/// workspace used to leave the pointer on the monitor you came from -- the command errored with
/// "No window is focused" and moved nothing. Measured live: 8/10 switches moved the mouse, and both
/// misses were the empty workspace.
@MainActor
final class MoveMouseCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        XCTAssertTrue(parseCommand("move-mouse").errorOrNil?.contains("mandatory") == true)
        XCTAssertTrue(parseCommand("move-mouse nonsense").errorOrNil?.contains("Possible values") == true)
    }

    /// The fix: an empty workspace centres on its monitor rather than failing.
    func testEmptyWorkspaceFallsBackToTheMonitor() async throws {
        let workspace = Workspace.get(byName: "empty")
        XCTAssertTrue(workspace.focusWorkspace())
        XCTAssertNil(focus.windowOrNil, "precondition: the workspace must be empty")

        let r = try await runMoveMouse("window-force-center")
        assertEquals(r.exitCode, 0, additionalMsg: "move-mouse failed on an empty workspace: \(r.stderr)")
        XCTAssertFalse(r.stderr.joined().contains(noWindowIsFocused), "still reporting a missing window: \(r.stderr)")
    }

    // Deliberately NOT asserted here: that the pointer lands inside the monitor rect. `move-mouse`
    // posts a real CGEvent, so a coordinate assertion would move the developer's actual cursor and
    // then compare it against the test harness's fake 1920x1080 monitor. Verified live instead --
    // 10/10 switches put the pointer on the right monitor, empty workspaces included.

    /// A workspace that HAS a window is unaffected -- the fallback must not swallow the normal path.
    func testAWindowIsStillPreferredOverTheMonitor() async throws {
        let workspace = Workspace.get(byName: "occupied")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        XCTAssertTrue(workspace.focusWorkspace())
        assertEquals(focus.windowOrNil?.windowId, 1)
        let rect = Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100)
        window.lastAppliedLayoutPhysicalRect = rect

        // The rect, not the command: this one posts a real mouse event.
        let chosen = try await windowSubjectRectOrReportError(focus, CmdIo(stdin: .emptyStdin))
        assertEquals(chosen?.topLeftCorner, rect.topLeftCorner)
    }

    /// `move left; move-mouse window-lazy-center` went to the old spot, because the rect comes from layout
    /// and nothing had laid out the first command yet. In the source because the command moves the real mouse.
    func testASequenceIsLaidOutBeforeTheWindowsRectIsRead() throws {
        let body = try sourceBody("func run(_ env: CmdEnv", in: "Sources/AppBundle/command/impl/MoveMouseCommand.swift", length: 800)
        let layout = try XCTUnwrap(body.range(of: "try await layoutWorkspaces()"))
        let read = try XCTUnwrap(body.range(of: "windowSubjectRectOrReportError"))
        XCTAssertLessThan(layout.lowerBound, read.lowerBound)
    }

    private func runMoveMouse(_ target: String) async throws -> CmdResult {
        try await parseCommand("move-mouse \(target)").cmdOrDie.run(.defaultEnv, CmdStdin.emptyStdin)
    }
}

/// The stale-rect half of "the mouse follows the workspace".
///
/// `move-mouse` runs from `on-focused-workspace-changed`, which can fire before `layoutWorkspaces()`
/// has applied the new frames. `lastAppliedLayoutPhysicalRect` then still describes where the window
/// sat BEFORE the switch, on the monitor the user just left -- and `window-lazy-center`, seeing the
/// mouse already inside that stale rect, declines to move at all.
///
/// Asserted on the CHOSEN RECT rather than on the cursor: `move-mouse` posts a real CGEvent, so a
/// cursor assertion would move the developer's actual pointer, and "landed within the monitor" is
/// satisfied by both the stale and the fresh answer -- it would not distinguish them.
@MainActor
final class MoveMouseStaleRectTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func subjectRect(cachedRect: Rect?) async throws -> (chosen: Rect?, monitor: Rect) {
        let workspace = Workspace.get(byName: "target")
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = cachedRect
        XCTAssertTrue(workspace.focusWorkspace())
        let io = CmdIo(stdin: .emptyStdin)
        let chosen = try await windowSubjectRectOrReportError(focus, io)
        return (chosen, workspace.workspaceMonitor.rect)
    }

    /// A cached rect off the workspace's monitor is stale by definition: fall back to the monitor.
    func testARectOnAnotherMonitorIsRejectedAsStale() async throws {
        let (chosen, monitor) = try await subjectRect(cachedRect: Rect(topLeftX: 9000, topLeftY: 9000, width: 100, height: 100))
        assertEquals(chosen?.center, monitor.center, additionalMsg: "the stale rect was used instead of the monitor")
    }

    /// ...while a cached rect that IS on the right monitor is still used, so the fast path survives.
    func testAFreshRectOnTheRightMonitorIsUsed() async throws {
        let fresh = Rect(topLeftX: 10, topLeftY: 10, width: 200, height: 200)
        let (chosen, monitor) = try await subjectRect(cachedRect: fresh)
        assertEquals(chosen?.center, fresh.center)
        XCTAssertNotEqual(chosen?.center, monitor.center, "the fast path was lost -- every window now centres on the monitor")
    }

    /// No cached rect and no readable AX rect: still the monitor, never nil.
    func testNoRectAtAllStillYieldsTheMonitor() async throws {
        let (chosen, monitor) = try await subjectRect(cachedRect: nil)
        assertEquals(chosen?.center, monitor.center)
    }
}
