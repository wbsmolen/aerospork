@testable import AppBundle
import AppKit
import XCTest

/// Pins the pixel arithmetic of `Sources/AppBundle/layout/layoutRecursive.swift`.
///
/// Everything here runs headlessly against the 1920x1080 `testMonitor` (see `Monitor.swift`) and
/// `LayoutTestWindow`, which records the frames layout asks for instead of writing them to the
/// Accessibility API.
@MainActor
final class LayoutRecursiveTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.gaps = .zero
        config.accordionPadding = 30
    }

    override func tearDown() {
        testMonitors = [defaultTestMonitor]
        super.tearDown()
    }

    /// A monitor anchored at the origin, so `mainMonitor` and `monitorApproximation` both pick it.
    private func monitor(width: CGFloat) -> MonitorImpl {
        let rect = Rect(topLeftX: 0, topLeftY: 0, width: width, height: 1080)
        return MonitorImpl(monitorAppKitNsScreenScreensId: 1, name: "Test Monitor", rect: rect, visibleRect: rect)
    }

    // MARK: - tiles

    /// Interior gaps must be exactly `inner`, and the container's outer edges must get no gap at
    /// all -- which is why the first and last child each give back half a gap.
    func testTilesHalfGapEdges() async throws {
        config.gaps = Gaps(inner: .init(vertical: 0, horizontal: 10), outer: .zero)
        let workspace = focus.workspace
        let windows = (0 ..< 3).map { LayoutTestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer) }

        try await workspace.layoutWorkspace()

        // 1920 / 3 = 640 per child before gaps.
        assertEquals(windows[0].singleAppliedFrame(), CGRect(x: 0, y: 0, width: 635, height: 1080))
        assertEquals(windows[1].singleAppliedFrame(), CGRect(x: 645, y: 0, width: 630, height: 1080))
        assertEquals(windows[2].singleAppliedFrame(), CGRect(x: 1285, y: 0, width: 635, height: 1080))
        // The invariants the numbers above encode:
        assertEquals(windows[0].singleAppliedFrame().minX, 0) // flush with the workspace
        assertEquals(windows[2].singleAppliedFrame().maxX, 1920) // flush with the workspace
        assertEquals(windows[1].singleAppliedFrame().minX - windows[0].singleAppliedFrame().maxX, 10)
        assertEquals(windows[2].singleAppliedFrame().minX - windows[1].singleAppliedFrame().maxX, 10)
    }

    /// Outer gaps come off the monitor rect, and nothing else does. `layoutWorkspace` used to pass
    /// `rect.height - 1`, leaving a 1px dead row at the bottom of every workspace; measurement showed
    /// macOS grants the exact fill on every monitor, so the row was pure loss. This pins the last row
    /// as usable -- if someone reinstates the workaround, the height here goes back to 1063.
    func testWorkspaceFillsVisibleRectExactly() async throws {
        config.gaps = Gaps(inner: .zero, outer: .init(left: 8, bottom: 12, top: 4, right: 16))
        let workspace = focus.workspace
        let window = LayoutTestWindow.new(id: 0, parent: workspace.rootTilingContainer)

        try await workspace.layoutWorkspace()

        // 1920 - 8 - 16 = 1896 wide, 1080 - 4 - 12 = 1064 tall.
        assertEquals(window.singleAppliedFrame(), CGRect(x: 8, y: 4, width: 1896, height: 1064))
    }

    /// Layout rescales the children onto the container and writes the result back as weights, so
    /// weights stay denominated in points -- `resize`, mouse-resize and balance-sizes all rely on
    /// that. The rescale is proportional, so the ratio the user set is what survives. See the
    /// `TRADEOFF:` note in `layoutTiles`.
    func testWeightsAreNormalizedToPoints() async throws {
        let workspace = focus.workspace
        let wide = LayoutTestWindow.new(id: 0, parent: workspace.rootTilingContainer, adaptiveWeight: 300)
        let narrow = LayoutTestWindow.new(id: 1, parent: workspace.rootTilingContainer, adaptiveWeight: 100)

        try await workspace.layoutWorkspace()

        // 300:100 is 3:1, and 3:1 of 1920 is 1440:480.
        assertEquals(wide.singleAppliedFrame(), CGRect(x: 0, y: 0, width: 1440, height: 1080))
        assertEquals(narrow.singleAppliedFrame(), CGRect(x: 1440, y: 0, width: 480, height: 1080))
        assertEquals(wide.hWeight, 1440)
        assertEquals(narrow.hWeight, 480)
    }

    /// The degenerate input the proportional rescale has to survive: `resize` can drive every weight
    /// in a container to zero, and there is no ratio left to scale. Fall back to an even split
    /// rather than dividing by zero.
    func testZeroWeightsFallBackToAnEvenSplit() async throws {
        let workspace = focus.workspace
        let windows = (0 ..< 3).map { LayoutTestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer, adaptiveWeight: 0) }

        try await workspace.layoutWorkspace()

        for window in windows {
            assertEquals(window.singleAppliedFrame().width, 640)
        }
    }

    /// Replaying an existing tree onto a much narrower monitor must scale the children, not subtract
    /// a constant from each. The additive spread took `(1280 - 3840) / 2 = -1280` off *both* windows,
    /// which drove the small one to a negative weight -- `Rect` clamps that to zero, so the window
    /// silently vanished. Nothing may ever come out of layout at zero width.
    func testNarrowerMonitorScalesInsteadOfCollapsingSmallWindows() async throws {
        testMonitors = [monitor(width: 3840)]
        let workspace = focus.workspace
        // Sums to 3840, so the first pass is a no-op and the second pass is purely the rescale.
        let big = LayoutTestWindow.new(id: 0, parent: workspace.rootTilingContainer, adaptiveWeight: 3000)
        let small = LayoutTestWindow.new(id: 1, parent: workspace.rootTilingContainer, adaptiveWeight: 840)

        try await workspace.layoutWorkspace()
        assertEquals(big.singleAppliedFrame().width, 3000)
        assertEquals(small.singleAppliedFrame().width, 840)

        big.resetRecording()
        small.resetRecording()
        testMonitors = [monitor(width: 1280)]
        try await workspace.layoutWorkspace()

        for window in [big, small] {
            let width = window.appliedSizes.last?.width ?? .nan
            assertEquals(width > 0, true, additionalMsg: "\(window) got width \(width) (weight \(window.hWeight))")
        }
        // A third as wide, so every child is a third as wide -- the 25:7 ratio is preserved.
        assertEquals(big.singleAppliedFrame().width, 1000)
        assertEquals(small.singleAppliedFrame().width, 280)
    }

    /// The sibling of the monitor-replay bug, reached through `resize` instead. `resize` hands a
    /// node's delta back by subtracting it from the siblings, so `resize width -2000` on a two-window
    /// split leaves the shrunk node with a negative weight. The proportional rescale preserves sign,
    /// so without a floor layout hands the AX API a negative CGSize and the window vanishes -- and
    /// `appliedFrames` cannot see it, because `CGRect` standardizes on read. Assert `appliedSizes`.
    func testNegativeWeightNeverReachesTheAxApi() async throws {
        let workspace = focus.workspace
        let shrunk = LayoutTestWindow.new(id: 0, parent: workspace.rootTilingContainer)
        let other = LayoutTestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        // Verbatim what ResizeCommand does for `resize width -2000` across two children.
        shrunk.setWeight(.h, shrunk.hWeight - 2000)
        other.setWeight(.h, other.hWeight + 2000)

        try await workspace.layoutWorkspace()

        for window in [shrunk, other] {
            let width = window.appliedSizes.last?.width ?? .nan
            assertEquals(width > 0, true, additionalMsg: "\(window) got width \(width) (weight \(window.hWeight))")
        }
    }

    /// The weight write-back converges in one pass, so laying out an unchanged tree twice lands on
    /// the same frames -- but only to within floating-point noise: `delta` is spread as
    /// `(size - sum) / count`, and `count * delta` doesn't re-sum to `size - sum` exactly, so the
    /// second pass wobbles by ~1 ULP. Anything bigger than a millipixel is real drift.
    func testLayoutIsIdempotent() async throws {
        config.gaps = Gaps(inner: .init(vertical: 7, horizontal: 13), outer: .init(left: 5, bottom: 5, top: 5, right: 5))
        let workspace = focus.workspace
        let windows = (0 ..< 3).map { LayoutTestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer, adaptiveWeight: CGFloat(100 * ($0 + 1))) }

        try await workspace.layoutWorkspace()
        try await workspace.layoutWorkspace()

        for window in windows {
            assertEquals(window.appliedFrames.count, 2)
            let (first, second) = (window.appliedFrames[0], window.appliedFrames[1])
            let drift = max(
                abs(first.minX - second.minX), abs(first.minY - second.minY),
                abs(first.width - second.width), abs(first.height - second.height),
            )
            assertEquals(drift < 0.001, true, additionalMsg: "\(window) drifted \(drift)pt: \(first) -> \(second)")
        }
    }

    /// Nested containers must fill their parent's slot exactly.
    func testNestedContainerFillsItsSlot() async throws {
        let workspace = focus.workspace
        let outer = LayoutTestWindow.new(id: 0, parent: workspace.rootTilingContainer)
        let column = TilingContainer.newVTiles(parent: workspace.rootTilingContainer, adaptiveWeight: 1)
        let top = LayoutTestWindow.new(id: 1, parent: column)
        let bottom = LayoutTestWindow.new(id: 2, parent: column)

        try await workspace.layoutWorkspace()

        assertEquals(outer.singleAppliedFrame(), CGRect(x: 0, y: 0, width: 960, height: 1080))
        assertEquals(top.singleAppliedFrame(), CGRect(x: 960, y: 0, width: 960, height: 540))
        assertEquals(bottom.singleAppliedFrame(), CGRect(x: 960, y: 540, width: 960, height: 540))
    }

    // MARK: - fullscreen

    /// Regression: fullscreen used to be applied only while the window was the workspace's
    /// `mostRecentWindowRecursive`, and the flag was cleared otherwise -- so focusing any other
    /// window silently un-fullscreened it.
    func testFullscreenSurvivesFocusingAnotherWindow() async throws {
        config.gaps = Gaps(inner: .zero, outer: .init(left: 8, bottom: 8, top: 8, right: 8))
        let workspace = focus.workspace
        let fullscreened = LayoutTestWindow.new(id: 0, parent: workspace.rootTilingContainer)
        let other = LayoutTestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        fullscreened.isFullscreen = true
        other.markAsMostRecentChild() // "focus the other window"

        try await workspace.layoutWorkspace()

        assertTrue(fullscreened.isFullscreen)
        // Both get visibleRect padded by outer gaps; the tiled one is just h-split with its sibling.
        assertEquals(fullscreened.singleAppliedFrame(), CGRect(x: 8, y: 8, width: 1904, height: 1064))
        assertEquals(other.singleAppliedFrame(), CGRect(x: 960, y: 8, width: 952, height: 1064))
    }

    func testFullscreenNoOuterGaps() async throws {
        config.gaps = Gaps(inner: .zero, outer: .init(left: 8, bottom: 8, top: 8, right: 8))
        let workspace = focus.workspace
        let window = LayoutTestWindow.new(id: 0, parent: workspace.rootTilingContainer)
        window.isFullscreen = true
        window.noOuterGapsInFullscreen = true

        try await workspace.layoutWorkspace()

        assertEquals(window.singleAppliedFrame(), CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    /// Regression: `layoutFloatingWindow` used to clear `isFullscreen` right after applying the
    /// frame, so a floating fullscreen window un-fullscreened itself on the next refresh.
    func testFloatingFullscreenSurvivesRefresh() async throws {
        let workspace = focus.workspace
        let window = LayoutTestWindow.new(
            id: 0,
            parent: workspace,
            adaptiveWeight: WEIGHT_AUTO,
            axRect: Rect(topLeftX: 100, topLeftY: 100, width: 200, height: 200),
        )
        window.isFullscreen = true

        try await workspace.layoutWorkspace()
        try await workspace.layoutWorkspace()

        assertTrue(window.isFullscreen)
        assertEquals(window.appliedFrames, [
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
            CGRect(x: 0, y: 0, width: 1920, height: 1080),
        ])
    }

    // MARK: - accordion

    /// Regression: `case children.indices.last` used to precede `case mruIndex + 1`, so a MRU
    /// neighbour that was also the last child got the last child's padding -- its far edge landed
    /// on the MRU child's edge instead of `padding` inside it.
    func testAccordionMruNeighbourPaddingBeatsLastChildPadding() async throws {
        let workspace = focus.workspace
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .accordion, index: INDEX_BIND_LAST)
        let windows = (0 ..< 3).map { LayoutTestWindow.new(id: UInt32($0), parent: accordion) }
        windows[1].markAsMostRecentChild()

        try await workspace.layoutWorkspace()

        // padding = 30. The MRU child sits at [30, 1890]; each neighbour peeks 30pt past one of its
        // edges and stops 30pt short of the other.
        assertEquals(windows[0].singleAppliedFrame(), CGRect(x: 0, y: 0, width: 1860, height: 1080))
        assertEquals(windows[1].singleAppliedFrame(), CGRect(x: 30, y: 0, width: 1860, height: 1080))
        assertEquals(windows[2].singleAppliedFrame(), CGRect(x: 60, y: 0, width: 1860, height: 1080))
    }

    func testAccordionSingleChildGetsNoPadding() async throws {
        let workspace = focus.workspace
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .accordion, index: INDEX_BIND_LAST)
        let window = LayoutTestWindow.new(id: 0, parent: accordion)

        try await workspace.layoutWorkspace()

        assertEquals(window.singleAppliedFrame(), CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    /// Deliberate behaviour, not an oversight: accordion children overlap by construction, so there
    /// is no space between siblings for an inner gap to occupy. Only `accordion-padding` separates
    /// them. If you ever make accordion honour inner gaps, this test is the one to delete.
    func testAccordionIgnoresInnerGaps() async throws {
        let workspace = focus.workspace
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .accordion, index: INDEX_BIND_LAST)
        let windows = (0 ..< 3).map { LayoutTestWindow.new(id: UInt32($0), parent: accordion) }
        windows[1].markAsMostRecentChild()

        try await workspace.layoutWorkspace()
        let withoutGaps = windows.map { $0.singleAppliedFrame() }

        windows.forEach { $0.resetRecording() }
        config.gaps = Gaps(inner: .init(vertical: 40, horizontal: 40), outer: .zero)
        try await workspace.layoutWorkspace()

        assertEquals(windows.map { $0.singleAppliedFrame() }, withoutGaps)
    }

    func testAccordionVerticalPadsTopAndBottom() async throws {
        let workspace = focus.workspace
        let accordion = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .v, .accordion, index: INDEX_BIND_LAST)
        let windows = (0 ..< 3).map { LayoutTestWindow.new(id: UInt32($0), parent: accordion) }
        windows[1].markAsMostRecentChild()

        try await workspace.layoutWorkspace()

        assertEquals(windows[0].singleAppliedFrame(), CGRect(x: 0, y: 0, width: 1920, height: 1020))
        assertEquals(windows[1].singleAppliedFrame(), CGRect(x: 0, y: 30, width: 1920, height: 1020))
        assertEquals(windows[2].singleAppliedFrame(), CGRect(x: 0, y: 60, width: 1920, height: 1020))
    }

    // MARK: - monitors

    /// A workspace on a second monitor is laid out on that monitor throughout the pass: tiles, the fullscreen
    /// window, and a floating window that was on the other monitor. The pass resolves the monitor once.
    func testAWorkspaceOnTheSecondMonitorIsLaidOutOnIt() async throws {
        let right = Rect(topLeftX: 1920, topLeftY: 0, width: 1000, height: 800)
        testMonitors = [monitor(width: 1920), MonitorImpl(monitorAppKitNsScreenScreensId: 2, name: "Right", rect: right, visibleRect: right)]
        let workspace = Workspace.get(byName: "on-right")
        assertTrue(testMonitors[1].setActiveWorkspace(workspace))
        let tiles = (0 ..< 2).map { LayoutTestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer) }
        let fullscreen = LayoutTestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        fullscreen.isFullscreen = true
        let floating = LayoutTestWindow.new(id: 3, parent: workspace, adaptiveWeight: WEIGHT_AUTO, axRect: Rect(topLeftX: 960, topLeftY: 540, width: 100, height: 100))

        try await workspace.layoutWorkspace()

        assertEquals(tiles[0].singleAppliedFrame(), CGRect(x: 1920, y: 0, width: 333.3333333333333, height: 800))
        assertEquals(fullscreen.singleAppliedFrame(), CGRect(x: 1920, y: 0, width: 1000, height: 800))
        // Halfway across the left monitor, so halfway across the right one.
        assertEquals(floating.singleAppliedFrame().origin, CGPoint(x: 2420, y: 400))
    }
}
