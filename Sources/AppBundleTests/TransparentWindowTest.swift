@testable import AppBundle
import XCTest

@MainActor
final class TransparentWindowTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// The phantom gap: a window WindowServer draws at alpha 0 was tiled like any other.
    func testTransparentWindowLeavesTheTilingAndComesBackWhenDrawn() async throws {
        let workspace = Workspace.get(byName: "ws")
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let phantom = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 3, parent: workspace.rootTilingContainer)

        phantom.transparent = true
        try await normalizeLayoutReason()
        XCTAssertTrue(phantom.parent === workspace.macOsNativeHiddenAppsWindowsContainer)
        assertEquals(workspace.rootTilingContainer.children.count, 2)

        phantom.transparent = false
        try await normalizeLayoutReason()
        XCTAssertTrue(phantom.parent === workspace.rootTilingContainer)
        assertEquals(phantom.nodeWorkspace?.name, workspace.name)
    }

    func testAWindowOnlyCountsAsTransparentAfterASecond() {
        defer { _ = updateTransparentWindowIds(zeroAlpha: [], now: Date()) }
        let t0 = Date()
        assertTrue(updateTransparentWindowIds(zeroAlpha: [7], now: t0)) // newly seen: caller schedules a re-check
        assertEquals(transparentWindowIds, [])
        assertFalse(updateTransparentWindowIds(zeroAlpha: [7], now: t0 + 0.5)) // fading in, maybe
        assertEquals(transparentWindowIds, [])
        assertFalse(updateTransparentWindowIds(zeroAlpha: [7], now: t0 + 1))
        assertEquals(transparentWindowIds, [7])
        _ = updateTransparentWindowIds(zeroAlpha: [], now: t0 + 2) // drawn again
        assertEquals(transparentWindowIds, [])
        assertTrue(updateTransparentWindowIds(zeroAlpha: [7], now: t0 + 3)) // and the grace starts over
        assertEquals(transparentWindowIds, [])
    }
}
