@testable import AppBundle
import Common
import XCTest

/// The world snapshot taken when a window dies, which is what restores windows after the screen
/// unlocks (locking makes every AX attribute go empty, so AeroSpork sees every window "close").
@MainActor
final class ClosedWindowsCacheTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// The happy path: a window sitting in a workspace is captured, so it can be restored.
    func testAWindowInAWorkspaceIsCaptured() {
        let window = TestWindow.new(id: 4242, parent: Workspace.get(byName: "cache-test").rootTilingContainer)
        cacheClosedWindowIfNeeded(window: window)
        XCTAssertTrue(restoreWouldFind(4242))
    }

    /// An unbound window cannot be captured -- the snapshot is built by walking `Workspace.all`.
    func testAnUnboundWindowIsNotCaptured() {
        let window = TestWindow.new(id: 4343, parent: Workspace.get(byName: "cache-test-2").rootTilingContainer)
        window.unbindFromParent()
        cacheClosedWindowIfNeeded(window: window)
        XCTAssertFalse(restoreWouldFind(4343))
    }

    /// The counterexample that broke a fatal `check(!window.isBound || captured)` in production.
    ///
    /// `isBound` is only `parent != nil`. Detach the window's *container* and the window is still
    /// "bound" while its chain no longer reaches a workspace -- so it is not captured, and asserting
    /// otherwise killed the app on an ordinary window close. Capturing must stay best-effort.
    func testAWindowBoundToADetachedContainerIsStillBoundButNotCaptured() {
        let workspace = Workspace.get(byName: "cache-test-3")
        let container = TilingContainer(parent: workspace.rootTilingContainer, adaptiveWeight: 1, .h, .tiles, index: INDEX_BIND_LAST)
        let window = TestWindow.new(id: 4444, parent: container)
        container.unbindFromParent() // the container leaves the tree; the window still points at it

        XCTAssertTrue(window.isBound, "precondition: parent != nil")
        XCTAssertNil(window.nodeWorkspace, "precondition: the chain no longer reaches a workspace")

        cacheClosedWindowIfNeeded(window: window) // must not crash
        XCTAssertFalse(restoreWouldFind(4444))
    }

    /// A snapshot leaves the tree as it found it: it used to create an empty fullscreen and an empty
    /// hidden-apps container in every workspace it walked.
    func testTakingASnapshotCreatesNoContainer() {
        let workspace = Workspace.get(byName: "cache-test-4")
        let window = TestWindow.new(id: 4545, parent: workspace.rootTilingContainer)
        let before = workspace.children.count
        cacheClosedWindowIfNeeded(window: window)
        assertEquals(workspace.children.count, before)
    }

    /// A window macOS holds in an existing hidden-apps or fullscreen container is still captured.
    func testWindowsInExistingUnconventionalContainersAreCaptured() {
        let workspace = Workspace.get(byName: "cache-test-5")
        TestWindow.new(id: 4646, parent: workspace.macOsNativeHiddenAppsWindowsContainer)
        TestWindow.new(id: 4747, parent: workspace.macOsNativeFullscreenWindowsContainer)
        assertEquals(FrozenWorkspace(workspace).macosUnconventionalWindows.map(\.id), [4646, 4747])
    }

    /// Asks the cache the same question `restoreClosedWindowsCacheIfNeeded` asks, without needing a
    /// real AX window to restore onto.
    private func restoreWouldFind(_ id: UInt32) -> Bool {
        let probe = TestWindow.new(id: id, parent: Workspace.get(byName: "probe-target").rootTilingContainer)
        defer { probe.unbindFromParent() }
        return (try? awaitRestore(probe)) ?? false
    }

    private func awaitRestore(_ window: Window) throws -> Bool {
        var result = false
        let done = expectation(description: "restore")
        Task { @MainActor in
            result = (try? await restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window)) ?? false
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        return result
    }
}
