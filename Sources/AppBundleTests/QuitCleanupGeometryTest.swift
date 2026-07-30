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

    /// Even the main monitor is offset, so the old code was wrong on a single display too.
    ///
    /// What gets passed is `visibleRect`, not `rect`, and the menu bar always insets it: measured on
    /// a 5120x1440 main display, `visibleRect.topLeftY` is 30, never 0. A Dock on the left insets
    /// `topLeftX` as well. The old arithmetic therefore put a full-height window's title bar
    /// *underneath* the menu bar.
    ///
    /// A fixture with origin (0,0) would be fiction, and would make this test agree with the old
    /// code -- which is exactly the wrong thing for it to do.
    func testEvenTheMainMonitorIsInsetByTheMenuBar() {
        let menuBarHeight: CGFloat = 30
        let mainVisible = Rect(topLeftX: 0, topLeftY: menuBarHeight, width: 5120, height: 1440 - menuBarHeight)
        let fullHeight = CGSize(width: mainVisible.width, height: mainVisible.height)

        // A window sized to the visible area lands exactly on it: both offsets are zero, so the
        // result is the corner itself.
        assertEquals(centredOnMonitor(mainVisible, fullHeight), CGPoint(x: 0, y: menuBarHeight))
        XCTAssertGreaterThanOrEqual(
            centredOnMonitor(mainVisible, fullHeight).y, menuBarHeight,
            "a window placed above the menu bar has its title bar covered and cannot be dragged",
        )
    }

    /// A window larger than the monitor centres to a negative offset rather than being clamped;
    /// that is existing behaviour and the origin fix must not silently change it.
    func testAnOversizedWindowStillCentres() {
        let monitor = Rect(topLeftX: 1920, topLeftY: 0, width: 1000, height: 800)
        let point = centredOnMonitor(monitor, CGSize(width: 1400, height: 900))

        assertEquals(point, CGPoint(x: 1920 + (1000 - 1400) / 2, y: (800 - 900) / 2))
    }
}
