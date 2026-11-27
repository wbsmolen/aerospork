@testable import Common
import XCTest

final class LateinitTest: XCTestCase {
    /// `&&` binds tighter than `||`, so the old `==` called any two initialized values equal, and
    /// `testParseCommandSucc` could not tell `workspace next` from `workspace prev`.
    func testEquality() {
        XCTAssertTrue(Lateinit.initialized(1) == .initialized(1))
        XCTAssertFalse(Lateinit.initialized(1) == .initialized(2))
        XCTAssertFalse(Lateinit.initialized("next") == .initialized("prev"))
        XCTAssertFalse(Lateinit.initialized(1) == .uninitialized)
        XCTAssertFalse(Lateinit.uninitialized == .initialized(1))
        XCTAssertTrue(Lateinit<Int>.uninitialized == .uninitialized)
    }
}
