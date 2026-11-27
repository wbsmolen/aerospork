@testable import AppBundle
import Common
import Foundation
import XCTest

/// The scratchpad: a global container that hangs off no workspace, and the id set that says which windows are
/// scratchpad windows, whether put away or shown on a workspace.
@MainActor
final class ScratchpadTest: XCTestCase {
    private var tempDir: URL?

    override func setUp() async throws { setUpWorkspacesForTests() }

    override func tearDown() async throws {
        testMonitors = [defaultTestMonitor]
        backgroundTabs = [:]
        config.onWindowDetected = []
        WorkspaceMemory.resetForTests()
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func run(_ command: String) async throws -> CmdResult {
        try await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
    }

    /// A window the app draws at 400x300 at the origin, which is also its floating size.
    @discardableResult
    private func window(_ id: UInt32, on workspace: Workspace, floating: Bool = false) -> TestWindow {
        let window = TestWindow.new(
            id: id,
            parent: floating ? workspace : workspace.rootTilingContainer,
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 400, height: 300),
        )
        window.lastFloatingSize = CGSize(width: 400, height: 300)
        return window
    }

    // MARK: - Putting away and showing

    func testPuttingAwayTakesATiledWindowOffItsWorkspace() async throws {
        let a = focus.workspace
        let away = window(1, on: a)
        window(2, on: a)
        XCTAssertTrue(away.focusWindow())

        assertEquals(try await run("move-node-to-scratchpad").exitCode, 0)

        XCTAssertTrue(away.parent === scratchpadContainer)
        XCTAssertTrue(away.isScratchpad)
        assertEquals(a.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [2])
        XCTAssertTrue(a.rootTilingContainer.awayWindows.isEmpty, "a window in the scratchpad kept a place in the tiles")
        assertEquals(focus.windowOrNil?.windowId, 2, additionalMsg: "focus did not fall back to the window left behind")
    }

    func testScratchpadShowsTheWindowFloatingAndCentredThenPutsItBack() async throws {
        let away = window(1, on: Workspace.get(byName: "a"))
        try await away.moveToScratchpad()
        let b = Workspace.get(byName: "b")
        let there = window(2, on: b)
        XCTAssertTrue(there.focusWindow())

        assertEquals(try await run("scratchpad").exitCode, 0)

        XCTAssertTrue(away.parent === b, "it did not come to the focused workspace, floating")
        assertEquals(focus.windowOrNil?.windowId, away.windowId)
        // Centred on the 1920x1080 test monitor at its floating size.
        let rect = try await away.getAxRect()
        assertEquals(rect?.topLeftCorner, CGPoint(x: 760, y: 390))
        assertEquals(rect?.size, CGSize(width: 400, height: 300))
        XCTAssertTrue(away.isScratchpad)

        assertEquals(try await run("scratchpad").exitCode, 0)

        XCTAssertTrue(away.parent === scratchpadContainer, "a second press did not put it back")
        assertEquals(focus.windowOrNil?.windowId, there.windowId)
    }

    func testScratchpadShowsTheWindowPutAwayLast() async throws {
        let a = Workspace.get(byName: "a")
        let first = window(1, on: a)
        let last = window(2, on: a)
        try await first.moveToScratchpad()
        try await last.moveToScratchpad()

        assertEquals(try await run("scratchpad").exitCode, 0)

        assertEquals(focus.windowOrNil?.windowId, last.windowId)
        XCTAssertTrue(first.parent === scratchpadContainer)
    }

    /// As in i3: a scratchpad window you can already see gets the focus before another one comes out.
    func testAScratchpadWindowOnTheFocusedWorkspaceIsFocusedFirst() async throws {
        let a = focus.workspace
        let shown = window(1, on: a, floating: true)
        shown.isScratchpad = true
        let typingIn = window(2, on: a)
        let stowed = window(3, on: a)
        try await stowed.moveToScratchpad()
        XCTAssertTrue(typingIn.focusWindow())

        assertEquals(try await run("scratchpad").exitCode, 0)

        assertEquals(focus.windowOrNil?.windowId, shown.windowId)
        XCTAssertTrue(stowed.parent === scratchpadContainer)
    }

    func testAScratchpadWindowShownElsewhereComesHereWhenTheScratchpadIsEmpty() async throws {
        let shown = window(1, on: Workspace.get(byName: "a"), floating: true)
        shown.isScratchpad = true
        let b = Workspace.get(byName: "b")
        XCTAssertTrue(b.focusWorkspace())

        assertEquals(try await run("scratchpad").exitCode, 0)

        XCTAssertTrue(shown.parent === b)
        assertEquals(focus.windowOrNil?.windowId, shown.windowId)
    }

    func testAppBundleIdPicksTheApp() async throws {
        let away = window(1, on: focus.workspace)
        try await away.moveToScratchpad()

        assertEquals(try await run("scratchpad --app-bundle-id com.example.other").exitCode, 1)
        XCTAssertTrue(away.parent === scratchpadContainer)

        assertEquals(try await run("scratchpad --app-bundle-id \(TestApp.shared.bundleId!)").exitCode, 0)
        XCTAssertTrue(away.parent === focus.workspace)
    }

    /// cmd-tab to an app whose only window is put away: macOS names that window, and it must come out, or the
    /// keyboard goes to a window nobody can see. Not right after it was put away, while macOS still names it.
    func testAPutAwayWindowMacOsFocusesComesOut() async throws {
        resetFocusCacheForTests()
        let a = focus.workspace
        let away = window(1, on: a)
        let other = window(2, on: a)
        updateFocusCache(away)
        try await away.moveToScratchpad()
        XCTAssertFalse(macOsFocusedAPutAwayScratchpadWindow(away), "macOS still naming the window just put away is not news")

        updateFocusCache(other)
        XCTAssertTrue(macOsFocusedAPutAwayScratchpadWindow(away))
        XCTAssertFalse(macOsFocusedAPutAwayScratchpadWindow(other), "a window on a workspace needs nothing")
        try await away.showFromScratchpad(on: focus.workspace)
        updateFocusCache(away)
        assertEquals(focus.windowOrNil?.windowId, 1, additionalMsg: "the shown window could not take focus")
        XCTAssertTrue(away.isScratchpad, "a shown scratchpad window is still a scratchpad window")
    }

    func testAnEmptyScratchpadIsAnError() async throws {
        let result = try await run("scratchpad")
        assertEquals(result.exitCode, 1)
        assertEquals(result.stderr, ["The scratchpad is empty"])
    }

    func testAMinimizedScratchpadWindowComesBackFromTheDock() async throws {
        let minimized = TestWindow.new(id: 1, parent: macosMinimizedWindowsContainer)
        minimized.layoutReason = .macos(prevParentKind: .workspace, prevWorkspaceName: "a")
        minimized.isScratchpad = true
        let b = Workspace.get(byName: "b")
        XCTAssertTrue(b.focusWorkspace())

        assertEquals(try await run("scratchpad").exitCode, 0)

        XCTAssertTrue(minimized.parent === b)
        assertEquals(minimized.layoutReason, .standard)
    }

    // MARK: - Leaving the scratchpad

    func testMovingOrTilingAShownWindowTakesItOutOfTheScratchpad() async throws {
        let a = focus.workspace
        let moved = window(1, on: a, floating: true)
        let tiled = window(2, on: a, floating: true)
        moved.isScratchpad = true
        tiled.isScratchpad = true

        XCTAssertTrue(moved.focusWindow())
        assertEquals(try await run("move-node-to-workspace elsewhere").exitCode, 0)
        XCTAssertTrue(tiled.focusWindow())
        assertEquals(try await run("layout tiling").exitCode, 0)

        XCTAssertFalse(moved.isScratchpad)
        XCTAssertFalse(tiled.isScratchpad)
        XCTAssertTrue(tiled.parent is TilingContainer)
    }

    func testStickyAndScratchpadAreExclusive() async throws {
        let a = focus.workspace
        let sticky = window(1, on: a, floating: true)
        sticky.isSticky = true
        XCTAssertTrue(sticky.focusWindow())

        assertEquals(try await run("move-node-to-scratchpad").exitCode, 0)
        XCTAssertFalse(sticky.isSticky, "a window in the scratchpad would follow the screen back out")

        assertEquals(try await run("scratchpad").exitCode, 0)
        assertEquals(try await run("sticky on").exitCode, 0)
        XCTAssertTrue(sticky.isSticky)
        XCTAssertFalse(sticky.isScratchpad, "a sticky window would be put away by the next scratchpad press")

        assertEquals(try await run("scratchpad").exitCode, 1, additionalMsg: "the sticky window went back in the scratchpad")
    }

    func testWhatCannotGoInTheScratchpad() async throws {
        let fullscreen = TestWindow.new(id: 1, parent: focus.workspace.macOsNativeFullscreenWindowsContainer)
        assertEquals(try await run("move-node-to-scratchpad --window-id 1").exitCode, 1)
        XCTAssertTrue(fullscreen.parent is MacosFullscreenWindowsContainer)
        assertEquals(try await run("move-node-to-scratchpad").exitCode, 1, additionalMsg: "no window is focused")
    }

    func testAWindowAlreadyInTheScratchpadIsANoop() async throws {
        try await window(1, on: focus.workspace).moveToScratchpad()
        assertEquals(try await run("move-node-to-scratchpad --window-id 1").exitCode, 0)
        assertEquals(try await run("move-node-to-scratchpad --window-id 1 --fail-if-noop").exitCode, 1)
    }

    // MARK: - On no workspace

    /// Every workspace enumeration reads `Workspace.all`, so a window that is on no workspace is out of all of
    /// them: `list-workspaces`, `next`/`prev`, the menu bar and `list-windows --all`, which leaves out minimized
    /// windows the same way.
    func testAWindowInTheScratchpadIsOnNoWorkspace() async throws {
        let only = Workspace.get(byName: "only")
        XCTAssertTrue(only.focusWorkspace())
        try await window(1, on: only).moveToScratchpad()
        XCTAssertTrue(Workspace.get(byName: "other").focusWorkspace())
        refreshModel()

        assertEquals(Workspace.all.map(\.name), ["other"])
        assertEquals(try await run("list-workspaces --all").stdout, ["other"])
        assertEquals(try await run("list-windows --all --count").stdout, ["0"])
        assertEquals(try await run("workspace --wrap-around next").exitCode, 0)
        assertEquals(focus.workspace.name, "other")
        updateTrayText()
        assertEquals(TrayMenuModel.shared.workspaces.map(\.name), ["other"])
    }

    func testTheContainerOutlivesTheCollection() async throws {
        let away = window(1, on: focus.workspace)
        try await away.moveToScratchpad()
        Workspace.garbageCollectUnusedWorkspaces()
        refreshModel()
        XCTAssertTrue(away.parent === scratchpadContainer)
    }

    /// `layoutWorkspaces` parks only `MacWindow`s, which need a real app, so the wiring is pinned in the source, as
    /// `ParkPositionTest` pins it for a hidden workspace's windows.
    func testTheLayoutParksTheScratchpadAgainstTheFocusedMonitor() throws {
        let layout = try sourceBody("func layoutWorkspaces(", in: "Sources/AppBundle/layout/refresh.swift")
        XCTAssertTrue(layout.contains("parkScratchpadWindows(monitors: monitors, onlyUnparked: parkOnlyUnparked)"))
        let park = try sourceBody("func parkScratchpadWindows(", in: "Sources/AppBundle/tree/ScratchpadContainer.swift")
        XCTAssertTrue(park.contains("focus.workspace.workspaceMonitor"))
        XCTAssertTrue(park.contains("shouldPark("), "a background tab of the scratchpad would be parked")
    }

    // MARK: - Restarts, the lock screen and quitting

    private func useTempMemoryFile() {
        let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "scratchpad-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir
        WorkspaceMemory.fileUrlOverride = dir.appending(path: "state.json")
    }

    private func load(_ windows: [String: WorkspaceMemory.WindowEntry]) throws {
        let state = WorkspaceMemory.State(session: WorkspaceMemory.session(), windows: windows, workspaceMonitors: [:])
        try JSONEncoder().encode(state).write(to: WorkspaceMemory.fileUrl)
        scratchpadWindowIds = []
        WorkspaceMemory.load()
    }

    func testTheMemoryRemembersAWindowInTheScratchpad() async throws {
        useTempMemoryFile()
        let away = window(1, on: Workspace.get(byName: "a"))
        try await away.moveToScratchpad()
        let entry = try XCTUnwrap(WorkspaceMemory.entry(for: away)).entry
        assertEquals(entry.isScratchpad, true)

        try load(["1": entry])

        XCTAssertTrue(scratchpadWindowIds.contains(1), "the restart forgot the window was in the scratchpad")
        XCTAssertTrue(WorkspaceMemory.returnsToScratchpad(windowId: 1))
        // Spent, and neither half of a workspace restored.
        assertNil(WorkspaceMemory.restoredWorkspace(forWindowId: 1, bundleId: TestApp.shared.bundleId))
    }

    /// A scratchpad window on screen comes back on screen, on its workspace, and is still a scratchpad window.
    func testTheMemoryRemembersAShownScratchpadWindowWhereItIs() throws {
        useTempMemoryFile()
        let shown = window(1, on: Workspace.get(byName: "a"), floating: true)
        shown.isScratchpad = true
        let entry = try XCTUnwrap(WorkspaceMemory.entry(for: shown)).entry

        try load(["1": entry])

        XCTAssertFalse(WorkspaceMemory.returnsToScratchpad(windowId: 1))
        assertEquals(WorkspaceMemory.restoredWorkspace(forWindowId: 1, bundleId: TestApp.shared.bundleId)?.name, "a")
        XCTAssertTrue(scratchpadWindowIds.contains(1))
    }

    func testTheKeyIsWrittenOnlyWhenTrueAndAFileWithoutItLoads() throws {
        useTempMemoryFile()
        let ordinary = try XCTUnwrap(WorkspaceMemory.entry(for: window(1, on: Workspace.get(byName: "a")))).entry
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(ordinary), encoding: .utf8))
        XCTAssertFalse(json.contains("isScratchpad"), json)

        let old = #"{"session":"\#(WorkspaceMemory.session())","windows":{"42":{"workspace":"A","bundleId":"b"}},"workspaceMonitors":{}}"#
        try Data(old.utf8).write(to: WorkspaceMemory.fileUrl)
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "b"), "A")
        XCTAssertFalse(WorkspaceMemory.returnsToScratchpad(windowId: 42))
    }

    /// The lock screen collects live windows, and they register again with the same id and no file entry.
    func testAWindowCollectedByTheLockScreenGoesBackInTheScratchpad() {
        scratchpadWindowIds = [5]
        XCTAssertTrue(WorkspaceMemory.returnsToScratchpad(windowId: 5))
        XCTAssertFalse(WorkspaceMemory.returnsToScratchpad(windowId: 6))
    }

    /// The quit cleanup puts a parked window back on its workspace's monitor. A window in the scratchpad has no
    /// workspace, so it goes on the main monitor, not on whichever one it was parked against.
    func testAtQuitAWindowInTheScratchpadGoesBackOnTheMainMonitor() async throws {
        let left = MonitorImpl(monitorAppKitNsScreenScreensId: 1, name: "Left", rect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080), visibleRect: Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080))
        let right = MonitorImpl(monitorAppKitNsScreenScreensId: 2, name: "Right", rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080), visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080))
        testMonitors = [left, right]
        rearrangeWorkspacesOnMonitors()
        XCTAssertTrue(right.setActiveWorkspace(Workspace.get(byName: "R")))
        XCTAssertTrue(Workspace.get(byName: "R").focusWorkspace())
        let away = window(1, on: Workspace.get(byName: "R"))
        try await away.moveToScratchpad()

        assertEquals(away.unparkedMonitor?.rect.topLeftX, 0)

        let quit = try sourceBody("private func makeAllWindowsVisibleAndRestoreSize(", in: "Sources/AppBundle/util/appBundleUtil.swift")
        XCTAssertTrue(quit.contains("window.parent is ScratchpadContainer"), "the quit cleanup centres a scratchpad window by where it is parked")
    }

    // MARK: - Native tabs

    /// A tab group is one window: the selected tab takes the group in and out of the scratchpad, and the
    /// scratchpad window is whichever tab is selected.
    func testATabGroupGoesInAndOutOfTheScratchpadTogether() async throws {
        let a = focus.workspace
        let selected = window(1, on: a)
        let tab = TestWindow.new(id: 2, parent: a.macOsNativeHiddenAppsWindowsContainer)
        tab.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: a.name)
        backgroundTabs = [2: 1]
        XCTAssertTrue(selected.focusWindow())

        assertEquals(try await run("move-node-to-scratchpad").exitCode, 0)
        settleBackgroundTabs()
        XCTAssertTrue(tab.parent === scratchpadContainer, "the background tab kept the workspace it left")

        backgroundTabs = [1: 2] // macOS selects the other tab while the group is put away
        settleBackgroundTabs()
        XCTAssertTrue(selected.parent === scratchpadContainer)
        XCTAssertTrue(tab.parent === scratchpadContainer)
        XCTAssertTrue(tab.isScratchpad)
        XCTAssertFalse(selected.isScratchpad, "the group counts as two scratchpad windows")

        let b = Workspace.get(byName: "b")
        XCTAssertTrue(b.focusWorkspace())
        assertEquals(try await run("scratchpad").exitCode, 0)
        XCTAssertTrue(tab.parent === b, "the selected tab did not come out")
        settleBackgroundTabs()
        XCTAssertTrue(selected.parent === b.macOsNativeHiddenAppsWindowsContainer, "the background tab stayed in the scratchpad")
    }
}
