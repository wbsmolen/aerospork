@testable import AppBundle
import Common
import XCTest

/// `move` and `resize` on a floating window. Both only said it wasn't supported.
@MainActor
final class FloatingWindowCommandTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.gaps = .zero
    }

    private func floating(x: CGFloat = 100, y: CGFloat = 100, width: CGFloat = 400, height: CGFloat = 300) -> LayoutTestWindow {
        let window = LayoutTestWindow.new(id: 1, parent: focus.workspace, axRect: Rect(topLeftX: x, topLeftY: y, width: width, height: height))
        check(window.focusWindow())
        return window
    }

    private func run(_ command: String) async throws -> Int32 {
        try await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode
    }

    // MARK: - move

    func testMovingAFloatingWindow() async throws {
        let window = floating()
        assertEquals(try await run("move right"), 0)
        assertEquals(window.appliedFrames.last?.origin, CGPoint(x: 150, y: 100))
        assertEquals(try await run("move down"), 0)
        assertEquals(window.appliedFrames.last?.origin, CGPoint(x: 100, y: 150))
    }

    /// Past the monitor's edge is another workspace's screen.
    func testAFloatingWindowStopsAtTheMonitorsEdge() async throws {
        let window = floating(x: 1500, y: 0)
        assertEquals(try await run("move right"), 0)
        assertEquals(window.appliedFrames.last?.origin, CGPoint(x: 1520, y: 0))
    }

    func testAlreadyAtTheEdgeIsNotAMove() async throws {
        let window = floating(x: 0, y: 0)
        assertEquals(try await run("move left"), 0)
        XCTAssertTrue(window.appliedFrames.isEmpty)
        assertEquals(try await run("move --boundaries-action fail left"), 1)
    }

    // MARK: - resize

    func testResizingAFloatingWindow() async throws {
        let window = floating()
        assertEquals(try await run("resize width +100"), 0)
        assertEquals(window.appliedFrames.last, CGRect(x: 100, y: 100, width: 500, height: 300))
        assertEquals(window.lastFloatingSize, CGSize(width: 500, height: 300))
        assertEquals(try await run("resize height -100"), 0)
        assertEquals(window.appliedFrames.last, CGRect(x: 100, y: 100, width: 400, height: 200))
        assertEquals(try await run("resize width 700"), 0)
        assertEquals(window.appliedFrames.last, CGRect(x: 100, y: 100, width: 700, height: 300))
    }

    func testSmartResizesAFloatingWindowsWidthAndOppositeItsHeight() async throws {
        let window = floating()
        assertEquals(try await run("resize smart +50"), 0)
        assertEquals(window.appliedFrames.last, CGRect(x: 100, y: 100, width: 450, height: 300))
        assertEquals(try await run("resize smart-opposite +50"), 0)
        assertEquals(window.appliedFrames.last, CGRect(x: 100, y: 100, width: 400, height: 350))
    }

    func testGrowingPastTheEdgeMovesItBackOntoTheMonitor() async throws {
        let window = floating(x: 1500, y: 100)
        assertEquals(try await run("resize width 800"), 0)
        assertEquals(window.appliedFrames.last, CGRect(x: 1120, y: 100, width: 800, height: 300))
    }

    func testAFloatingWindowCannotOutgrowItsMonitor() async throws {
        let window = floating()
        assertEquals(try await run("resize width 99999"), 0)
        assertEquals(window.appliedFrames.last?.width, 1920)
        assertEquals(window.appliedFrames.last?.origin.x, 0)
    }

    func testAFloatingWindowCannotShrinkToNothing() async throws {
        let window = floating()
        assertEquals(try await run("resize width -99999"), 0)
        assertEquals(window.appliedFrames.last?.width, 1)
    }

    /// Parked off screen. Keeping the result on the monitor would bring it into view on someone else's screen.
    func testAFloatingWindowOnAHiddenWorkspaceIsLeftWhereItIs() async throws {
        let window = LayoutTestWindow.new(id: 7, parent: Workspace.get(byName: "hidden"))
        for command in ["move --window-id 7 right", "resize --window-id 7 width +100"] {
            assertEquals(try await run(command), 1, additionalMsg: command)
        }
        XCTAssertTrue(window.appliedFrames.isEmpty)
    }

    // MARK: - resize of a tiled window

    func testResizingATiledWindowTakesFromItsSiblings() async throws {
        let root = focus.workspace.rootTilingContainer
        let windows = (0 ..< 3).map { LayoutTestWindow.new(id: UInt32($0), parent: root, adaptiveWeight: 640) }
        check(windows[0].focusWindow())

        assertEquals(try await run("resize width +100"), 0)
        assertEquals(windows.map { $0.getWeight(.h) }, [740, 590, 590])
        assertEquals(try await run("resize smart -100"), 0)
        assertEquals(windows.map { $0.getWeight(.h) }, [640, 640, 640])
        assertEquals(try await run("resize width 900"), 0)
        assertEquals(windows.map { $0.getWeight(.h) }, [900, 510, 510])
    }

    /// Its weights are still 1 each, because layout puts them in points and it has never been laid out.
    /// `resize width 500` left the window 500 times the size of its siblings once it was shown.
    func testResizingOnAWorkspaceNeverShownIsInPoints() async throws {
        let root = Workspace.get(byName: "neverShown").rootTilingContainer
        let windows = (0 ..< 3).map { LayoutTestWindow.new(id: UInt32($0 + 10), parent: root) }

        assertEquals(try await run("resize --window-id 10 width 500"), 0)
        assertEquals(windows.map { $0.getWeight(.h) }, [500, 710, 710])
        assertEquals(try await run("resize --window-id 10 width +100"), 0)
        assertEquals(windows.map { $0.getWeight(.h) }, [600, 660, 660])
    }

    func testResizingInsideANestedContainerNeverShownIsInPoints() async throws {
        let root = Workspace.get(byName: "neverShown").rootTilingContainer
        LayoutTestWindow.new(id: 10, parent: root)
        let nested = TilingContainer(parent: root, adaptiveWeight: 1, .v, .tiles, index: INDEX_BIND_LAST)
        let windows = (0 ..< 2).map { LayoutTestWindow.new(id: UInt32($0 + 11), parent: nested) }

        assertEquals(try await run("resize --window-id 11 height 300"), 0)

        assertEquals(windows.map { $0.getWeight(.v) }, [300, 780])
    }

    func testAWindowInAnAccordionSaysWhyNotAndNotThatItFloats() async throws {
        focus.workspace.rootTilingContainer.layout = .accordion
        let window = LayoutTestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        check(window.focusWindow())

        let result = try await parseCommand("resize width +100").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        XCTAssertFalse(result.stderr.joined().contains("floating"), result.stderr.joined())
    }
}
