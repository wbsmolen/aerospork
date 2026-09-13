@testable import Common
import XCTest

/// `isUserInitiated` decides which focus changes reach the always-on `session` log. Get it wrong one
/// way and a hotkey switch is logged as the window manager acting on its own, burying the real
/// report; the other way and an involuntary focus change is silent -- which is how issue #39 arrived
/// with nothing to diagnose it from.
final class RefreshSessionEventTest: XCTestCase {
    func testWhatCountsAsThePersonAsking() {
        let asked: [RefreshSessionEvent] = [
            .hotkeyBinding, .socketServer, .menuBarButton,
            .globalObserverLeftMouseUp, .resetManipulatedWithMouse,
            // Only reaches a *session* from a drag or resize under the pointer; see `isUserInitiated`.
            .ax("AXMoved"),
        ]
        let notAsked: [RefreshSessionEvent] = [
            .globalObserver("didActivateApplication"), .startup,
            .onFocusedMonitorChanged, .onFocusedWorkspaceChanged, .onFocusChanged,
        ]
        for event in asked {
            XCTAssertTrue(event.isUserInitiated, "\(event) is something a person did")
        }
        for event in notAsked {
            XCTAssertFalse(event.isUserInitiated, "\(event) is the world moving, and must be logged as such")
        }
    }
}
