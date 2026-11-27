@testable import AppBundle
import AppKit
import Common
import XCTest

/// `new-window-placement = 'nest'`: a new window shares the focused window's tile instead of squeezing the row.
@MainActor
final class NewWindowPlacementTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.gaps = .zero
        config.newWindowPlacement = .nest
        backgroundTabs = [:]
    }

    override func tearDown() async throws {
        for child in macosMinimizedWindowsContainer.children { child.unbindFromParent() }
        backgroundTabs = [:]
    }

    private var workspace: Workspace { focus.workspace }
    private var root: TilingContainer { workspace.rootTilingContainer }

    /// What registration does: bind beside the focused window (the same code, through `relayoutWindow`), run the
    /// rules, then place it.
    @discardableResult
    private func open(_ id: UInt32, on workspace: Workspace? = nil, isRemembered: Bool = false, isNewTab: Bool = false) async throws -> LayoutTestWindow {
        let workspace = workspace ?? self.workspace
        let window = LayoutTestWindow.new(id: id, parent: workspace)
        try await window.relayoutWindow(on: workspace, forceTile: true)
        window.applyNewWindowPlacement(isRemembered: isRemembered, isNewTab: isNewTab)
        return window
    }

    private func focused(_ window: Window) { check(window.focusWindow()) }

    /// Windows already open, side by side.
    private func row(_ ids: [UInt32]) -> [LayoutTestWindow] { ids.map { LayoutTestWindow.new(id: $0, parent: root) } }

    func testSiblingIsTheDefaultAndChangesNothing() async throws {
        config.newWindowPlacement = Config().newWindowPlacement
        assertEquals(config.newWindowPlacement, .sibling)
        focused(try await open(1))
        focused(try await open(2))
        try await open(3)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
    }

    /// With normalization on, the default, a nested container takes the opposite orientation: the dwindle pattern.
    func testNestingAlternatesWithNormalizationOn() async throws {
        config.enableNormalizationFlattenContainers = true
        config.enableNormalizationOppositeOrientationForNestedContainers = true
        let first = try await open(1)
        focused(first)
        let second = try await open(2) // alone with the first, nesting would only flip the root
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
        focused(second)
        let third = try await open(3)
        focused(third)
        try await open(4)
        workspace.normalizeContainers()

        assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(3), .window(4)])])]))
    }

    /// The new window takes half of the focused tile, and the rest of the row keeps its size.
    func testTheRestOfTheRowKeepsItsSize() async throws {
        let windows = [try await open(1), try await open(2)]
        try await workspace.layoutWorkspace()
        let before = windows[0].lastAppliedLayoutPhysicalRect.orDie().width
        focused(windows[1])
        let third = try await open(3)
        try await workspace.layoutWorkspace()

        XCTAssertEqual(windows[0].lastAppliedLayoutPhysicalRect.orDie().width, before, accuracy: 0.01)
        XCTAssertEqual(third.lastAppliedLayoutPhysicalRect.orDie().width, windows[1].lastAppliedLayoutPhysicalRect.orDie().width, accuracy: 0.01)
    }

    /// With normalization off, the split follows the focused tile's longer side.
    func testNestingFollowsTheLongerSideWithNormalizationOff() async throws {
        focused(try await open(1))
        let second = try await open(2)
        focused(second)
        try await workspace.layoutWorkspace() // two halves of a wide monitor: each is taller than wide
        try await open(3)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))

        setUpWorkspacesForTests()
        config.newWindowPlacement = .nest
        let windows = row([1, 2, 3])
        root.changeOrientation(.v) // three rows of a wide monitor: each is wider than tall
        try await workspace.layoutWorkspace()
        focused(windows[1])
        try await open(4)
        assertEquals(root.layoutDescription, .v_tiles([.window(1), .h_tiles([.window(2), .window(4)]), .window(3)]))
    }

    func testARememberedWindowDoesNotNest() async throws {
        focused(try await open(1))
        focused(try await open(2))
        try await open(3, isRemembered: true)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
    }

    /// A new tab took its group's tile; nesting it would split the group.
    func testANewTabDoesNotNest() async throws {
        focused(try await open(1))
        let group = try await open(2)
        focused(group)
        let tab = try await open(3, isNewTab: true)
        tab.takePlace(of: group)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(3)]))
    }

    func testNotAtStartup() async throws {
        focused(try await open(1))
        focused(try await open(2))
        _ = try await $_isStartup.withValue(true) { try await open(3) }
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
    }

    /// Minimized and back: it returns to its place, not into a nest with the focused window.
    func testAnAwayWindowComingBackDoesNotNest() async throws {
        let windows = row([1, 2, 3])
        windows[0].layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name)
        windows[0].leaveTilesForMacos(macosMinimizedWindowsContainer, adaptiveWeight: 1)
        focused(windows[2])
        try await exitMacOsNativeUnconventionalState(window: windows[0], prevParentKind: .tilingContainer, workspace: workspace)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
    }

    /// The away window keeps its place when the tile it came after is nested.
    func testAwayWindowsKeepTheirPlacesAroundANest() async throws {
        let windows = row([1, 2, 3])
        windows[2].layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name)
        windows[2].leaveTilesForMacos(macosMinimizedWindowsContainer, adaptiveWeight: 1)
        focused(windows[1])
        try await open(4)
        try await exitMacOsNativeUnconventionalState(window: windows[2], prevParentKind: .tilingContainer, workspace: workspace)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(4)]), .window(3)]))
    }

    /// `layout tiling` and the move commands bind through the same code as registration, and must not nest.
    func testLayoutTilingDoesNotNest() async throws {
        focused(try await open(1))
        focused(try await open(2))
        let floating = LayoutTestWindow.new(id: 3, parent: workspace)
        assertEquals(try await parseCommand("layout tiling").cmdOrDie.run(.defaultEnv.copy(\.windowId, floating.windowId), .emptyStdin).exitCode, 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
    }

    /// A rule that moved the new window nests it on the workspace it went to, beside that workspace's focus, once.
    func testARuleThatMovesTheWindowNestsItWhereItLands() async throws {
        let other = Workspace.get(byName: "other")
        let there = [LayoutTestWindow.new(id: 10, parent: other.rootTilingContainer), LayoutTestWindow.new(id: 11, parent: other.rootTilingContainer)]
        there[0].markAsMostRecentChild()
        focused(try await open(1))
        focused(try await open(2))

        let window = LayoutTestWindow.new(id: 3, parent: workspace)
        try await window.relayoutWindow(on: workspace, forceTile: true)
        assertEquals(try await parseCommand("move-node-to-workspace other").cmdOrDie.run(.defaultEnv.copy(\.windowId, window.windowId), .emptyStdin).exitCode, 0)
        window.applyNewWindowPlacement(isRemembered: false, isNewTab: false)

        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
        assertEquals(other.rootTilingContainer.layoutDescription, .h_tiles([.v_tiles([.window(10), .window(3)]), .window(11)]))
    }

    /// Accordion stacks windows: there is no tile to share.
    func testNoNestInAnAccordion() async throws {
        root.layout = .accordion
        focused(try await open(1))
        focused(try await open(2))
        try await open(3)
        assertEquals(root.layoutDescription, .h_accordion([.window(1), .window(2), .window(3)]))
    }

    /// Registration places the window after its rules, and only when it is neither remembered nor a tab.
    func testRegistrationPlacesTheWindowAfterItsRules() throws {
        let body = try sourceBody("static func getOrRegister(windowId: UInt32", in: "Sources/AppBundle/tree/MacWindow.swift")
        let rules = try XCTUnwrap(body.range(of: "tryOnWindowDetected("))
        let placement = try XCTUnwrap(body.range(of: "window.applyNewWindowPlacement(isRemembered: isRemembered, isNewTab: isNewTab)"))
        XCTAssertLessThan(rules.lowerBound, placement.lowerBound)
        let shield = try XCTUnwrap(body.range(of: "shieldedFromCancellation {"))
        XCTAssertLessThan(shield.lowerBound, placement.lowerBound)
    }
}
