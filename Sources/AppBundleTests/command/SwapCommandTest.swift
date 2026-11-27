@testable import AppBundle
import Common
import XCTest

@MainActor
final class SwapCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func swap(_ args: String) async throws -> Int32 {
        try await parseCommand("swap \(args)").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode
    }

    /// `move right` would have put window 1 into the container. Each window takes the other's slot and its size.
    func testASwapKeepsTheLayoutAndTheSizes() async throws {
        var (window1, window3): (Window?, Window?)
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 3).apply {
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 1)
                window3 = TestWindow.new(id: 3, parent: $0, adaptiveWeight: 2)
            }
        }
        window3!.markAsMostRecentChild() // the one `focus right` would pick
        check(window1!.focusWindow())

        assertEquals(try await swap("right"), 0)

        assertEquals(root.layoutDescription, .h_tiles([.window(3), .v_tiles([.window(2), .window(1)])]))
        assertEquals(window3!.hWeight, 1)
        assertEquals(window1!.vWeight, 2)
        assertEquals(focus.windowOrNil, window1) // focus went with the window
    }

    func testSwapFocusLeavesFocusWhereItWas() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        let window1 = TestWindow.new(id: 1, parent: root)
        let window2 = TestWindow.new(id: 2, parent: root)
        check(window1.focusWindow())

        assertEquals(try await swap("--swap-focus right"), 0)

        assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1)]))
        assertEquals(focus.windowOrNil, window2)
    }

    func testAtTheEdgeOnlyWrapAroundSwaps() async throws {
        let root = Workspace.get(byName: name).rootTilingContainer
        check(TestWindow.new(id: 1, parent: root).focusWindow())
        TestWindow.new(id: 2, parent: root)
        TestWindow.new(id: 3, parent: root)

        assertEquals(try await swap("left"), 1)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))

        assertEquals(try await swap("--wrap-around left"), 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(3), .window(2), .window(1)]))
    }

    /// The order `focus --dfs-index` counts in, across containers.
    func testDfsNextAndPrev() async throws {
        var window2: Window?
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                window2 = TestWindow.new(id: 2, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }
        }
        check(window2!.focusWindow())

        assertEquals(try await swap("dfs-next"), 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(3), .window(2)])]))

        assertEquals(try await swap("dfs-next"), 1) // the last one
        assertEquals(try await swap("dfs-prev"), 0)
        assertEquals(try await swap("dfs-prev"), 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(2), .v_tiles([.window(1), .window(3)])]))

        assertEquals(try await swap("dfs-prev"), 1) // the first one
        assertEquals(try await swap("--wrap-around dfs-prev"), 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(3), .v_tiles([.window(1), .window(2)])]))
    }

    func testAFloatingWindowHasNoPlaceToTrade() async throws {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        check(TestWindow.new(id: 2, parent: workspace).focusWindow())

        assertEquals(try await swap("left"), 1)
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
    }
}
