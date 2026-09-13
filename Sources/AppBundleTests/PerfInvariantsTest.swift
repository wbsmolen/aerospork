@testable import AppBundle
import Combine
import Common
import Foundation
import XCTest

/// Regression tests for the *algorithmic* properties the performance work rests on.
///
/// Deliberately not wall-clock benchmarks: dev-docs/performance.md measured ~12x run-to-run
/// variance on unchanged code (cold app registration, AX round-trip latency, ambient load), which
/// is far larger than anything worth detecting. Every claim below is instead a deterministic,
/// zero-timing property that would silently regress if someone "simplified" the code.
@MainActor
final class PerfInvariantsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// `refresh()` membership-tests one id per live window, so an Array here is O(W^2).
    ///
    /// TRADEOFF: asserted against the source text because `aliveWindowIds` is a local inside a
    /// private `refresh()` that needs real AX apps to reach. Upgrade path: if the alive-id set ever
    /// becomes a value the refresh loop is handed rather than one it builds, assert on its type.
    func testAliveWindowIdsIsASetNotAnArray() throws {
        let source = try String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/layout/refresh.swift"), encoding: .utf8)
        let line = source.split(separator: "\n").first { $0.contains("let aliveWindowIds") }
        assertNotNil(line)
        assertEquals(line?.contains("= Set("), true, additionalMsg: "aliveWindowIds must stay a Set: \(line ?? "<missing>")")
    }

    /// Every `@Published` write invalidates `MenuBarExtra`, and `MenuBarLabel` then re-rasterizes
    /// the whole label through `ImageRenderer` on the main thread. `updateTrayText()` runs on every
    /// refresh, so publishing an unchanged value is a full SwiftUI-to-CGImage pass at up to 20Hz
    /// producing a byte-identical image.
    func testTrayDoesNotPublishWhenNothingChanged() {
        updateTrayText() // settle: the first call legitimately publishes

        var publishes = 0
        let subscription = TrayMenuModel.shared.objectWillChange.sink { _ in publishes += 1 }
        defer { subscription.cancel() }

        updateTrayText()
        assertEquals(publishes, 0)

        // Counter-check: the guard must be an equality check, not a mute button.
        let other = Workspace.get(byName: "perf-invariants-other")
        check(other.focusWorkspace())
        check(mainMonitor.setActiveWorkspace(other))
        updateTrayText()
        assertTrue(publishes > 0)
    }

    /// `debugLog` is called several times per refresh and once per command parse. The `@autoclosure`
    /// is what keeps the string interpolation -- including whatever `description` the arguments
    /// build -- from running when logging is off.
    func testDebugLogDoesNotEvaluateItsMessageWhenGateIsOff() throws {
        try XCTSkipIf(isDebugLoggingEnabled, "AEROSPORK_DEBUG_LOG is set, so the message is supposed to be evaluated")
        var evaluated = false
        debugLog({ evaluated = true; return "expensive" }())
        assertFalse(evaluated)
    }

    // The fourth property -- "the setFrame no-op guard actually skips AX writes when the frame
    // already matches" -- is pinned by AxWriteTest.testGuardSkipsAllWritesWhenFrameAlreadyMatches,
    // which counts writes through the AX mock rather than timing them. Its sibling,
    // testGuardStopsReadingAtFirstDisagreement, pins the read count.

    /// `TreeNode.unbindIfBound` used to call `Thread.callStackSymbols` unconditionally.
    ///
    /// That symbolicates every frame of a deep async stack, and it runs on EVERY rebind -- `bind`
    /// unbinds first, so container flattening, `relayoutWindow` and every tree-moving command paid
    /// it -- to build a string whose only consumer is a `dieT` message that fires once, ever, in a
    /// process that is already crashing. It is now behind the same gate as `debugLog`.
    func testUnbindDoesNotSymbolicateTheStackWhenDebugLoggingIsOff() throws {
        try XCTSkipIf(isDebugLoggingEnabled, "AEROSPORK_DEBUG_LOG is set, so the stacktrace is supposed to be captured")
        let workspace = Workspace.get(byName: "unbind-stacktrace")
        let window = TestWindow.new(id: 8001, parent: workspace.rootTilingContainer)
        window.unbindFromParent()
        assertNil(window.unboundStacktrace)
    }

    // MARK: - Workspaces are not materialized just because a keybinding names them

    /// The largest win in the whole performance pass, and until now the only one with no test.
    ///
    /// Workspaces used to be force-created for every name any keybinding mentioned. With a normal
    /// i3-style keymap that is ~35 objects that exist only because a shortcut says the name: every
    /// refresh then walked all of them for layout, normalization and tray text, and the menu bar
    /// listed all of them. Measured on the real machine: **32 workspaces, 0 windows**.
    ///
    /// The invariant is not "few workspaces" but "a workspace exists only if something is in it, it
    /// is on screen, you are looking at it, or the config declares it". Declared workspaces are
    /// `PersistentWorkspacesTest`'s business; here the config declares none.
    func testEmptyWorkspacesAreCollectedNoMatterHowManyNamesAreBound() {
        let bound = (1 ... 9).map(String.init) + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        config.preservedWorkspaceNames = bound

        // Materialize them the way the old code did, so there is something to collect. Asserting
        // against a registry that was already empty would pass with the GC deleted entirely.
        for name in bound { _ = Workspace.get(byName: name) }
        assertEquals(Workspace.all.count, bound.count + 1) // +1 for the focused one from setUp

        Workspace.garbageCollectUnusedWorkspaces()

        // Only the focused one survives -- it is empty, but it is where the user is.
        assertEquals(Workspace.all.map(\.name), [focus.workspace.name])
    }

    /// The counter-check: collection must be driven by emptiness, not by a name list. A workspace
    /// holding a window survives even though nothing references its name.
    func testAWorkspaceWithAWindowIsNeverCollected() {
        let occupied = Workspace.get(byName: "has-a-window")
        TestWindow.new(id: 1, parent: occupied.rootTilingContainer)

        Workspace.garbageCollectUnusedWorkspaces()

        XCTAssertTrue(Workspace.all.contains { $0.name == "has-a-window" }, Workspace.all.map(\.name).description)
    }

    /// `getStubWorkspace` prefers a bound name, and walks that list lazily. Eagerly mapping 35 names
    /// to `Workspace.get(byName:)` would re-create on every monitor rearrange exactly the population
    /// this GC exists to remove -- the fix for one symptom silently reinstating the other.
    func testPickingAStubDoesNotInstantiateEveryBoundName() {
        config.preservedWorkspaceNames = (1 ... 9).map(String.init) + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        let before = Workspace.all.count

        _ = getStubWorkspace(for: mainMonitor)

        // One new workspace at most: the stub itself. Not 35.
        XCTAssertTrue(
            Workspace.all.count <= before + 1,
            "instantiated \(Workspace.all.count - before) workspaces to pick one stub: \(Workspace.all.map(\.name))",
        )
    }

    // MARK: - Hot paths stay free of unconditional I/O

    /// `forceAssignedMonitor` is the first thing `workspaceMonitor` checks, and `workspaceMonitor` is
    /// called from layout, focus, tray updates and `hideInCorner` -- many times per refresh. It once
    /// held two unconditional `print("[DEBUG]...")` calls, i.e. an unbuffered stdout write per call
    /// for any user with `workspace-to-monitor-force-assignment` configured.
    ///
    /// `print` specifically: `debugLog` is gated and `@autoclosure`, so it is fine anywhere.
    func testHotPathsContainNoUnconditionalPrint() throws {
        let hotFiles = [
            "Sources/AppBundle/tree/Workspace.swift",
            "Sources/AppBundle/tree/MacApp.swift",
            "Sources/AppBundle/tree/MacWindow.swift",
            "Sources/AppBundle/layout/refresh.swift",
            "Sources/AppBundle/layout/layoutRecursive.swift",
            "Sources/AppBundle/normalizeLayoutReason.swift",
            "Sources/AppBundle/focus.swift",
        ]
        for path in hotFiles {
            let source = try String(contentsOf: projectRoot.appending(path: path), encoding: .utf8)
            for (i, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("///") { continue }
                // `printStderr` is the deliberate error channel; only bare `print(` is the problem.
                XCTAssertFalse(
                    code.contains("print(") && !code.contains("printStderr("),
                    "\(path):\(i + 1) does unconditional stdout I/O in a hot path -- use debugLog: \(code)",
                )
            }
        }
    }
}
