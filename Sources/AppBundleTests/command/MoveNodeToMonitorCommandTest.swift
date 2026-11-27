@testable import AppBundle
import Common
import XCTest

@MainActor
final class MoveNodeToMonitorCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        testParseCommandSucc("move-node-to-monitor next", MoveNodeToMonitorCmdArgs(target: .relative(.next)))
        testParseCommandSucc("move-node-to-monitor --fail-if-noop main", MoveNodeToMonitorCmdArgs(target: .patterns([.main])).copy(\.failIfNoop, true))
        assertEquals(parseCommand("move-node-to-monitor --fail-if-noop next").errorOrNil, "--fail-if-noop is incompatible with (left|down|up|right|next|prev)")
        assertEquals(parseCommand("move-node-to-monitor --fail-if-noop left").errorOrNil, "--fail-if-noop is incompatible with (left|down|up|right|next|prev)")
    }

    /// The same refusal as `move-node-to-workspace`, which it goes through: a native-fullscreen window stays in
    /// its Space instead of becoming a tile on the other monitor.
    func testANativeFullscreenWindowIsRefused() async throws {
        let left = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let right = Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080)
        testMonitors = [
            MonitorImpl(monitorAppKitNsScreenScreensId: 1, name: "Left", rect: left, visibleRect: left),
            MonitorImpl(monitorAppKitNsScreenScreensId: 2, name: "Right", rect: right, visibleRect: right),
        ]
        rearrangeWorkspacesOnMonitors()
        let source = testMonitors[0].activeWorkspace
        let target = testMonitors[1].activeWorkspace
        let window = TestWindow.new(id: 1, parent: source.rootTilingContainer)
        window.layoutReason = .macos(prevParentKind: .tilingContainer, prevWorkspaceName: source.name)
        window.leaveTilesForMacos(source.macOsNativeFullscreenWindowsContainer, adaptiveWeight: WEIGHT_DOESNT_MATTER)

        let result = try await parseCommand("move-node-to-monitor --window-id 1 right").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 1)
        assertEquals(result.stderr, [moveOutMacosUnconventionalWindow])
        XCTAssertTrue(window.parent === source.macOsNativeFullscreenWindowsContainer, "the window moved")
        XCTAssertTrue(target.isEffectivelyEmpty)
    }
}
