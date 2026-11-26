@testable import AppBundle
import Common
import Foundation
import XCTest

/// A sticky window follows the workspace its monitor shows. One pass in `refreshModel`, `followVisibleWorkspaces`,
/// does it for every way the visible workspace changes.
@MainActor
final class StickyWindowTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    override func tearDown() async throws {
        stickyWindowIds = []
        testMonitors = [defaultTestMonitor]
        WorkspaceMemory.resetForTests()
    }

    private func run(_ command: String) async throws -> CmdResult {
        try await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
    }

    func testFollowsAWorkspaceSwitch() async throws {
        let a = Workspace.get(byName: "a")
        XCTAssertTrue(a.focusWorkspace())
        let sticky = TestWindow.new(id: 1, parent: a)
        sticky.isSticky = true
        let there = TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)

        assertEquals(try await run("workspace b").exitCode, 0) // a command sequence ends in `refreshModel`

        XCTAssertTrue(sticky.parent === Workspace.get(byName: "b"), "the sticky window stayed on the workspace that left the screen")
        XCTAssertTrue(sticky.isFloating)
        assertEquals(focus.windowOrNil?.windowId, there.windowId, additionalMsg: "the switch landed somewhere it would not have without the sticky window")
        assertEquals(Workspace.get(byName: "b").mostRecentWindowRecursive?.windowId, there.windowId, additionalMsg: "the sticky window took the workspace's focus fallback")
    }

    func testAFocusedStickyWindowKeepsFocusOnAnEmptyWorkspace() {
        let a = Workspace.get(byName: "a")
        let sticky = TestWindow.new(id: 1, parent: a)
        sticky.isSticky = true
        XCTAssertTrue(sticky.focusWindow())

        XCTAssertTrue(Workspace.get(byName: "b").focusWorkspace())
        refreshModel()

        assertEquals(focus.workspace.name, "b")
        assertEquals(focus.windowOrNil?.windowId, sticky.windowId)
    }

    func testFollowsAMonitorRearrange() {
        let left = panel(id: 1, x: 0)
        let right = panel(id: 2, x: 1920)
        testMonitors = [left, right]
        rearrangeWorkspacesOnMonitors()
        XCTAssertTrue(left.setActiveWorkspace(Workspace.get(byName: "L")))
        XCTAssertTrue(right.setActiveWorkspace(Workspace.get(byName: "R")))
        let sticky = TestWindow.new(id: 1, parent: Workspace.get(byName: "R"))
        sticky.isSticky = true

        testMonitors = [left] // the right panel is unplugged
        gcMonitors()
        refreshModel()

        XCTAssertTrue(sticky.parent === left.activeWorkspace, "the sticky window stayed behind on a workspace no monitor shows")
    }

    func testSurvivesAWorkspaceMemoryRoundTrip() throws {
        try remember(#"{"workspace":"a","bundleId":"b","isFloating":true,"isSticky":true}"#)
        let window = TestWindow.new(id: 42, parent: Workspace.get(byName: "a"))
        WorkspaceMemory.restoreState(of: window)
        XCTAssertTrue(window.isSticky)

        let entry = WorkspaceMemory.WindowEntry(workspace: "a", bundleId: "b", isSticky: true)
        assertEquals(try JSONDecoder().decode(WorkspaceMemory.WindowEntry.self, from: JSONEncoder().encode(entry)), entry)
        let notSticky = String(decoding: try JSONEncoder().encode(WorkspaceMemory.WindowEntry(workspace: "a", bundleId: "b")), as: UTF8.self)
        XCTAssertFalse(notSticky.contains("isSticky"), "a window that is not sticky still wrote the key: \(notSticky)")
    }

    func testAFileWithoutTheKeyStillDecodes() throws {
        try remember(#"{"workspace":"a","bundleId":"b"}"#)
        let window = TestWindow.new(id: 42, parent: Workspace.get(byName: "a"))
        WorkspaceMemory.restoreState(of: window)
        XCTAssertFalse(window.isSticky)
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "b"), "a")
    }

    func testMoveNodeToWorkspaceClearsTheFlag() async throws {
        let sticky = TestWindow.new(id: 1, parent: focus.workspace)
        sticky.isSticky = true

        assertEquals(try await run("move-node-to-workspace --window-id 1 b").exitCode, 0)

        XCTAssertFalse(sticky.isSticky)
        assertEquals(sticky.nodeWorkspace?.name, "b")
    }

    /// The move rebinds a window. Focus did not change, so `on-focus-changed` has nothing to report.
    func testNoFocusCallbackFires() {
        let left = panel(id: 1, x: 0)
        let right = panel(id: 2, x: 1920)
        testMonitors = [left, right]
        rearrangeWorkspacesOnMonitors()
        XCTAssertTrue(left.setActiveWorkspace(Workspace.get(byName: "L")))
        XCTAssertTrue(right.setActiveWorkspace(Workspace.get(byName: "R")))
        let typingIn = TestWindow.new(id: 1, parent: Workspace.get(byName: "L").rootTilingContainer)
        XCTAssertTrue(typingIn.focusWindow())
        let sticky = TestWindow.new(id: 2, parent: Workspace.get(byName: "R"))
        sticky.isSticky = true
        checkOnFocusChangedCallbacks() // takes in the focus as it is now
        _prevFocus = nil

        XCTAssertTrue(right.setActiveWorkspace(Workspace.get(byName: "R2"))) // the other monitor switches
        refreshModel()

        XCTAssertTrue(sticky.parent === Workspace.get(byName: "R2"), "the test needs the window to have moved")
        XCTAssertNil(_prevFocus, "the move counted as a focus change")
        assertEquals(focusedWindowId, typingIn.windowId)
    }

    func testThePassIsSkippedWhenNoWindowIsSticky() {
        let a = Workspace.get(byName: "a")
        XCTAssertTrue(a.focusWorkspace())
        let floating = TestWindow.new(id: 1, parent: a)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)

        XCTAssertTrue(Workspace.get(byName: "b").focusWorkspace())
        refreshModel()

        XCTAssertTrue(stickyWindowIds.isEmpty)
        XCTAssertTrue(floating.parent === a, "a window nobody made sticky followed the screen")
    }

    /// macOS has it. It comes back through `takeAwaySlot`, to the workspace it left.
    func testAMinimizedStickyWindowStaysWhereMacOsHasIt() {
        let sticky = TestWindow.new(id: 1, parent: macosMinimizedWindowsContainer)
        defer { sticky.unbindFromParent() } // the minimized container is global and outlives the test
        sticky.isSticky = true

        XCTAssertTrue(Workspace.get(byName: "b").focusWorkspace())
        refreshModel()

        XCTAssertTrue(sticky.parent === macosMinimizedWindowsContainer)
        XCTAssertTrue(sticky.isSticky)
    }

    func testStickyOnFloatsATiledWindowAndTheToggleTurnsItOff() async throws {
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        XCTAssertTrue(window.focusWindow())

        assertEquals(try await run("sticky").exitCode, 0)
        XCTAssertTrue(window.isSticky)
        XCTAssertTrue(window.isFloating, "a sticky window is a floating one")
        assertEquals(try await run("sticky on --fail-if-noop").exitCode, 1)

        assertEquals(try await run("sticky").exitCode, 0)
        XCTAssertFalse(window.isSticky)
        XCTAssertTrue(window.isFloating, "turning sticky off moved the window")
    }

    func testATiledWindowStopsBeingSticky() {
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        window.isSticky = true // a window tiled since it was made sticky
        refreshModel()
        XCTAssertFalse(window.isSticky)
    }

    func testTheFormatVariable() async throws {
        let window = TestWindow.new(id: 1, parent: focus.workspace)
        window.isSticky = true
        assertEquals(try await run("list-windows --all --format %{window-is-sticky}").stdout, ["true"])
    }

    private func remember(_ entry: String) throws {
        WorkspaceMemory.fileUrlOverride = URL(filePath: NSTemporaryDirectory()).appending(path: "sticky-\(UUID().uuidString).json")
        WorkspaceMemory.forceSessionForTests("s")
        try Data(#"{"session":"s","windows":{"42":\#(entry)},"workspaceMonitors":{}}"#.utf8).write(to: WorkspaceMemory.fileUrl)
        WorkspaceMemory.load()
        try? FileManager.default.removeItem(at: WorkspaceMemory.fileUrl)
    }

    private func panel(id: Int, x: CGFloat) -> MonitorImpl {
        let rect = Rect(topLeftX: x, topLeftY: 0, width: 1920, height: 1080)
        return MonitorImpl(monitorAppKitNsScreenScreensId: id, name: "Panel \(id)", rect: rect, visibleRect: rect, fingerprint: nil)
    }
}
