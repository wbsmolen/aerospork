@testable import AppBundle
import AppKit
import Common
import XCTest

/// Paths that used to call `die`/`check`/`getOrDie` on conditions a *user* can reach.
///
/// The precedent is `cacheClosedWindowIfNeeded`: a best-effort cache diagnostic was written as a
/// fatal `check`, and closing a window took the whole window manager down. Each case below is the
/// same shape -- an invariant the code itself no longer maintains, or a state the OS/user is
/// entitled to produce -- and each test crashes the whole bundle (not just fails) if the fix is
/// reverted, because `die` is `fatalError`.
@MainActor
final class DegradeInsteadOfDieTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws {
        config.execOnWorkspaceChange = []
        _prevFocusedWorkspaceName = nil
        testMonitors = [defaultTestMonitor]
        try await super.tearDown()
    }

    /// `Workspace ==` asserted that `get(byName:)` interning is never broken, while
    /// `garbageCollectUnusedWorkspaces` breaks it on purpose -- it drops empty invisible workspaces
    /// from the registry, so anything still holding one (a local in an `async` function that
    /// released the main actor across an `await`) then meets a freshly created namesake.
    func testComparingAStaleWorkspaceToItsLiveNamesakeDoesNotDie() {
        let stale = Workspace.get(byName: "collected")
        Workspace.garbageCollectUnusedWorkspaces()
        let fresh = Workspace.get(byName: "collected")
        XCTAssertFalse(stale === fresh, "the GC did not actually collect it; the test proves nothing")

        // Evaluating this line at all is the assertion. The answer (identity: not equal) is
        // unchanged; what changed is that reaching it no longer calls `die`.
        XCTAssertFalse(stale == fresh)
    }

    /// `/tmp` is world-writable and sticky, so another account can create our socket path first, and
    /// then we can neither remove it nor bind it. That used to be `die`: any local account could stop
    /// the window manager from starting. A non-empty directory fails `unlink` and `bind` the same way.
    func testACliSocketPathWeCannotBindDoesNotTakeTheAppDown() async throws {
        let squatted = "/tmp/aerospork-test-\(getpid())-\(UInt32.random(in: 0 ... .max))"
        try FileManager.default.createDirectory(atPath: squatted + "/occupied", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: squatted) }

        startUnixSocketServer(socketFile: squatted)
        try await Task.sleep(for: .milliseconds(300))
        // Reaching this line is the assertion.
    }

    /// The app mirror image, decided the other way: `MacApp` equality is identity, because each one
    /// owns its own thread and AX connection. pid reuse (which `MacApp.failedPids` already tracks
    /// `launchDate` for) means two live objects can share a pid, and asserting they cannot was fatal.
    func testTwoAppsSharingAPidAreNotTheSameApp() {
        let a = PidOnlyApp(pid: 42)
        let b = PidOnlyApp(pid: 42)
        XCTAssertFalse(a == b)
        XCTAssertTrue(a == a)
    }

    /// `exec-on-workspace-change` is a user-supplied path. A typo, a missing executable bit, or a
    /// binary removed by a package upgrade all make `Process.run()` throw -- and that used to be
    /// `.getOrDie()`, i.e. the window manager died on every workspace switch until the config was
    /// fixed.
    func testABadExecOnWorkspaceChangePathDoesNotTakeTheAppDown() {
        config.execOnWorkspaceChange = ["/nonexistent/aerospork-test-binary", "arg"]
        checkOnFocusChangedCallbacks() // settle: records the current focus as last known

        check(Workspace.get(byName: "exec-target").focusWorkspace())
        checkOnFocusChangedCallbacks() // fires onWorkspaceChanged -> Process.run() throws

        // Reaching this line is the assertion.
        assertEquals(focus.workspace.name, "exec-target")
    }

    /// `swapWindows` guarded `window1.ownIndex` twice instead of once each, so window2 was never
    /// checked at all and an unbound operand reached `unbindFromParent()`, which is fatal. Its only
    /// caller picks the swap target out of `lastAppliedLayoutPhysicalRect`, written by the previous
    /// layout pass -- so the target can have been garbage collected before the mouse-up reads it.
    func testSwappingWithAnUnboundWindowIsDeclinedNotFatal() {
        let root = Workspace.get(byName: "swap").rootTilingContainer
        let a = TestWindow.new(id: 9001, parent: root)
        TestWindow.new(id: 9002, parent: root)
        let c = TestWindow.new(id: 9003, parent: root)

        // Behaviour of the surviving path is unchanged: first and last trade places.
        swapWindows(a, c)
        assertEquals(root.children.map { ($0 as! Window).windowId }, [9003, 9002, 9001])

        let orphan = TestWindow.new(id: 9004, parent: root)
        orphan.unbindFromParent()
        swapWindows(a, orphan)
        assertEquals(root.children.map { ($0 as! Window).windowId }, [9003, 9002, 9001])
    }

    /// `mainMonitor` used to be `singleOrNil(where: \.isMainScreen).orDie()`: fatal for *two*
    /// screens at the origin (display mirroring reports identical frames) and fatal for *none*
    /// (all displays asleep, or a DisplayLink dock mid-reconnect).
    func testMainScreenPickIsDefinedForMirroredAndForNoScreens() {
        assertEquals(mainScreenIndex(isMainFlags: [false, true, false]), 1)
        assertEquals(mainScreenIndex(isMainFlags: [true, true]), 0) // mirrored: first wins
        assertEquals(mainScreenIndex(isMainFlags: [false, false]), 0) // none claims the origin
        assertNil(mainScreenIndex(isMainFlags: []))
    }

    /// `Monitor.activeWorkspace` ended with `return self.activeWorkspace` after rebuilding the
    /// mapping. That is unbounded recursion, not a retry: the rebuild only ever populates points
    /// belonging to the *current* `monitors`, so a `Monitor` whose rect is not among them recursed
    /// until the stack ran out. A stale monitor held across an `await` is exactly that.
    func testActiveWorkspaceOfAMonitorThatIsNoLongerAttachedTerminates() {
        let ghostRect = Rect(topLeftX: 99999, topLeftY: 99999, width: 800, height: 600)
        let ghost = MonitorImpl(
            monitorAppKitNsScreenScreensId: 9,
            name: "unplugged",
            rect: ghostRect,
            visibleRect: ghostRect,
        )
        XCTAssertFalse(monitors.contains { $0.rect.topLeftCorner == ghostRect.topLeftCorner })

        // Reaching the next line at all is the assertion; the old code never returned from here.
        assertFalse(ghost.activeWorkspace.name.isEmpty)
    }
}

/// Minimal second `AbstractApp` conformer. `TestApp` is a singleton, so there is otherwise no way to
/// have two app objects at all, let alone two sharing a pid.
private final class PidOnlyApp: AbstractApp {
    let pid: Int32
    let bundleId: String? = nil
    let name: String? = nil
    let execPath: String? = nil
    let bundlePath: String? = nil
    init(pid: Int32) { self.pid = pid }
    @MainActor func getFocusedWindow() async throws -> Window? { nil }
}
