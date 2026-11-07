@testable import AppBundle
import AppKit
import Common
import XCTest

/// A native tab group is one window to the user, and macOS makes each tab a window of its own. Tiled as such,
/// every background tab held open a tile with nothing in it.
@MainActor
final class NativeTabsTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.gaps = .zero
        backgroundTabs = [:]
    }

    override func tearDown() async throws {
        backgroundTabs = [:]
    }

    private var workspace: Workspace { focus.workspace }
    private var root: TilingContainer { workspace.rootTilingContainer }
    private var hidden: MacosHiddenAppsWindowsContainer { workspace.macOsNativeHiddenAppsWindowsContainer }
    private var order: [UInt32] { root.allLeafWindowsRecursive.map(\.windowId) }
    private var waiting: [UInt32] { hidden.children.map { ($0 as! Window).windowId }.sorted() }

    private func tiles(_ weights: [CGFloat]) -> [LayoutTestWindow] {
        weights.enumerated().map { LayoutTestWindow.new(id: UInt32($0.offset + 1), parent: root, adaptiveWeight: $0.element) }
    }

    /// What registering a window does when it finds it's a tab: it starts as a tile like any new window, wherever
    /// focus was, and replaces the tab it opened from before anything lays it out.
    private func openTab(_ id: UInt32, from tab: Window, on workspace: Workspace? = nil) -> LayoutTestWindow {
        let window = LayoutTestWindow.new(id: id, parent: (workspace ?? self.workspace).rootTilingContainer)
        window.takePlace(of: tab)
        return window
    }

    /// What a refresh does once it knows which tabs are behind which.
    private func refresh(_ tabs: [UInt32: UInt32]) async throws {
        backgroundTabs = tabs
        try await normalizeLayoutReason()
        try await workspace.layoutWorkspace()
    }

    private func width(_ window: Window) -> CGFloat { window.lastAppliedLayoutPhysicalRect.orDie().width }

    /// The report: tabs of one group took a share of the monitor each, and the ones behind drew nothing there.
    func testAGroupOfTabsTakesOneTile() async throws {
        let windows = tiles([1, 1])
        try await workspace.layoutWorkspace()
        let half = width(windows[0])

        let second = openTab(3, from: windows[1])
        try await refresh([2: 3])
        let third = openTab(4, from: second)
        try await refresh([2: 4, 3: 4])

        assertEquals(order, [1, 4])
        assertEquals(waiting, [2, 3])
        XCTAssertEqual(width(windows[0]), half, accuracy: 0.01)
        XCTAssertEqual(width(third), half, accuracy: 0.01)
        XCTAssertTrue(root.awayWindows.isEmpty) // a tab keeps no place of its own to come back to
    }

    /// In the middle of a row at its own size, not at the average beside it.
    func testANewTabTakesThePlaceOfTheTabItOpenedFrom() async throws {
        let windows = tiles([300, 900, 300])
        try await workspace.layoutWorkspace()
        let before = width(windows[1])

        let tab = openTab(4, from: windows[1])
        try await refresh([2: 4])

        assertEquals(order, [1, 4, 3])
        XCTAssertEqual(width(tab), before, accuracy: 0.01)
        XCTAssertEqual(tab.lastAppliedLayoutPhysicalRect.orDie().topLeftX, windows[1].lastAppliedLayoutPhysicalRect.orDie().topLeftX, accuracy: 0.01)
    }

    func testSwitchingTabsKeepsThePlaceAndSize() async throws {
        let windows = tiles([300, 900, 300])
        try await workspace.layoutWorkspace()
        let before = width(windows[1])
        let tab = openTab(4, from: windows[1])
        try await refresh([2: 4])

        for (selected, behind) in [(windows[1], tab), (tab, windows[1]), (windows[1], tab)] {
            try await refresh([behind.windowId: selected.windowId])
            assertEquals(order, [1, selected.windowId, 3])
            assertEquals(waiting, [behind.windowId])
            XCTAssertEqual(width(selected), before, accuracy: 0.01)
            XCTAssertEqual(selected.layoutReason, .standard)
        }
    }

    /// Window > Merge All Windows: the selected tab was laid out already, so it stays and the other's tile closes.
    func testMergedWindowsCloseTheTileOfTheTabBehind() async throws {
        let windows = tiles([1, 1, 1])
        try await workspace.layoutWorkspace()

        try await refresh([1: 3])

        assertEquals(order, [2, 3])
        assertEquals(waiting, [1])
        XCTAssertEqual(width(windows[1]) + width(windows[2]), workspace.workspaceMonitor.visibleRect.width, accuracy: 0.01)
    }

    func testClosingTheSelectedTabHandsItsTileOn() async throws {
        let windows = tiles([300, 900, 300])
        try await workspace.layoutWorkspace()
        let weight = windows[1].getWeight(.h) // in points, now it has been laid out
        let t4 = openTab(4, from: windows[1])
        try await refresh([2: 4])
        let t5 = openTab(5, from: t4)
        try await refresh([2: 5, 4: 5])
        assertEquals(order, [1, 5, 3])

        t5.passTabPlaceOn()
        t5.unbindFromParent()

        assertEquals(order, [1, 4, 3]) // the latest of the two, deterministically
        XCTAssertEqual(t4.getWeight(.h), weight, accuracy: 0.01)
        assertEquals(backgroundTabs, [2: 4])

        // macOS picked the other one, and the next refresh is when that is known.
        try await refresh([4: 2])
        assertEquals(order, [1, 2, 3])
        XCTAssertEqual(windows[1].getWeight(.h), weight, accuracy: 0.01)
    }

    func testTheTileGoesWithTheLastTab() async throws {
        let windows = tiles([1, 1])
        windows[1].passTabPlaceOn()
        windows[1].unbindFromParent()
        assertEquals(order, [1])
    }

    /// Dragged out or moved to a new window: it is a window again, with a tile of its own.
    func testATabThatLeavesTheGroupGetsATile() async throws {
        let windows = tiles([1, 1])
        try await workspace.layoutWorkspace()
        _ = openTab(3, from: windows[1])
        try await refresh([2: 3])

        try await refresh([:])

        assertEquals(order.sorted(), [1, 2, 3])
        assertEquals(windows[1].layoutReason, .standard)
    }

    /// Otherwise the old workspace is kept alive by windows nobody can see, and comes back in the list.
    func testTheGroupMovesTogether() async throws {
        let windows = tiles([1, 1])
        try await workspace.layoutWorkspace()
        let tab = openTab(3, from: windows[1])
        try await refresh([2: 3])
        let start = workspace
        let other = Workspace.get(byName: "other")

        tab.bind(to: other.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        backgroundTabs = [2: 3]
        try await normalizeLayoutReason()

        assertEquals(windows[1].nodeWorkspace, other)
        assertEquals(start.macOsNativeHiddenAppsWindowsContainer.children.count, 0)
    }

    /// Opened while focus was somewhere else: a tab goes where its group is, not where any new window would.
    func testANewTabGoesWhereTheGroupIs() async throws {
        let windows = tiles([1, 1])
        let elsewhere = Workspace.get(byName: "elsewhere")
        LayoutTestWindow.new(id: 8, parent: elsewhere.rootTilingContainer)

        let tab = openTab(3, from: windows[1], on: elsewhere)

        assertEquals(tab.nodeWorkspace, workspace)
        assertEquals(order, [1, 3])
        assertEquals(waiting, [2])
        assertEquals(elsewhere.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [8])
    }

    /// No layout may see the old tab and the new one both tiled, because the row would squeeze for a frame.
    func testANewTabLeavesNoSecondTileEvenBeforeARefresh() async throws {
        let windows = tiles([1, 1])
        try await workspace.layoutWorkspace()
        let half = width(windows[0])

        let tab = openTab(3, from: windows[1])
        try await workspace.layoutWorkspace()

        assertEquals(order, [1, 3])
        XCTAssertEqual(width(tab), half, accuracy: 0.01)
        XCTAssertEqual(width(windows[0]), half, accuracy: 0.01)
    }

    /// Tabs changing in a group you aren't in don't take the workspace's focus.
    func testAGroupInTheBackgroundLeavesFocusAlone() async throws {
        let windows = tiles([1, 1])
        try await workspace.layoutWorkspace()
        _ = openTab(3, from: windows[1])
        try await refresh([2: 3])
        check(windows[0].focusWindow())

        try await refresh([3: 2])

        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 1)
    }

    /// Focus left on a tab that's now behind would push back to macOS and flip the tabs.
    func testFocusGoesWithTheSelection() async throws {
        let windows = tiles([1, 1])
        check(windows[1].focusWindow())
        try await workspace.layoutWorkspace()

        let tab = openTab(3, from: windows[1])
        try await refresh([2: 3])

        assertEquals(focus.windowOrNil?.windowId, 3)
        assertEquals(workspace.mostRecentWindowRecursive, tab)
    }

    /// Merged while it was the most recent: the workspace's focus falls back to a window of the group that shows.
    func testAMergedTabIsNotWhatAWorkspaceFallsBackTo() async throws {
        let windows = tiles([1, 1, 1])
        try await workspace.layoutWorkspace()
        windows[0].markAsMostRecentChild()

        try await refresh([1: 3])

        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3)
    }

    func testAeroSporkFullscreenStaysWithTheTile() async throws {
        let windows = tiles([1, 1])
        windows[1].isFullscreen = true
        windows[1].noOuterGapsInFullscreen = true
        try await workspace.layoutWorkspace()

        let tab = openTab(3, from: windows[1])
        try await refresh([2: 3])

        XCTAssertTrue(tab.isFullscreen)
        XCTAssertTrue(tab.noOuterGapsInFullscreen)
        XCTAssertFalse(windows[1].isFullscreen)
    }

    func testAFloatingGroupStaysFloating() async throws {
        let floating = LayoutTestWindow.new(id: 1, parent: workspace)

        let tab = openTab(2, from: floating)
        try await refresh([1: 2])

        XCTAssertTrue(tab.isFloating)
        assertEquals(order, [])
        assertEquals(waiting, [1])
    }

    /// `focus --window-id` on a tab behind: that is what selects it, and it needs the tile, not one of its own.
    func testFocusingABackgroundTabGivesItTheTile() async throws {
        let windows = tiles([300, 900, 300])
        try await workspace.layoutWorkspace()
        let weight = windows[1].getWeight(.h)
        let tab = openTab(4, from: windows[1])
        try await refresh([2: 4])

        try await windows[1].exitMacosMinimizedOrHidden()

        assertEquals(order, [1, 2, 3])
        assertEquals(backgroundTabs, [4: 2])
        XCTAssertEqual(windows[1].getWeight(.h), weight, accuracy: 0.01)
        assertEquals(tab.layoutReason, .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name))
    }

    /// A popup off the list is no tile to take over, whatever else it looks like.
    func testAPopupIsNoPlaceToTake() async throws {
        let popup = LayoutTestWindow.new(id: 1, parent: macosPopupWindowsContainer)
        defer { popup.unbindFromParent() }
        LayoutTestWindow.new(id: 2, parent: root)

        backgroundTabs = [1: 2]
        settleBackgroundTabs() // not the whole pass, which takes every popup for a `MacWindow`

        assertEquals(order, [2])
        XCTAssertTrue(popup.parent === macosPopupWindowsContainer)
    }

    /// An app with several groups.
    func testATabIsMatchedToItsGroupByTitleThenFrame() {
        let frame = Rect(topLeftX: 10, topLeftY: 20, width: 300, height: 400)
        let elsewhere = Rect(topLeftX: 500, topLeftY: 20, width: 300, height: 400)
        let groups = [
            TabGroup(selected: 1, titles: ["Documents", "Music"], frame: elsewhere),
            TabGroup(selected: 2, titles: ["Downloads", "Music"], frame: frame),
        ]
        assertEquals(tabGroup(titled: "Documents", at: frame, among: groups)?.selected, 1) // parked groups can share a frame
        assertEquals(tabGroup(titled: "Music", at: frame, among: groups)?.selected, 2) // both name it
        assertEquals(tabGroup(titled: "-zsh — 80x24", at: frame, among: groups)?.selected, 2) // Terminal's titles don't match
        assertEquals(tabGroup(titled: "Music", at: nil, among: groups)?.selected, 1)
        assertEquals(tabGroup(titled: nil, at: nil, among: groups)?.selected, 1) // moves a tile, leaves no gap
        assertEquals(tabGroup(titled: "Music", at: nil, among: [])?.selected, nil)
    }

    func testTheTabBarIsReadFromTheWindowsChildren() {
        let bar = FakeAxNode(role: kAXTabGroupRole, tabs: [FakeAxNode(role: kAXRadioButtonRole, title: "one"), FakeAxNode(role: kAXRadioButtonRole, title: "two")])
        let window = FakeAxNode(role: kAXWindowRole, children: [FakeAxNode(role: kAXToolbarRole), bar, FakeAxNode(role: kAXButtonRole)])
        assertEquals(window.tabTitles, ["one", "two"])
        assertEquals(FakeAxNode(role: kAXWindowRole, children: [FakeAxNode(role: kAXToolbarRole)]).tabTitles, nil)
    }
}

private struct FakeAxNode: AxUiElementMock {
    var role = ""
    var title = ""
    var children: [FakeAxNode] = []
    var tabs: [FakeAxNode] = []

    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        switch attr.key {
            case kAXRoleAttribute: role as? Attr.T
            case kAXTitleAttribute: title as? Attr.T
            case kAXChildrenAttribute: children.map { $0 as any AxUiElementMock } as? Attr.T
            case kAXTabsAttribute: tabs.map { $0 as any AxUiElementMock } as? Attr.T
            default: nil
        }
    }

    func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool { false }
    func containingWindowId() -> CGWindowID? { nil }
}
