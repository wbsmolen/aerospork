@testable import AppBundle
import AppKit
import Common
import XCTest

/// A window macOS takes out of the tiles comes back to its place, not next to the most recent window.
/// Minimizing a middle window, or cmd-H on an app with several, used to reorder the row.
@MainActor
final class AwayWindowTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.gaps = .zero
    }

    /// That container is global, and the next suite's refresh would act on whatever is left in it.
    override func tearDown() async throws {
        for child in macosMinimizedWindowsContainer.children { child.unbindFromParent() }
    }

    private var workspace: Workspace { focus.workspace }
    private var root: TilingContainer { workspace.rootTilingContainer }

    private func row(_ ids: [UInt32], in parent: NonLeafTreeNodeObject? = nil) -> [LayoutTestWindow] {
        ids.map { LayoutTestWindow.new(id: $0, parent: parent ?? root) }
    }

    private func leave(_ window: Window) {
        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name)
        window.leaveTilesForMacos(macosMinimizedWindowsContainer, adaptiveWeight: 1)
    }

    private func comeBack(_ window: Window) async throws {
        try await exitMacOsNativeUnconventionalState(window: window, prevParentKind: .tilingContainer, workspace: workspace)
    }

    private var order: [UInt32] { root.allLeafWindowsRecursive.map(\.windowId) }

    func testAWindowComesBackToItsPlace() async throws {
        let windows = row([1, 2, 3])
        check(windows[2].focusWindow()) // the old answer was "next to this one"

        leave(windows[0])
        assertEquals(order, [2, 3])
        try await comeBack(windows[0])

        assertEquals(order, [1, 2, 3])
        XCTAssertTrue(root.awayWindows.isEmpty)
    }

    /// cmd-H takes all of an app's windows at once, and they return in whatever order.
    func testSeveralComeBackInAnyOrder() async throws {
        for returning in [[0, 1], [1, 0]] {
            setUpWorkspacesForTests()
            let windows = row([1, 2, 3, 4])
            leave(windows[1])
            leave(windows[2])
            assertEquals(order, [1, 4])

            for i in returning { try await comeBack(windows[i + 1]) }

            assertEquals(order, [1, 2, 3, 4], additionalMsg: "returning \(returning)")
        }
    }

    func testOthersCanComeBackAroundIt() async throws {
        let windows = row([1, 2, 3, 4, 5])
        for i in [0, 2, 4] { leave(windows[i]) }
        assertEquals(order, [2, 4])
        for i in [4, 0, 2] { try await comeBack(windows[i]) }
        assertEquals(order, [1, 2, 3, 4, 5])
    }

    /// The split, too: it used to come back at an average weight, whatever it had been.
    func testSizesComeBackInAnyOrder() async throws {
        for returning in [[0, 1], [1, 0]] {
            setUpWorkspacesForTests()
            config.gaps = .zero
            let weights: [CGFloat] = [960, 320, 320, 320]
            let windows = weights.enumerated().map { LayoutTestWindow.new(id: UInt32($0.offset + 1), parent: root, adaptiveWeight: $0.element) }
            try await workspace.layoutWorkspace()

            leave(windows[0])
            leave(windows[2])
            try await workspace.layoutWorkspace()
            for i in returning { try await comeBack(windows[i * 2]) }
            try await workspace.layoutWorkspace()

            for (window, weight) in zip(windows, weights) {
                XCTAssertEqual(window.getWeight(.h), weight, accuracy: 0.01, "returning \(returning): \(window)")
            }
        }
    }

    /// An index would go stale here.
    func testAWindowOpeningMeanwhileDoesNotMoveItsPlace() async throws {
        let windows = row([1, 2, 3])
        leave(windows[1])
        LayoutTestWindow.new(id: 9, parent: root, adaptiveWeight: WEIGHT_AUTO)
        assertEquals(order, [1, 3, 9])

        try await comeBack(windows[1])

        assertEquals(order, [1, 2, 3, 9])
    }

    func testAWindowClosingMeanwhileDoesNotMoveItsPlace() async throws {
        let windows = row([1, 2, 3])
        leave(windows[2])
        windows[1].unbindFromParent() // closed

        try await comeBack(windows[2])

        assertEquals(order, [1, 3])
    }

    func testItComesBackIntoItsNestedContainer() async throws {
        config.enableNormalizationFlattenContainers = true
        let first = row([1])[0]
        let nested = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: INDEX_BIND_LAST)
        let inner = row([2, 3], in: nested)
        leave(inner[1])

        workspace.normalizeContainers() // one window left in there, which would otherwise flatten it

        try await comeBack(inner[1])
        assertEquals(root.layoutDescription, .h_tiles([.window(first.windowId), .v_tiles([.window(2), .window(3)])]))
    }

    /// A container with nothing in it has to go, or it holds an empty tile. Its windows keep their position.
    func testAContainerThatEmptiesHandsItsWindowsUp() async throws {
        config.enableNormalizationFlattenContainers = true
        let outer = row([1])
        let nested = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: INDEX_BIND_LAST)
        let inner = row([2, 3], in: nested)
        let last = row([4])
        leave(inner[0])
        leave(inner[1])

        workspace.normalizeContainers()
        assertEquals(root.layoutDescription, .h_tiles([.window(outer[0].windowId), .window(last[0].windowId)]))

        try await comeBack(inner[1])
        try await comeBack(inner[0])
        assertEquals(order, [1, 2, 3, 4])
    }

    func testAClosedWindowStopsHoldingAContainerOpen() async throws {
        config.enableNormalizationFlattenContainers = true
        let nested = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: INDEX_BIND_LAST)
        let inner = row([2, 3], in: nested)
        row([1])
        leave(inner[1])
        workspace.normalizeContainers()
        XCTAssertNotNil(inner[0].parent as? TilingContainer)
        XCTAssertFalse(inner[0].parent === root)

        root.forgetAway { $0 == 3 }
        workspace.normalizeContainers()

        XCTAssertTrue(inner[0].parent === root)
    }

    func testWithNoPlaceKeptItGoesWhereANewWindowWould() async throws {
        let windows = row([1, 2])
        let stray = TestWindow.new(id: 3, parent: macosMinimizedWindowsContainer)
        check(windows[0].focusWindow())

        try await comeBack(stray)

        XCTAssertTrue(stray.parent === root)
    }

    /// A tree written while a window is away still names it, in its place, or a restart loses it.
    func testAFrozenTreeKeepsAWindowThatIsAway() {
        let windows = row([1, 2, 3])
        leave(windows[1])

        let frozen = FrozenContainer(root)

        assertEquals(frozen.allWindowIds, [1, 2, 3])
    }

    func testAFrozenTreeKeepsItsShare() {
        let windows = [LayoutTestWindow.new(id: 1, parent: root, adaptiveWeight: 500), LayoutTestWindow.new(id: 2, parent: root, adaptiveWeight: 300), LayoutTestWindow.new(id: 3, parent: root, adaptiveWeight: 200)]
        leave(windows[1])

        guard case .window(let frozen) = FrozenContainer(root).children[1] else { return XCTFail("not in its place") }

        // 30% of the whole row, while 700 points remain for the other 70%.
        XCTAssertEqual(frozen.weight, 300, accuracy: 0.01)
    }
}
