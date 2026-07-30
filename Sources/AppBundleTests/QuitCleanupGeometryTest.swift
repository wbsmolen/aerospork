@testable import AppBundle
import XCTest

/// Where the quit cleanup puts a window back.
///
/// `makeAllWindowsVisibleAndRestoreSize` centres every window on its own monitor before quitting, so
/// nothing is left parked off screen where a hidden workspace put it. It resolved the right monitor
/// and then used only that monitor's width and height, never its origin -- and both `visibleRect`
/// and `kAXPositionAttribute` are in the GLOBAL coordinate space. So every window landed near the
/// origin of that space, which is the main monitor.
///
/// On a single display the two are the same point, which is why nobody saw it. With a second monitor
/// it collapsed every display onto one at quit, and because the next launch binds a window by where
/// it physically sits, everything came back on the main monitor's startup workspace. A window left
/// on workspace `A` reappeared on `1` or `3`.
final class QuitCleanupGeometryTest: XCTestCase {
    /// The regression. A monitor to the right of the main one has a non-zero origin, and a window
    /// centred on it must stay within it.
    func testAWindowIsCentredOnItsOwnMonitorNotTheMainOne() {
        let secondMonitor = Rect(topLeftX: 1920, topLeftY: 0, width: 2560, height: 1440)
        let size = CGSize(width: 800, height: 600)

        let point = centredOnMonitor(secondMonitor, size)

        XCTAssertEqual(point.x, 1920 + (2560 - 800) / 2)
        XCTAssertEqual(point.y, (1440 - 600) / 2)
        XCTAssertTrue(
            point.x >= secondMonitor.topLeftX,
            "window placed at x=\(point.x), left of its own monitor at x=\(secondMonitor.topLeftX) -- "
                + "it will be bound to the wrong monitor on the next launch",
        )
    }

    /// A monitor above and to the left of the main one: both offsets negative, so an implementation
    /// that merely adds an absolute value would pass the test above and fail this.
    func testNegativeMonitorOriginsAreHonoured() {
        let monitor = Rect(topLeftX: -1920, topLeftY: -1080, width: 1920, height: 1080)
        let size = CGSize(width: 400, height: 300)

        let point = centredOnMonitor(monitor, size)

        XCTAssertEqual(point.x, -1920 + (1920 - 400) / 2)
        XCTAssertEqual(point.y, -1080 + (1080 - 300) / 2)
    }

    /// The main monitor sits at the origin, so this is the case the old code got right -- and the
    /// reason it survived. Pinned so a "fix" cannot regress it.
    func testTheMainMonitorIsUnaffected() {
        let main = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
        let size = CGSize(width: 1000, height: 700)

        assertEquals(centredOnMonitor(main, size), CGPoint(x: (1920 - 1000) / 2, y: (1080 - 700) / 2))
    }

    /// A window larger than the monitor centres to a negative offset rather than being clamped;
    /// that is existing behaviour and the origin fix must not silently change it.
    func testAnOversizedWindowStillCentres() {
        let monitor = Rect(topLeftX: 1920, topLeftY: 0, width: 1000, height: 800)
        let point = centredOnMonitor(monitor, CGSize(width: 1400, height: 900))

        assertEquals(point, CGPoint(x: 1920 + (1000 - 1400) / 2, y: (800 - 900) / 2))
    }
}
