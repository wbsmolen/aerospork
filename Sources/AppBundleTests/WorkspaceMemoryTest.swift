@testable import AppBundle
import Common
import Foundation
import XCTest

/// Restoring window placement across a restart.
///
/// The first version of this feature was reverted, and the reason shapes these tests: it restored a
/// workspace *name* and nothing else, so every restored workspace reported `mainMonitor` and a
/// multi-monitor layout collapsed onto one display. Its own suite stayed green through all of it,
/// because it only ever exercised the pure lookup API — emptying `save()` or deleting the restore
/// hook changed nothing. So the tests that matter here are the ones about the **monitor** and about
/// the hook being wired at all.
@MainActor
final class WorkspaceMemoryTest: XCTestCase {
    private var tempDir: URL!
    private var savedMonitors: [Monitor]!

    /// Two monitors that differ only by UUID — the case the whole fingerprint design exists for, and
    /// the one a name or a size cannot tell apart.
    private let leftUuid = "11111111-1111-1111-1111-111111111111"
    private let rightUuid = "22222222-2222-2222-2222-222222222222"

    private func fingerprint(uuid: String) -> MonitorFingerprint {
        MonitorFingerprint(
            vendorID: nil, modelID: nil, serialNumber: nil,
            displayName: "ACME 32", widthPixels: 3840, heightPixels: 2160,
            displayUUID: uuid,
        )
    }

    override func setUp() {
        WorkspaceMemory.resetForTests()
        savedMonitors = testMonitors
        tempDir = URL(filePath: NSTemporaryDirectory()).appending(path: "wsmem-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // Never the real file: the previous suite wrote to the live debug state path and deleted it
        // in setUp, so running the tests destroyed a running debug app's state.
        WorkspaceMemory.fileUrlOverride = tempDir.appending(path: "state.json")

        let left = Rect(topLeftX: 0, topLeftY: 0, width: 3840, height: 2160)
        let right = Rect(topLeftX: 3840, topLeftY: 0, width: 3840, height: 2160)
        testMonitors = [
            MonitorImpl(monitorAppKitNsScreenScreensId: 1, name: "ACME 32", rect: left, visibleRect: left,
                        fingerprint: fingerprint(uuid: leftUuid)),
            MonitorImpl(monitorAppKitNsScreenScreensId: 2, name: "ACME 32", rect: right, visibleRect: right,
                        fingerprint: fingerprint(uuid: rightUuid)),
        ]
    }

    override func tearDown() {
        testMonitors = savedMonitors
        WorkspaceMemory.resetForTests()
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ state: WorkspaceMemory.State) {
        try! JSONEncoder().encode(state).write(to: WorkspaceMemory.fileUrl)
    }

    private func state(
        session: String,
        windows: [String: WorkspaceMemory.WindowEntry],
        monitors: [String: MonitorFingerprint] = [:],
    ) -> WorkspaceMemory.State {
        WorkspaceMemory.State(session: session, windows: windows, workspaceMonitors: monitors)
    }

    // MARK: - The defect that forced the revert

    /// A restored workspace must come back on the monitor it was on, not on the main one.
    ///
    /// This is the whole point. Restoring only the name gives a `Workspace` whose
    /// `assignedMonitorPoint` is nil, and `workspaceMonitor` then falls through to `mainMonitor` —
    /// so every remembered workspace piles onto one display. That version passed its own tests.
    func testARestoredWorkspaceKeepsItsMonitor() {
        write(state(
            session: WorkspaceMemory.currentSession(),
            windows: ["42": .init(workspace: "A", bundleId: "com.apple.finder")],
            monitors: ["A": fingerprint(uuid: rightUuid)],
        ))
        WorkspaceMemory.load()

        let workspace = try! XCTUnwrap(
            WorkspaceMemory.restoredWorkspace(forWindowId: 42, bundleId: "com.apple.finder"),
        )
        assertEquals(workspace.name, "A")
        XCTAssertEqual(
            workspace.workspaceMonitor.rect.topLeftX, 3840,
            "restored onto the main monitor instead of the one it was on -- this is the revert defect",
        )
    }

    /// What the UUID-first branch is actually for: the panel is the same one, but something else
    /// about it changed while AeroSpork was not running.
    ///
    /// Whole-fingerprint equality fails here — the resolution and the name both moved — so without
    /// the UUID check the workspace silently loses its monitor. Note that the *other* obvious test,
    /// two monitors differing only by UUID, proves nothing about ordering: plain equality already
    /// includes the UUID and picks correctly.
    func testAMonitorIsStillFoundAfterItsResolutionOrNameChanges() {
        let stale = MonitorFingerprint(
            vendorID: nil, modelID: nil, serialNumber: nil,
            displayName: "ACME 32 (old name)", widthPixels: 1920, heightPixels: 1080,
            displayUUID: rightUuid,
        )
        write(state(
            session: WorkspaceMemory.session(),
            windows: ["5": .init(workspace: "D", bundleId: "com.apple.finder")],
            monitors: ["D": stale],
        ))
        WorkspaceMemory.load()

        let monitor = WorkspaceMemory.monitor(forWorkspace: "D")
        XCTAssertEqual(
            monitor?.rect.topLeftX, 3840,
            "the panel was not recognised after its resolution changed, so the workspace lost its monitor",
        )
    }

    /// Two monitors differing only by UUID must not be confused for one another.
    func testTheMonitorIsMatchedByUuidNotByName() {
        write(state(
            session: WorkspaceMemory.currentSession(),
            windows: ["7": .init(workspace: "B", bundleId: "com.apple.finder")],
            monitors: ["B": fingerprint(uuid: leftUuid)],
        ))
        WorkspaceMemory.load()

        let workspace = try! XCTUnwrap(WorkspaceMemory.restoredWorkspace(forWindowId: 7, bundleId: "com.apple.finder"))
        assertEquals(workspace.workspaceMonitor.rect.topLeftX, 0)
    }

    /// A monitor that is no longer attached must degrade to today's behaviour, not to a wrong one.
    func testAnUnpluggedMonitorLeavesTheWorkspaceUnpinned() {
        write(state(
            session: WorkspaceMemory.currentSession(),
            windows: ["9": .init(workspace: "C", bundleId: "com.apple.finder")],
            monitors: ["C": fingerprint(uuid: "33333333-3333-3333-3333-333333333333")],
        ))
        WorkspaceMemory.load()

        XCTAssertNotNil(WorkspaceMemory.restoredWorkspace(forWindowId: 9, bundleId: "com.apple.finder"))
        XCTAssertNil(WorkspaceMemory.monitor(forWorkspace: "C"), "an absent monitor must not resolve to something else")
    }

    // MARK: - The generation guard

    /// `CGWindowID`s are reissued from the bottom when WindowServer restarts, which a log out does
    /// without rebooting. A file from a previous session names ids that now mean something else.
    func testStateFromAnotherWindowServerSessionRestoresNothing() {
        write(state(session: "ws:1:1.1", windows: ["42": .init(workspace: "A", bundleId: "com.apple.finder")]))
        WorkspaceMemory.load()

        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), nil)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: WorkspaceMemory.fileUrl.path),
            "a file from a dead session should be deleted, not left to be reconsidered",
        )
    }

    /// An empty token means we could not identify the session at all. It must never compare equal to
    /// a stored one, or the guard degrades open.
    func testAnEmptySessionTokenNeverMatches() {
        write(state(session: "", windows: ["42": .init(workspace: "A", bundleId: "com.apple.finder")]))
        WorkspaceMemory.load()

        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), nil)
    }

    /// The token must really name the running WindowServer.
    ///
    /// A shape-only assertion is not enough: stubbing `currentSession()` to a constant passes
    /// `hasPrefix("ws:")` while making the guard incapable of ever rejecting a stale file — which is
    /// the whole defect it exists to prevent. Verified by doing exactly that and watching the weaker
    /// version stay green. So this cross-checks the pid against `pgrep`, which reaches the process
    /// list by a different route than the `sysctl` under test.
    func testTheSessionTokenNamesTheRunningWindowServer() throws {
        let token = WorkspaceMemory.currentSession()
        let parts = token.split(separator: ":")
        try XCTSkipIf(parts.count != 3 && !FileManager.default.fileExists(atPath: "/usr/bin/pgrep"),
                      "no WindowServer and no pgrep: not a graphical session")
        assertEquals(parts.count, 3, additionalMsg: "unexpected token shape: \(token)")
        assertEquals(String(parts[0]), "ws")

        let pgrep = Process()
        pgrep.executableURL = URL(filePath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "WindowServer"]
        let pipe = Pipe()
        pgrep.standardOutput = pipe
        try XCTSkipIf((try? pgrep.run()) == nil, "could not run pgrep")
        pgrep.waitUntilExit()
        let pids = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(whereSeparator: \.isNewline).map(String.init)
        try XCTSkipIf(pids.isEmpty, "WindowServer is not running; nothing to cross-check against")

        XCTAssertTrue(
            pids.contains(String(parts[1])),
            "token names pid \(parts[1]) but pgrep reports WindowServer at \(pids) -- the token does "
                + "not identify the real session, so the guard can never reject a stale file",
        )
        XCTAssertTrue(Double(parts[2]) != nil, "start time is not a number: \(parts[2])")
    }

    /// Two calls in the same session must agree, or every load would discard a valid file.
    func testTheSessionTokenIsStable() {
        assertEquals(WorkspaceMemory.currentSession(), WorkspaceMemory.currentSession())
    }

    // MARK: - Refusals

    func testAnUnknownWindowIdIsNotAnswered() {
        write(state(session: WorkspaceMemory.currentSession(),
                    windows: ["42": .init(workspace: "A", bundleId: "com.apple.finder")]))
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 99, bundleId: "com.apple.finder"), nil)
    }

    func testAnIdNowOwnedByADifferentAppIsNotAnswered() {
        write(state(session: WorkspaceMemory.currentSession(),
                    windows: ["42": .init(workspace: "A", bundleId: "com.apple.finder")]))
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.googlecode.iterm2"), nil)
    }

    /// Unknown is not the same as equal, in either direction.
    func testAMissingBundleIdIsNeverAMatch() {
        write(state(session: WorkspaceMemory.currentSession(), windows: [
            "42": .init(workspace: "A", bundleId: "com.apple.finder"),
            "43": .init(workspace: "B", bundleId: nil),
        ]))
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: nil), nil)
        assertEquals(WorkspaceMemory.workspace(forWindowId: 43, bundleId: "com.apple.finder"), nil)
        assertEquals(WorkspaceMemory.workspace(forWindowId: 43, bundleId: nil), nil)
    }

    func testNoFileAndCorruptFileBothRestoreNothing() {
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), nil)

        try! Data("not json".utf8).write(to: WorkspaceMemory.fileUrl)
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), nil)
    }

    // MARK: - Writing

    /// Exercises `save()`, the function production actually calls — not `saveBlocking`.
    ///
    /// The previous version of these tests only ever went through a test-only helper, so every
    /// mutation of the real write path survived: emptying `save()`, deleting the write inside its
    /// detached task, returning before scheduling it. All of them left the suite green.
    func testSaveWritesAFileThatLoadAccepts() throws {
        WorkspaceMemory.load() // no file yet
        XCTAssertFalse(FileManager.default.fileExists(atPath: WorkspaceMemory.fileUrl.path))

        WorkspaceMemory.save()
        WorkspaceMemory.waitForWrites()

        let data = try XCTUnwrap(
            try? Data(contentsOf: WorkspaceMemory.fileUrl),
            "save() wrote nothing, so nothing can ever be restored",
        )
        let written = try JSONDecoder().decode(WorkspaceMemory.State.self, from: data)
        assertEquals(written.session, WorkspaceMemory.session())
    }

    /// And what it writes must survive the next load rather than being discarded as stale.
    func testWhatSaveWritesIsStillValidOnTheNextLoad() throws {
        WorkspaceMemory.load()
        WorkspaceMemory.save()
        WorkspaceMemory.waitForWrites()

        WorkspaceMemory.load()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: WorkspaceMemory.fileUrl.path),
            "load() deleted the file save() had just written, so the memory can never survive a restart",
        )
    }

    /// A signal arriving between `initTerminationHandler` and `load()` would otherwise persist an
    /// empty tree over a good file.
    func testSaveBeforeLoadDoesNotTouchTheFile() throws {
        write(state(session: WorkspaceMemory.session(),
                    windows: ["42": .init(workspace: "A", bundleId: "com.apple.finder")]))
        let before = try Data(contentsOf: WorkspaceMemory.fileUrl)

        WorkspaceMemory.save() // no load() first
        WorkspaceMemory.waitForWrites()

        assertEquals(try Data(contentsOf: WorkspaceMemory.fileUrl), before)
    }

    /// The quit path must take a real snapshot and *then* stop.
    ///
    /// Asserting only "nothing changed after the freeze" is vacuous: swapping the two statements in
    /// `freezeAndSave` so quitting persists nothing at all passes that. So this asserts the content
    /// actually landed.
    func testTheQuitSaveWritesTheTreeAndThenFreezes() throws {
        WorkspaceMemory.load()

        WorkspaceMemory.freezeAndSave()
        WorkspaceMemory.waitForWrites()

        let data = try XCTUnwrap(
            try? Data(contentsOf: WorkspaceMemory.fileUrl),
            "quitting wrote nothing -- the freeze happened before the save",
        )
        let written = try JSONDecoder().decode(WorkspaceMemory.State.self, from: data)
        assertEquals(written.session, WorkspaceMemory.session())

        // And then nothing more is accepted. The change check has to be invalidated first, or an
        // unchanged tree short-circuits `save()` and the freeze guard looks tested when it is not.
        try FileManager.default.removeItem(at: WorkspaceMemory.fileUrl)
        WorkspaceMemory.invalidateChangeCheckForTests()
        WorkspaceMemory.save()
        WorkspaceMemory.waitForWrites()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: WorkspaceMemory.fileUrl.path),
            "a save after the freeze landed, so the cleanup's own refresh can overwrite the snapshot",
        )
    }

    /// A state whose session could not be determined must never be written: `load()` would reject
    /// it, so persisting it only destroys what was there.
    func testAStateWithNoSessionIsNeverWritten() throws {
        write(state(session: WorkspaceMemory.session(),
                    windows: ["42": .init(workspace: "A", bundleId: "com.apple.finder")]))
        let before = try Data(contentsOf: WorkspaceMemory.fileUrl)
        WorkspaceMemory.load()

        WorkspaceMemory.writeForTests(state(session: "", windows: [:]))
        WorkspaceMemory.waitForWrites()

        assertEquals(try Data(contentsOf: WorkspaceMemory.fileUrl), before)
    }

    /// Failing to identify the session is not proof the file is stale. Deleting it on that basis
    /// destroys a perfectly good memory whenever the process table read happens to fail.
    func testAnUnidentifiableLiveSessionLeavesTheFileAlone() throws {
        write(state(session: "ws:1:1.1", windows: ["42": .init(workspace: "A", bundleId: "com.apple.finder")]))
        WorkspaceMemory.forceSessionForTests("")

        WorkspaceMemory.load()

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: WorkspaceMemory.fileUrl.path),
            "the file was deleted because we could not read the session, not because it was stale",
        )
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), nil)
    }

    /// `save()` must record the monitor each workspace is on, or a restore has only half of what it
    /// needs — the half whose absence forced the previous version to be reverted.
    ///
    /// Tested against the extracted helper: a headless suite has no windows, so a full `save()`
    /// always yields an empty map and cannot see this at all.
    func testTheSnapshotRecordsEachWorkspacesMonitor() {
        let workspace = Workspace.get(byName: "A")
        workspace.assignMonitor(testMonitors[1])

        let recorded = WorkspaceMemory.workspaceMonitors(for: ["A"])

        assertEquals(recorded["A"]?.displayUUID, rightUuid)
    }

    // MARK: - The hook

    /// The restore is only reachable through `MacWindow.getOrRegister`, which needs a real
    /// Accessibility window, so this pins the call *shape* in the source.
    ///
    /// A grep for the function name alone is not enough, and the previous version proved it: passing
    /// `bundleId: nil` makes every lookup reject its entry — the feature permanently dead — while the
    /// name is still there. So the arguments are pinned too, whitespace-normalised.
    func testWindowRegistrationRestoresUsingTheWindowsOwnApp() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/tree/MacWindow.swift"),
            encoding: .utf8,
        )
        let normalised = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(
            normalised.contains(
                "WorkspaceMemory.restoredWorkspace(forWindowId: windowId, bundleId: macApp.bundleId)",
            ),
            """
            window registration does not consult the memory with this window's own id and app.
            Passing anything else -- `nil` in particular -- makes every lookup fail and the feature
            silently does nothing.
            """,
        )
    }

    /// And the result has to be what the window is bound to, not something computed and dropped.
    func testTheRestoredWorkspaceIsWhatTheWindowIsBoundTo() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/tree/MacWindow.swift"),
            encoding: .utf8,
        )
        let normalised = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(
            normalised.contains(
                "? WorkspaceMemory.restoredWorkspace(forWindowId: windowId, bundleId: macApp.bundleId) "
                    + "?? (rect?.center.monitorApproximation ?? mainMonitor).activeWorkspace",
            ),
            """
            the remembered workspace is not the value bound to the window -- location is being used
            regardless, so the memory is computed and thrown away.
            """,
        )
    }

    /// Restoring the name without the monitor is the reverted defect. `restoredWorkspace` is the one
    /// entry point that does both, so the raw name lookup must not be what registration calls.
    func testWindowRegistrationDoesNotUseTheNameOnlyLookup() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/tree/MacWindow.swift"),
            encoding: .utf8,
        )
        XCTAssertFalse(
            source.contains("WorkspaceMemory.workspace(forWindowId:"),
            "registration takes the workspace name without its monitor -- that collapses every "
                + "restored workspace onto the main display",
        )
    }

    /// `load()` must be called, and before anything can register a window.
    func testLoadIsCalledAtStartupBeforeRegistrationCanHappen() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/initAppBundle.swift"),
            encoding: .utf8,
        )
        let load = try XCTUnwrap(
            source.range(of: "WorkspaceMemory.load()")?.lowerBound,
            "nothing loads the memory, so the whole feature is inert",
        )
        let observers = try XCTUnwrap(source.range(of: "GlobalObserver.initObserver()")?.lowerBound)
        XCTAssertLessThan(load, observers, "windows can be registered before the memory is loaded")
    }

    /// The refresh-time save is what covers a crash or force quit, neither of which reaches the quit
    /// path at all.
    func testTheRefreshLoopPersistsTheTree() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/layout/refresh.swift"),
            encoding: .utf8,
        )
        XCTAssertTrue(
            source.contains("WorkspaceMemory.save()"),
            "nothing persists between quits, so a crash or `killall -9` loses the layout",
        )
    }

    func testTheQuitPathSnapshotsBeforeTheCleanupMovesAnything() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/util/appBundleUtil.swift"),
            encoding: .utf8,
        )
        let save = try XCTUnwrap(source.range(of: "WorkspaceMemory.freezeAndSave()")?.lowerBound)
        let cleanup = try XCTUnwrap(source.range(of: "makeAllWindowsVisibleAndRestoreSize()")?.lowerBound)
        XCTAssertLessThan(save, cleanup, "the snapshot must be taken before the windows are moved")
    }
}
