@testable import AppBundle
import XCTest

/// `hideSpot` against a real arrangement: an ultrawide on top, two 4Ks side by side under it. Both
/// bottom corners of the ultrawide touch a 4K, which is how hidden windows ended up in plain view on
/// another workspace's screen.
final class HideSpotTest: XCTestCase {
    private let ultrawide = Rect(topLeftX: 0, topLeftY: 0, width: 5120, height: 1440)
    private let ultrawideVisible = Rect(topLeftX: 0, topLeftY: 25, width: 5120, height: 1415)
    private let leftFourK = Rect(topLeftX: -1302, topLeftY: 1440, width: 3840, height: 2160)
    private let rightFourK = Rect(topLeftX: 2538, topLeftY: 1440, width: 3840, height: 2160)
    private let window = CGSize(width: 853, height: 1409)

    private func reach(_ p: CGPoint, _ size: CGSize, _ m: Rect) -> Bool {
        p.x < m.maxX && p.x + size.width > m.minX && p.y < m.maxY && p.y + size.height > m.minY
    }

    func testUltrawideAboveTwoMonitorsParksOffTheRightEdgeNotOnAMonitorBelow() {
        let p = hideSpot(for: window, on: ultrawideVisible, otherMonitors: [leftFourK, rightFourK], sliver: 1)
        assertEquals(p, CGPoint(x: 5119, y: 25))
        assertFalse(reach(p, window, leftFourK))
        assertFalse(reach(p, window, rightFourK))
    }

    func testLoneMonitorKeepsTheBottomRightCorner() {
        assertEquals(hideSpot(for: window, on: ultrawideVisible, otherMonitors: [], sliver: 1), CGPoint(x: 5119, y: 1439))
    }

    func testMonitorWithANeighbourOnItsRightUsesBottomLeft() {
        let p = hideSpot(for: window, on: leftFourK, otherMonitors: [ultrawide, rightFourK], sliver: 1)
        assertEquals(p, CGPoint(x: -1302 + 1 - 853, y: 3599))
    }

    func testBoxedInMonitorPicksTheSpotThatShowsLeast() {
        // Monitors on every side: nothing is free, so take the least overlap rather than the first spot.
        let middle = Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 1000)
        let others = [
            Rect(topLeftX: 1000, topLeftY: 0, width: 1000, height: 2000), // right, reaching below
            Rect(topLeftX: -1000, topLeftY: 0, width: 1000, height: 1000), // left
            Rect(topLeftX: -1000, topLeftY: 1000, width: 2000, height: 1000), // below-left and below
        ]
        let small = CGSize(width: 100, height: 100)
        assertEquals(hideSpot(for: small, on: middle, otherMonitors: others, sliver: 1), CGPoint(x: 999, y: 0))
    }

    /// A neighbour beside the corner that stops just short of the bottom: the parked window is lifted
    /// into it, so the corner is not free even though nothing is directly below.
    func testANeighbourBesideTheCornerCountsBecauseMacosLiftsTheWindow() {
        let monitor = Rect(topLeftX: 0, topLeftY: 0, width: 1000, height: 1000)
        let tallerOnTheRight = Rect(topLeftX: 1000, topLeftY: -500, width: 1000, height: 1490) // ends 10 pt above
        let small = CGSize(width: 100, height: 100)
        assertEquals(hideSpot(for: small, on: monitor, otherMonitors: [tallerOnTheRight], sliver: 1), CGPoint(x: -99, y: 999))
    }
}
