@testable import AppBundle
import AppKit
import Common
import XCTest

/// `debug-windows --tree` dumps the tree AeroSpork holds without changing it.
@MainActor
final class DebugWindowsTreeTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws {
        for child in macosMinimizedWindowsContainer.children { child.unbindFromParent() }
    }

    func testParse() {
        assertNil(parseCommand("debug-windows --tree").errorOrNil)
        assertEquals(parseCommand("debug-windows --tree --window-id 1").errorOrNil, "ERROR: Conflicting options: --tree, --window-id")
    }

    func testTheDumpShowsTheTreeAndChangesNothing() async throws {
        let left = panel(x: 0, uuid: "L")
        let right = panel(x: 1920, uuid: "R")
        testMonitors = [left, right]
        let onLeft = Workspace.get(byName: "on-left")
        check(left.setActiveWorkspace(onLeft))
        check(right.setActiveWorkspace(Workspace.get(byName: "on-right")))
        TestWindow.new(id: 1, parent: onLeft.rootTilingContainer)
        let away = TestWindow.new(id: 2, parent: onLeft.rootTilingContainer)
        away.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: onLeft.name)
        away.leaveTilesForMacos(macosMinimizedWindowsContainer, adaptiveWeight: 1)
        let before = Workspace.all.map(\.name)

        let io = CmdIo(stdin: .emptyStdin)
        assertTrue(try await parseCommand("debug-windows --tree").cmdOrDie.run(.defaultEnv, io))

        assertEquals(Workspace.all.map(\.name), before)
        let dump = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(io.stdout.joined().utf8)) as? [String: Any])
        let monitors = try XCTUnwrap(dump["monitors"] as? [[String: Any]])
        assertEquals(monitors.map { $0["uuid"] as? String }, ["L", "R"])
        assertEquals(monitors.map { $0["visibleWorkspace"] as? String }, ["on-left", "on-right"])

        let tree = try XCTUnwrap(dump["tree"] as? [[String: Any]])
        let leftWorkspace = try XCTUnwrap(tree.first { $0["workspace"] as? String == "on-left" })
        let root = try XCTUnwrap((leftWorkspace["children"] as? [[String: Any]])?.singleOrNil())
        assertEquals(root["away"] as? [Int], [2])
        assertEquals((root["children"] as? [[String: Any]])?.map { $0["window"] as? Int }, [1])
        let minimized = try XCTUnwrap(tree.first { $0["container"] as? String == "macos-minimized" })
        assertEquals((minimized["children"] as? [[String: Any]])?.map { $0["window"] as? Int }, [2])
        assertEquals(dump["inconsistencies"] as? [String], [])
    }

    private func panel(x: CGFloat, uuid: String) -> MonitorImpl {
        let rect = Rect(topLeftX: x, topLeftY: 0, width: 1920, height: 1080)
        return MonitorImpl(
            monitorAppKitNsScreenScreensId: x == 0 ? 1 : 2, name: uuid, rect: rect, visibleRect: rect,
            fingerprint: MonitorFingerprint(displayUUID: uuid),
        )
    }
}
