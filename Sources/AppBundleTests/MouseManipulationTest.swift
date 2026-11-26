@testable import AppBundle
import XCTest

final class MouseManipulationTest: XCTestCase {
    /// A stale drag flag is cleared on refresh only once the button is up.
    func testAStaleDragFlagIsResetOnlyWhenTheButtonIsUp() {
        XCTAssertTrue(shouldResetMouseManipulation(flag: true, buttonDown: false))
        XCTAssertFalse(shouldResetMouseManipulation(flag: true, buttonDown: true)) // a drag in progress
        XCTAssertFalse(shouldResetMouseManipulation(flag: false, buttonDown: false))
        XCTAssertFalse(shouldResetMouseManipulation(flag: false, buttonDown: true))
    }
}

/// Each drag event asked the focused app for its focused window, about 60 times a second.
@MainActor
final class DragFocusReadTest: XCTestCase {
    private var window: TestWindow!

    override func setUp() async throws {
        setUpWorkspacesForTests()
        window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        window.nativeFocus() // sets appForTests
    }

    override func tearDown() async throws {
        currentlyManipulatedWithMouseWindowId = nil
        TestApp.shared.focusedWindowReads = 0
    }

    /// The first event of a drag checks focus; the drag then takes the window (`moveTilingWindow` sets the id).
    private func startDrag(press: UInt32) async throws {
        let manipulated = try await isManipulatedWithMouse(window, buttonDown: true, press: press)
        XCTAssertTrue(manipulated)
        currentlyManipulatedWithMouseWindowId = window.windowId
        TestApp.shared.focusedWindowReads = 0
    }

    func testTheSamePressIsNotCheckedAgain() async throws {
        try await startDrag(press: 7)
        let manipulated = try await isManipulatedWithMouse(window, buttonDown: true, press: 7)
        XCTAssertTrue(manipulated)
        assertEquals(TestApp.shared.focusedWindowReads, 0)
    }

    /// The id alone can be stale, after a missed mouse-up. A new press is checked again.
    func testANewPressIsCheckedAgain() async throws {
        try await startDrag(press: 7)
        let manipulated = try await isManipulatedWithMouse(window, buttonDown: true, press: 8)
        XCTAssertTrue(manipulated)
        assertEquals(TestApp.shared.focusedWindowReads, 1)
    }

    func testAnotherWindowIsNotManipulatedAndCostsNoRead() async throws {
        try await startDrag(press: 7)
        let other = TestWindow.new(id: 2, parent: focus.workspace.rootTilingContainer)
        let manipulated = try await isManipulatedWithMouse(other, buttonDown: true, press: 7)
        XCTAssertFalse(manipulated)
        assertEquals(TestApp.shared.focusedWindowReads, 0)
    }
}
