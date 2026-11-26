@testable import AppBundle
import Common
import XCTest

/// What a window rule may run. "Open this app on that monitor" needs `move-node-to-monitor`, and a
/// migrated config that used it was rejected whole.
@MainActor
final class WindowRuleCommandsTest: XCTestCase {
    func testTheNewCommandsAreAccepted() {
        for run in [
            "['fullscreen on']",
            "['fullscreen on --no-outer-gaps']",
            "['move-node-to-monitor next']",
            "['layout floating', 'fullscreen on', 'move-node-to-monitor main']",
            "['layout tiling', 'move-node-to-workspace W']",
            "['sticky on']",
        ] {
            assertEquals(errors(run), [], additionalMsg: run)
        }
    }

    /// `move-node-to-workspace --focus-follows-window` passed before this change, so taking it away
    /// would remove a feature. The two moves accept the flag alike.
    func testBothMovesAcceptFocusFollowsWindow() {
        assertEquals(errors("['move-node-to-workspace --focus-follows-window W']"), [])
        assertEquals(errors("['move-node-to-monitor --focus-follows-window next']"), [])
    }

    func testTheShorthandAcceptsTheSameCommands() {
        guard case .success(let config) = parseConfig("[on-window]\n'com.apple.mail' = ['fullscreen on', 'move-node-to-monitor 2']") else {
            return XCTFail("the shorthand rejected a command the long form accepts")
        }
        assertEquals(config.onWindowDetected.singleOrNil()?.run.map { $0.args.description }, ["fullscreen on", "move-node-to-monitor 2"])
    }

    func testTheMoveComesLast() {
        XCTAssertTrue(errors("['move-node-to-monitor next', 'fullscreen on']").contains { $0.contains("must be the latest instruction") })
        XCTAssertTrue(errors("['move-node-to-workspace W', 'layout floating']").contains { $0.contains("must be the latest instruction") })
    }

    /// The two moves are one move between them: the second would undo the first.
    func testTheMoveAppearsOnlyOnce() {
        for run in [
            "['move-node-to-workspace W', 'move-node-to-monitor next']",
            "['move-node-to-monitor next', 'move-node-to-monitor prev']",
            "['move-node-to-workspace W', 'move-node-to-workspace V']",
        ] {
            XCTAssertTrue(errors(run).contains { $0.contains("only one 'move-node-to-workspace' or 'move-node-to-monitor'") }, run)
        }
    }

    /// A rule that toggles undoes itself when it runs a second time, so only the explicit `on`.
    func testFullscreenNeedsAnExplicitOn() {
        for run in ["['fullscreen']", "['fullscreen off']", "['sticky']", "['sticky off']"] {
            XCTAssertTrue(errors(run).contains { $0.contains("are the only commands that are supported") }, run)
        }
    }

    private func errors(_ run: String) -> [String] {
        switch parseConfig("[[on-window-detected]]\nrun = \(run)") {
            case .success: []
            case .failure(let errors): errors.descriptions
        }
    }
}
