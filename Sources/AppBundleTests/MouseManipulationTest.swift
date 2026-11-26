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
