@testable import AppBundle
import Common
import XCTest

//
// test 1
//     horizontal
//         window1
//         vertical
//             vertical
//                 window2 <-- focused
//             vertical
//                 window5
//                 horizontal
//                     window3
//                     window4
// pre-condition: focus_wrapping force_workspace
// action: focus up
// expected: mru(window3, window4) is focused

@MainActor
final class FocusCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// Unbinding floating windows across awaits left the earlier ones detached when a later read threw,
    /// and a detached window crashes on the next "already unbound".
    func testAFailedReadLeavesFloatingWindowsWhereTheyWere() async throws {
        let workspace = Workspace.get(byName: name)
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        let readable = TestWindow.new(id: 2, parent: workspace, rect: Rect(topLeftX: 10, topLeftY: 10, width: 50, height: 50))
        let unreadable = TestWindow.new(id: 3, parent: workspace)
        unreadable.axRectFails = true
        check(workspace.focusWorkspace())

        do {
            _ = try await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTFail("the read should have thrown")
        } catch is CancellationError {}

        XCTAssertTrue(readable.parent === workspace)
        XCTAssertTrue(unreadable.parent === workspace)
    }

    /// With nothing tiled, directional focus found nothing to place them beside and did nothing.
    func testFloatingWindowsAloneCanBeFocusedByDirection() async throws {
        let workspace = Workspace.get(byName: name)
        let left = TestWindow.new(id: 1, parent: workspace, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
        let middle = TestWindow.new(id: 2, parent: workspace, rect: Rect(topLeftX: 500, topLeftY: 0, width: 100, height: 100))
        let right = TestWindow.new(id: 3, parent: workspace, rect: Rect(topLeftX: 1000, topLeftY: 0, width: 100, height: 100))
        check(left.focusWindow())

        _ = try await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        _ = try await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)

        for window in [left, middle, right] { XCTAssertTrue(window.parent === workspace, "\(window) stayed tiled") }
    }

    /// An empty root can be the most recent child while a floating window sits beside it.
    func testTheMostRecentWindowIsFoundPastAnEmptyRoot() {
        let workspace = Workspace.get(byName: name)
        let floating = TestWindow.new(id: 1, parent: workspace)
        workspace.rootTilingContainer.markAsMostRecentChild()

        assertEquals(workspace.mostRecentWindowRecursive?.windowId, floating.windowId)
    }

    func testAMinimizedWindowCanBeFocused() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: macosMinimizedWindowsContainer)
        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: workspace.name)

        try await window.exitMacosMinimizedOrHidden()

        XCTAssertTrue(window.nodeWorkspace === workspace)
        assertEquals(window.layoutReason, .standard)
        XCTAssertTrue(window.focusWindow())
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    /// Through the command, because resolving a target fails on a minimized window, and it has to be
    /// brought back before that. Found live: the method alone passed and the command still failed.
    func testTheCommandBringsAMinimizedWindowBackBeforeResolvingIt() throws {
        let body = try sourceBody("func run(_ env: CmdEnv", in: "Sources/AppBundle/command/impl/FocusCommand.swift", length: 600)
        let bringBack = try XCTUnwrap(body.range(of: "exitMacosMinimizedOrHidden()"))
        let resolve = try XCTUnwrap(body.range(of: "resolveTargetOrReportError"))
        XCTAssertLessThan(bringBack.lowerBound, resolve.lowerBound)
    }

    func testAWindowOfAHiddenAppCanBeFocused() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.macOsNativeHiddenAppsWindowsContainer)
        window.layoutReason = .macos(prevParentKind: .workspace, prevWorkspaceName: workspace.name)

        try await window.exitMacosMinimizedOrHidden()

        XCTAssertTrue(window.parent === workspace, "it was floating before it was hidden")
        assertEquals(window.layoutReason, .standard)
    }

    func testAnOrdinaryWindowIsLeftAlone() async throws {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let parent = window.parent

        try await window.exitMacosMinimizedOrHidden()

        XCTAssertTrue(window.parent === parent)
    }

    func testParse() {
        XCTAssertTrue(parseCommand("focus --boundaries left").errorOrNil?.contains("Possible values") == true)
        var expected = FocusCmdArgs(rawArgs: [], direction: .left)
        expected.rawBoundaries = .workspace
        testParseCommandSucc("focus --boundaries workspace left", expected)

        assertEquals(
            parseCommand("focus --boundaries workspace --boundaries workspace left").errorOrNil,
            "ERROR: Duplicated option '--boundaries'",
        )
        assertEquals(
            parseCommand("focus --window-id 42 --ignore-floating").errorOrNil,
            "--window-id is incompatible with other options",
        )
    }

    func testFocus() {
        assertEquals(focus.windowOrNil, nil)
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusAlongTheContainerOrientation() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        try await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusAcrossTheContainerOrientation() async throws {
        Workspace.get(byName: name).apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
            TestWindow.new(id: 2, parent: $0.rootTilingContainer)
            assertEquals($0.focusWorkspace(), true)
        }

        assertEquals(focus.windowOrNil?.windowId, 2)
        try await FocusCommand.new(direction: .up).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        try await FocusCommand.new(direction: .down).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusNoWrapping() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        try await FocusCommand.new(direction: .left).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusWrapping() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.windowOrNil?.windowId, 1)
        var args = FocusCmdArgs(rawArgs: [], direction: .left)
        args.rawBoundaries = .workspace
        args.rawBoundariesAction = .wrapAroundTheWorkspace
        try await FocusCommand(args: args).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusFindMruLeaf() async throws {
        let workspace = Workspace.get(byName: name)
        var startWindow: Window!
        var window2: Window!
        var window3: Window!
        var unrelatedWindow: Window!
        workspace.rootTilingContainer.apply {
            startWindow = TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    window2 = TestWindow.new(id: 2, parent: $0)
                    unrelatedWindow = TestWindow.new(id: 5, parent: $0)
                }
                window3 = TestWindow.new(id: 3, parent: $0)
            }
        }

        assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3) // The latest bound
        _ = startWindow.focusWindow()
        try await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)

        window2.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        try await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)

        window3.markAsMostRecentChild()
        unrelatedWindow.markAsMostRecentChild()
        _ = startWindow.focusWindow()
        try await FocusCommand.new(direction: .right).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testFocusOutsideOfTheContainer() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        try await FocusCommand.new(direction: .left).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusOutsideOfTheContainer2() async throws {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            }
        }

        try await FocusCommand.new(direction: .left).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }
}

extension FocusCommand {
    static func new(direction: CardinalDirection) -> FocusCommand {
        FocusCommand(args: FocusCmdArgs(rawArgs: [], direction: direction))
    }
}
