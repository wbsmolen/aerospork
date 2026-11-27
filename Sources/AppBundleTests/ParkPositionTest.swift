@testable import AppBundle
import XCTest

/// Parking a window of a workspace that left the screen. `layoutWorkspaces` parks only `MacWindow`s, which need a
/// real app, so the decisions are pure functions and the wiring is pinned in the source.
final class ParkPositionTest: XCTestCase {
    override func setUp() { testMonitors = [defaultTestMonitor] } // no `setUpWorkspacesForTests` here

    /// A tiled window is parked from where layout last put it, not from a frame read over AX. The two must give
    /// the same answer whenever they are the same rect.
    func testTheLastAppliedRectGivesTheSamePositionAsTheFrameRead() {
        let readOverAx = Rect(topLeftX: 480, topLeftY: 270, width: 960, height: 540)
        let lastApplied = Rect(topLeftX: 480, topLeftY: 270, width: 960, height: 540)
        assertEquals(proportionalPosition(of: lastApplied), proportionalPosition(of: readOverAx))
        assertEquals(proportionalPosition(of: readOverAx), CGPoint(x: 0.25, y: 0.25)) // on the 1920x1080 test monitor
    }

    /// On a second monitor, the share is of that monitor, as `unparkedTopLeftCorner` reads it back.
    func testThePositionIsAShareOfTheMonitorTheRectIsOn() {
        let right = MonitorImpl(monitorAppKitNsScreenScreensId: 2, name: "right", rect: Rect(topLeftX: 1920, topLeftY: 0, width: 1000, height: 1000), visibleRect: Rect(topLeftX: 1920, topLeftY: 0, width: 1000, height: 1000))
        testMonitors = [defaultTestMonitor, right]
        assertEquals(proportionalPosition(of: Rect(topLeftX: 2420, topLeftY: 100, width: 200, height: 200)), CGPoint(x: 0.5, y: 0.1))
    }

    func testOnlyATiledPlacedWindowOfAnAnsweringAppSkipsTheRead() {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: 10, height: 10)
        assertFalse(parkNeedsFrameRead(parentIsTiling: true, lastApplied: rect, appTimedOut: false))
        assertTrue(parkNeedsFrameRead(parentIsTiling: false, lastApplied: rect, appTimedOut: false)) // floating
        assertTrue(parkNeedsFrameRead(parentIsTiling: true, lastApplied: nil, appTimedOut: false)) // never laid out, or dragged
        // A timed-out app goes through the read, which answers nil at once, so the window is left alone and no
        // job waits out the timeout on that app's thread.
        assertTrue(parkNeedsFrameRead(parentIsTiling: true, lastApplied: rect, appTimedOut: true))
    }

    func testThePreLayoutParksOnlyWindowsNotParkedYet() {
        assertTrue(shouldPark(inNativeFullscreen: false, isBackgroundTab: false, isParked: false, onlyUnparked: true))
        assertFalse(shouldPark(inNativeFullscreen: false, isBackgroundTab: false, isParked: true, onlyUnparked: true))
        // The full layout re-checks every parked window.
        assertTrue(shouldPark(inNativeFullscreen: false, isBackgroundTab: false, isParked: true, onlyUnparked: false))
        assertFalse(shouldPark(inNativeFullscreen: true, isBackgroundTab: false, isParked: false, onlyUnparked: false))
        assertFalse(shouldPark(inNativeFullscreen: false, isBackgroundTab: true, isParked: false, onlyUnparked: false))
    }

    func testHideInCornerAsksThePredicateBeforeReadingTheFrame() throws {
        let body = try sourceBody("func hideInCorner(", in: "Sources/AppBundle/tree/MacWindow.swift")
        let predicate = try XCTUnwrap(body.range(of: "parkNeedsFrameRead("))
        let read = try XCTUnwrap(body.range(of: "getAxRect()"))
        XCTAssertLessThan(predicate.lowerBound, read.lowerBound)
        XCTAssertTrue(body.contains("MacApp.timedOutThisPass.contains(macApp.pid)"), "a timed-out app's window would be parked without asking")
    }

    /// The trace for apps that move a parked window without telling: only a re-check of the same spot that
    /// finds the window elsewhere, with no notification since, counts.
    func testAParkedWindowMovedWithoutANotificationIsOnlyThatCase() {
        let spot = CGPoint(x: -799, y: 900)
        let away = CGPoint(x: 100, y: 100)
        assertTrue(parkedWindowMovedWithoutNotification(parkedAt: spot, spot: spot, actual: away, notified: false))
        assertFalse(parkedWindowMovedWithoutNotification(parkedAt: spot, spot: spot, actual: away, notified: true))
        assertFalse(parkedWindowMovedWithoutNotification(parkedAt: spot, spot: spot, actual: spot, notified: false)) // still there
        assertFalse(parkedWindowMovedWithoutNotification(parkedAt: nil, spot: spot, actual: away, notified: false)) // first park
        assertFalse(parkedWindowMovedWithoutNotification(parkedAt: away, spot: spot, actual: away, notified: false)) // new spot
        assertFalse(parkedWindowMovedWithoutNotification(parkedAt: spot, spot: spot, actual: nil, notified: false)) // unreadable
    }
}
