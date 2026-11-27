@testable import AppBundle
import Common
import XCTest

@MainActor
final class MoveNodeToWorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseCommandSucc("move-node-to-workspace next", MoveNodeToWorkspaceCmdArgs(target: .relative(.next)))
        assertEquals(parseCommand("move-node-to-workspace --fail-if-noop next").errorOrNil, "--fail-if-noop is incompatible with (next|prev)")
    }

    func testSimple() async throws {
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        XCTAssertTrue(workspaceA.isEffectivelyEmpty)
        assertEquals((Workspace.get(byName: "b").rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 1)
    }

    /// The exit code, not the tree. `moveWindowToWorkspace` used to `return focusFollowsWindow ?
    /// window.focusWindow() : false`, so the default `move-node-to-workspace <name>` -- the single
    /// most common command in an i3-style config -- moved the window correctly and then exited 1
    /// with nothing on stderr. Every `&&` chain and every script checking `$?` saw a failure.
    func testASuccessfulMoveExitsZeroEvenWhenFocusStaysBehind() async throws {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        let io = CmdIo(stdin: .emptyStdin)
        let succ = MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, io)

        XCTAssertTrue(succ, "successful move reported failure. stderr: \(io.stderr)")
        assertEquals(io.stderr, [])
        // ...and it really did stay behind, so this is not passing because focus now follows.
        assertEquals(focus.workspace.name, "a")
    }

    /// The counter-check for the above: `--focus-follows-window` still has to do something, or the
    /// fix could have been "always return true" with the focus call deleted.
    func testFocusFollowsWindowStillMovesFocus() async throws {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        let args = MoveNodeToWorkspaceCmdArgs(workspace: "b").copy(\.focusFollowsWindow, true)
        let succ = MoveNodeToWorkspaceCommand(args: args).run(.defaultEnv, CmdIo(stdin: .emptyStdin))

        XCTAssertTrue(succ)
        assertEquals(focus.workspace.name, "b")
    }

    func testEmptyWorkspaceSubject() async throws {
        let workspaceA = Workspace.get(byName: "a")
        workspaceA.rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "a")
    }

    func testAnotherWindowSubject() async throws {
        Workspace.get(byName: "a").rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            _ = TestWindow.new(id: 2, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testPreserveFloatingLayout() async throws {
        let workspaceA = Workspace.get(byName: "a").apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
        }

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b")).run(.defaultEnv, .emptyStdin)
        XCTAssertTrue(workspaceA.isEffectivelyEmpty)
        assertEquals(Workspace.get(byName: "b").children.filterIsInstance(of: Window.self).singleOrNil()?.windowId, 1)
    }

    func testSummonWindow() async throws {
        let workspaceA = Workspace.get(byName: "a").apply {
            $0.rootTilingContainer.apply {
                _ = TestWindow.new(id: 1, parent: $0).focusWindow()
            }
        }
        Workspace.get(byName: "b").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
        }

        assertEquals(focus.workspace, workspaceA)

        try await MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "a").copy(\.windowId, 2))
            .run(.defaultEnv, .emptyStdin)

        assertEquals(focus.workspace, workspaceA)
        assertEquals(focus.windowOrNil?.windowId, 1)
        assertEquals(Workspace.get(byName: "b").rootTilingContainer.children.count, 0)
        assertEquals(workspaceA.rootTilingContainer.children.count, 2)
    }

    /// macOS owns a native-fullscreen or hidden-app window. Moving one bound it into the target's tiles while its
    /// reason stayed `.macos`, so the target tiled a window in its own Space (or hidden), and the source kept a
    /// stale away slot. Refused, like `move` refuses it.
    func testANativeFullscreenWindowIsRefused() {
        assertRefused(from: Workspace.get(byName: "a").macOsNativeFullscreenWindowsContainer)
    }

    func testAHiddenAppWindowIsRefused() {
        assertRefused(from: Workspace.get(byName: "a").macOsNativeHiddenAppsWindowsContainer)
    }

    /// A minimized window has no workspace, so the command already fails before the macOS-owned guard.
    func testAMinimizedWindowIsRefused() {
        let window = TestWindow.new(id: 1, parent: macosMinimizedWindowsContainer)
        let io = CmdIo(stdin: .emptyStdin)
        let succ = MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b").copy(\.windowId, 1)).run(.defaultEnv, io)

        XCTAssertFalse(succ)
        XCTAssertTrue(window.parent === macosMinimizedWindowsContainer, "the window moved")
        XCTAssertTrue(Workspace.get(byName: "b").isEffectivelyEmpty)
    }

    private func assertRefused(from container: NonLeafTreeNodeObject) {
        let workspaceA = Workspace.get(byName: "a")
        let window = TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: "a")
        window.leaveTilesForMacos(container, adaptiveWeight: WEIGHT_DOESNT_MATTER)

        let io = CmdIo(stdin: .emptyStdin)
        let succ = MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "b").copy(\.windowId, 1)).run(.defaultEnv, io)

        XCTAssertFalse(succ)
        assertEquals(io.stderr, [moveOutMacosUnconventionalWindow])
        XCTAssertTrue(window.parent === container, "the window moved")
        assertEquals(workspaceA.rootTilingContainer.awayWindows.map(\.id), [1])
        XCTAssertTrue(Workspace.get(byName: "b").isEffectivelyEmpty)
    }
}
