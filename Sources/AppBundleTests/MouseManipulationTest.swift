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

    /// A window's notifications carry its id, the whole 32 bits of it, and the app's carry none.
    func testTheRefconIsTheWindowId() {
        for id: UInt32 in [1, 4242, UInt32.max] {
            assertEquals(axRefconWindowId(axRefcon(windowId: id)), id)
        }
        assertEquals(axRefcon(windowId: nil), nil)
        assertEquals(axRefconWindowId(nil), nil)
    }

    /// Each move or resize during a drag asked the app which window it was, one IPC per event. The
    /// callbacks need a real `AXObserver`, so the wiring is pinned in the source.
    func testDragEventsNameTheirWindowByTheRefcon() throws {
        for (declaration, file) in [("func movedObs(", "moveWithMouse"), ("func resizedObs(", "resizeWithMouse")] {
            let body = try sourceBody(declaration, in: "Sources/AppBundle/mouse/\(file).swift")
            XCTAssertTrue(body.contains("axRefconWindowId(data)"), declaration)
            XCTAssertFalse(body.contains("containingWindowId"), declaration)
        }
        let window = try sourceBody("static func new(windowId: UInt32", in: "Sources/AppBundle/tree/MacApp.swift")
        XCTAssertTrue(window.contains("windowId: windowId)"), "a window subscribes without its id as the refcon")
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
