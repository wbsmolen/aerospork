import AppKit
import Common
import Foundation

/// Remembers where each window was, so restarting AeroSpork does not scatter the layout.
///
/// ## Why this is needed
///
/// Workspaces are emulated, not native Spaces: a hidden workspace's windows are parked off screen.
/// Nothing outside this process knows a window "belongs to" workspace `A`. At launch a window is
/// bound by where it physically sits, and at a cold start no workspace is active yet, so
/// `getStubWorkspace` invents one per monitor from the first keybound name in sort order. `A` sorts
/// after every digit, so a window left on `A` could never return to it. That is structural.
///
/// ## Both halves, or neither
///
/// A workspace name on its own is not enough, and a first attempt at this shipped exactly that
/// mistake. `Workspace.get(byName:)` mints a workspace whose `assignedMonitorPoint` is nil, and the
/// only writers of that field run when a workspace becomes *visible* or is force-assigned -- neither
/// true of one restored from a file. `workspaceMonitor` then falls through to `mainMonitor`, so
/// every restored workspace lands on the main display: right name, wrong monitor, with the other
/// monitors showing empty stubs. That is worse than binding by location, which at least got the
/// monitor right. So the monitor is persisted with the workspace and reassigned on restore.
///
/// ## Why `CGWindowID` alone, and nothing cleverer
///
/// The id comes from a monotonic counter in the WindowServer. It is exactly stable while that
/// process lives -- which spans any restart of *this* one -- and meaningless afterwards.
///
/// A composite key (bundle id + title + index + frame) looks like it would also survive an app
/// relaunch, and cannot. `AXIdentifier` names a window *class*, not an instance: every Terminal
/// window reports `TerminalWindowRestoration`, every Finder window `FinderWindow`, as the `axDumps/`
/// fixtures show. Titles follow tabs, the index into `kAXWindowsAttribute` is z-order, and the quit
/// cleanup overwrites the frame. Several identical terminal windows are indistinguishable, so a
/// composite key would shuffle them into an arbitrary permutation -- silently, and untestably, since
/// the fixtures really are identical. An exact id match cannot be wrong; it can only be absent.
///
/// Where the id is gone, `on-window-detected` with `if.during-aerospork-startup` is the right tool,
/// because there the user states intent instead of us guessing.
///
/// ## The generation token is the WindowServer, not the boot
///
/// The id counter restarts from the bottom whenever WindowServer does: a log out and back in, a
/// `killall WindowServer`, a graphics fault. None of those reboot the machine, and `/tmp` is not
/// cleared at logout. Guarding on `kern.boottime` therefore accepted a stale file across a logout --
/// new WindowServer hands out low ids again, macOS reopens the same apps so the bundle id still
/// matches, and windows land on workspaces they were never on. That is the one way this design could
/// produce a wrong answer rather than no answer, and the boot time does not close it. Measured here,
/// WindowServer started 49 seconds after boot, so the two are not even the same instant.
///
/// `kern.boottime` is unsuitable for a second reason: the kernel *adjusts* it when the calendar
/// clock is stepped, so an NTP correction would silently discard a good file.
@MainActor
enum WorkspaceMemory {
    struct WindowEntry: Codable, Equatable, Sendable {
        let workspace: String
        /// Checked against the live window's app, so an id reused within one WindowServer session by
        /// a different application is a no-op rather than a misplacement.
        let bundleId: String?
        /// Position and share of the split, as 1.3.1 wrote them. `State.trees` replaced both, so these are
        /// only ever read, from a file of that version. See `flatTree`.
        var index: Int? = nil
        var weight: CGFloat? = nil
        var isFloating: Bool? = nil
        /// Where a floating window of a hidden workspace goes back to, as a share of its monitor. Only the
        /// tree knows this, and a crash leaves the window parked, so its frame says nothing.
        var parkedAt: CGPoint? = nil
        var isFullscreen: Bool? = nil
        var noOuterGapsInFullscreen: Bool? = nil
    }

    struct State: Codable, Equatable, Sendable {
        let session: String
        var windows: [String: WindowEntry]
        /// Workspace name to the monitor it was on. Without this the restore is worse than useless
        /// on a multi-monitor setup; see the note above.
        let workspaceMonitors: [String: MonitorFingerprint]
        /// The workspaces on screen. Optional because a file written by an older version has none.
        var visibleWorkspaces: [String]? = nil
        /// Each workspace's tiling tree: the order of its windows, their sizes, what is nested in what, and
        /// each container's layout. Optional because a file written by an older version has none.
        var trees: [String: FrozenContainer]? = nil
    }

    /// Overridable so tests do not read or delete the real file. The default sits beside the CLI
    /// socket and deliberately nowhere near the config: this is a disposable cache, and
    /// `ConfigurationWriter`'s do-no-harm invariant must not be dragged into it.
    static var fileUrlOverride: URL?
    static var fileUrl: URL {
        if let fileUrlOverride { return fileUrlOverride }
        // `~/Library/Caches`, not `/tmp`.
        //
        // The CLI socket lives in /tmp because it is a rendezvous point two processes have to agree
        // on, and its security comes from filesystem permissions on a socket. This file is
        // different in kind: it is read at startup and acted on, so a planted one in a
        // world-writable directory decides where another user's windows go. Caches is per-user,
        // still disposable, and still not the config.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(filePath: NSTemporaryDirectory())
        let directory = caches.appending(path: aeroSporkAppId, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "workspace-memory.json")
    }

    /// WindowServer's pid and start time. Changes on every event that resets the id counter, and on
    /// reboot too, so it strictly dominates `kern.boottime`.
    static func currentSession() -> String {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        // Retried because the table can outgrow the size just read, which fails with ENOMEM. A burst
        // of launches at login is exactly when that happens, and an empty token costs the restore.
        for _ in 0 ..< 3 {
            var len = 0
            guard sysctl(&name, 4, nil, &len, nil, 0) == 0, len > 0 else { return "" }
            var procs = [kinfo_proc](repeating: kinfo_proc(), count: len / MemoryLayout<kinfo_proc>.stride)
            if sysctl(&name, 4, &procs, &len, nil, 0) == 0 {
                return windowServerSession(in: Array(procs.prefix(len / MemoryLayout<kinfo_proc>.stride)))
            }
            guard errno == ENOMEM else { return "" }
        }
        return ""
    }

    /// By uid as well as by name, because any process can call itself WindowServer. The real one runs
    /// as `_windowserver`, uid 88. That is its effective uid: its real uid is 0.
    static func windowServerSession(in procs: [kinfo_proc]) -> String {
        for var proc in procs where proc.kp_eproc.e_ucred.cr_uid == 88 {
            let comm = withUnsafeBytes(of: &proc.kp_proc.p_comm) { raw in
                String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            guard comm == "WindowServer" else { continue }
            let start = proc.kp_proc.p_un.__p_starttime
            return "ws:\(proc.kp_proc.p_pid):\(start.tv_sec).\(start.tv_usec)"
        }
        // No WindowServer (headless, or a sysctl failure). An empty token never equals a stored one,
        // so the memory is simply not used -- the guard degrades closed.
        return ""
    }

    static func session() -> String {
        if let sessionOverrideForTests { return sessionOverrideForTests }
        // `!isEmpty`, because `""` is a failure to look, not an answer. `if let cachedSession`
        // alone was true for it, so one transient `sysctl` failure at startup poisoned the cache for
        // the process lifetime -- and `write()` refuses to persist a state with an empty session, so
        // every save after that silently did nothing, for as long as the app ran. Re-reading costs
        // a process-table copy, but only on the machine where the first read failed and only when
        // the tree actually changed.
        if let cachedSession, !cachedSession.isEmpty { return cachedSession }
        let value = currentSession()
        cachedSession = value
        return value
    }

    private static var restored: State?
    /// Every entry as it was loaded. `restored` spends an entry when its window comes back, but its state
    /// is still read after that.
    private static var placements: [String: WindowEntry] = [:]
    /// Empty once the user has changed a layout. See `restoreLayout`.
    private static var trees: [String: FrozenContainer] = [:]
    /// `save()` before `load()` would persist an empty tree over a good file. That window is
    /// milliseconds wide -- a signal between `initTerminationHandler` and `load` -- but it costs one
    /// Bool to close.
    private static var isLoaded = false
    /// Skips the expensive half and the write when nothing changed, which is most refreshes.
    private static var lastWritten: CheapKey?
    /// `currentSession()` copies the whole process table -- measured 633 KiB and ~950 String
    /// allocations per call. It cannot meaningfully change while we run: if WindowServer restarts,
    /// every id we hold is void anyway. So it is read once.
    private static var cachedSession: String?
    /// Written only by `forceSessionForTests`. Separate from `cachedSession` so a test can pin the
    /// *empty* token -- which the cache above deliberately refuses to keep -- without the production
    /// retry reading the real WindowServer out from under it.
    private static var sessionOverrideForTests: String?
    /// Set the moment quitting begins. `makeAllWindowsVisibleAndRestoreSize` moves every window, and
    /// each AX write emits a notification that schedules a refresh -- which would call `save()`
    /// again and persist where the windows were dumped instead of where they belonged. Freezing is
    /// simpler than cancelling the pending refresh and does not depend on the debouncer's state.
    private static var isFrozen = false


    /// Reads the file if it belongs to this WindowServer session. Call once, before any window can
    /// be registered.
    static func load() {
        restored = nil
        placements = [:]
        trees = [:]
        lastWritten = nil
        isLoaded = true
        guard let data = try? Data(contentsOf: fileUrl),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return }
        let live = session()
        // An empty LIVE token means we could not identify the session, not that the file is stale.
        // Deleting on that would treat a failure to look as proof, and destroy a good file.
        guard !live.isEmpty else {
            debugLog("WorkspaceMemory: no WindowServer session; leaving the file alone and not restoring")
            return
        }
        guard !state.session.isEmpty, state.session == live else {
            debugLog("WorkspaceMemory: discarding state from a previous WindowServer session")
            try? FileManager.default.removeItem(at: fileUrl)
            return
        }
        restored = state
        placements = state.windows
        trees = state.trees ?? [:]
        debugLog("WorkspaceMemory: restored \(state.windows.count) windows")
    }

    /// The workspace this window was on, when it is provably the same window.
    static func workspace(forWindowId id: UInt32, bundleId: String?) -> String? {
        guard let entry = restored?.windows[String(id)] else { return nil }
        // A nil bundle id on either side is not a match: unknown is not the same as equal.
        guard let remembered = entry.bundleId, let bundleId, remembered == bundleId else { return nil }
        return entry.workspace
    }

    /// The workspace to bind a window to on restart, with its monitor already reattached.
    ///
    /// One entry point on purpose. Callers that took only the name got a workspace reporting
    /// `mainMonitor`, which collapsed every remembered workspace onto one display -- the defect that
    /// forced the first version of this to be reverted. Both halves, or neither.
    static func restoredWorkspace(forWindowId id: UInt32, bundleId: String?) -> Workspace? {
        guard let name = workspace(forWindowId: id, bundleId: bundleId) else { return nil }
        restored?.windows.removeValue(forKey: String(id)) // see `MacWindow.getOrRegister`
        let workspace = Workspace.get(byName: name)
        restoreMonitor(of: workspace)
        return workspace
    }

    /// Where a remembered window binds: floating if it was, or the place it kept, or `default`. Not a window
    /// that now looks like a popup, whatever it was before. `restoreLayout` then rebuilds the tree, while it
    /// still may.
    static func restoredBinding(of id: UInt32, on workspace: Workspace, default data: BindingData) -> BindingData {
        guard data.parent is TilingContainer else { return data }
        if placements[String(id)]?.isFloating == true {
            return BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
        return workspace.rootTilingContainer.takeAwaySlot(of: id) ?? data
    }

    static func restoreState(of window: Window) {
        guard let entry = placements[String(window.windowId)] else { return }
        window.isFullscreen = entry.isFullscreen == true
        window.noOuterGapsInFullscreen = entry.noOuterGapsInFullscreen == true
        if let parkedAt = entry.parkedAt { (window as? MacWindow)?.parkedPosition = parkedAt }
    }

    /// Puts a workspace's tiling tree back, with whichever of its windows are back so far.
    ///
    /// On every arrival, because apps answer in any order and some much later than others. Rebuilt whole
    /// from the file each time, so the result doesn't depend on that order, or on normalization having
    /// flattened a half-filled container in between. A window on the workspace that the tree doesn't name
    /// stays on it, and one that has gone elsewhere is left where it went.
    ///
    /// Only until the user changes a layout (`stopRestoringLayouts`). A window arriving after that goes
    /// where any new window goes, rather than undoing what they just did.
    static func restoreLayout(of workspace: Workspace) async throws {
        let root = workspace.rootTilingContainer
        guard let tree = trees[workspace.name] ?? flatTree(of: workspace.name, like: root) else { return }
        let windows = Dictionary(root.allLeafWindowsRecursive.map { ($0.windowId, $0) }, uniquingKeysWith: { first, _ in first })
        try await restoreTilingTree(of: workspace, from: tree) { windows[$0] }
    }

    static func stopRestoringLayouts() {
        trees = [:]
        for key in placements.keys { placements[key]?.index = nil }
    }

    /// What a file from 1.3.1 says about a tree: order and sizes, nothing nested. Only for the update from
    /// that version, whose file has no `trees`.
    private static func flatTree(of name: String, like root: TilingContainer) -> FrozenContainer? {
        let tiled = placements.compactMap { id, entry -> (index: Int, window: FrozenWindow)? in
            guard entry.workspace == name, let index = entry.index, let windowId = UInt32(id) else { return nil }
            return (index, FrozenWindow(id: windowId, weight: entry.weight ?? WEIGHT_AUTO))
        }
        if tiled.isEmpty { return nil }
        return FrozenContainer(
            children: tiled.sorted { $0.index < $1.index }.map { .window($0.window) },
            layout: root.layout,
            orientation: root.orientation,
            weight: 1,
        )
    }

    /// Puts every monitor back on the workspace it showed, and the rest back on their monitors.
    ///
    /// Only what focus adopted from macOS came back right before: a cold start fills the other monitors
    /// with whichever names come first, so one showed `3` when it had been showing `A`. The focused
    /// monitor keeps what focus adopted, because the window the user is on outranks the file.
    static func restoreVisibleWorkspaces() {
        guard let restored else { return }
        for name in restored.visibleWorkspaces ?? [] {
            guard let monitor = monitor(forWorkspace: name),
                  monitor.rect.topLeftCorner != focus.workspace.workspaceMonitor.rect.topLeftCorner
            else { continue }
            _ = monitor.setActiveWorkspace(Workspace.get(byName: name))
        }
        // The stubs that stood in have now been pinned to wherever they stood in.
        for name in restored.workspaceMonitors.keys {
            if let workspace = Workspace.existing(byName: name), !workspace.isVisible { restoreMonitor(of: workspace) }
        }
    }

    /// The workspace to remember a window under. A minimized one hangs off a global container, not a
    /// workspace, so it only has the name recorded on its way in.
    static func rememberedWorkspaceName(of window: Window) -> String? {
        if let workspace = window.nodeWorkspace { return workspace.name }
        if case .macos(_, let name) = window.layoutReason { return name }
        return nil
    }

    /// The monitor `workspace` was on, if it is still attached.
    ///
    /// UUID first, for the same reason `MonitorFingerprint.matches` checks it first: it is the only
    /// key that separates two otherwise identical panels. Full equality is the fallback, which also
    /// covers monitors that report no UUID.
    static func monitor(forWorkspace workspace: String) -> Monitor? {
        guard let saved = restored?.workspaceMonitors[workspace] else { return nil }
        let live = monitors
        if let uuid = saved.displayUUID, !uuid.isEmpty,
           let match = live.first(where: { $0.fingerprint?.displayUUID == uuid })
        {
            return match
        }
        return live.first { $0.fingerprint == saved }
    }

    /// Puts a restored workspace back on its monitor. Idempotent, and a no-op when the monitor is
    /// gone -- that workspace then falls back to today's behaviour instead of to a wrong answer.
    private static func restoreMonitor(of workspace: Workspace) {
        guard let monitor = monitor(forWorkspace: workspace.name) else { return }
        workspace.assignMonitor(monitor)
    }

    /// The cheap half of a snapshot: what is bound where, and which monitor each workspace is on by
    /// screen id. No fingerprints, no `sysctl`.
    ///
    /// This exists so the change check can run before the expensive half. Building the full state
    /// first and comparing afterwards meant every refresh paid for it, including the ones that
    /// changed nothing — which is most of them.
    private struct CheapKey: Equatable {
        let windows: [String: WindowEntry]
        let workspaceScreens: [String: Int]
        let visibleWorkspaces: [String]
        let trees: [String: FrozenContainer]
    }

    private static func cheapKey() -> CheapKey {
        var windows: [String: WindowEntry] = [:]
        var workspaceScreens: [String: Int] = [:]
        var trees: [String: FrozenContainer] = [:]
        for workspace in Workspace.all {
            // By what it names, not what is tiled: cmd-H can leave every window on a workspace away.
            let tree = FrozenContainer(workspace.rootTilingContainer)
            if !tree.allWindowIds.isEmpty { trees[workspace.name] = tree }
        }
        for window in MacWindow.allWindows {
            guard let name = rememberedWorkspaceName(of: window) else { continue }
            windows[String(window.windowId)] = WindowEntry(
                workspace: name,
                bundleId: window.macApp.bundleId,
                isFloating: window.isFloating ? true : nil,
                parkedAt: window.isFloating ? window.parkedPosition : nil,
                isFullscreen: window.isFullscreen ? true : nil,
                noOuterGapsInFullscreen: window.noOuterGapsInFullscreen ? true : nil,
            )
            if workspaceScreens[name] == nil, let workspace = Workspace.existing(byName: name) {
                workspaceScreens[name] = workspace.workspaceMonitor.monitorAppKitNsScreenScreensId
            }
        }
        let visible = Workspace.all.filter(\.isVisible)
        for workspace in visible where workspaceScreens[workspace.name] == nil {
            workspaceScreens[workspace.name] = workspace.workspaceMonitor.monitorAppKitNsScreenScreensId
        }
        return CheapKey(windows: windows, workspaceScreens: workspaceScreens, visibleWorkspaces: visible.map(\.name), trees: trees)
    }

    /// The full state. `MonitorFingerprint.fromScreen` is four CoreGraphics round trips per monitor
    /// and the monitor list is rebuilt on every access, so this is only reached when `cheapKey`
    /// says something actually changed.
    private static func fullState(_ key: CheapKey) -> State {
        let alive = windowServerWindowIds()
        if !isUnitTest { for workspace in Workspace.all { workspace.rootTilingContainer.forgetAway { !alive.contains($0) } } }
        var monitors = workspaceMonitors(for: Set(key.workspaceScreens.keys))
        // Keep the remembered monitor for any workspace this snapshot cannot see yet. Dropping it
        // would leave a restored window with its workspace and no monitor, which is precisely the
        // half-restore that made the first version of this worse than no restore at all.
        if let remembered = restored {
            for (name, fingerprint) in remembered.workspaceMonitors where monitors[name] == nil {
                if key.windows.values.contains(where: { $0.workspace == name }) {
                    monitors[name] = fingerprint
                }
            }
        }
        return State(
            session: session(),
            windows: key.windows.merging(unclaimedWindows(alive: alive)) { live, _ in live },
            workspaceMonitors: monitors,
            visibleWorkspaces: key.visibleWorkspaces,
            trees: key.trees,
        )
    }

    /// Remembered windows that haven't come back but still exist.
    ///
    /// A minimized window isn't in its app's window list, so after a restart nothing registers it until it
    /// is unminimized. It gets its place back then, but leaving it out of the file lost that place at the
    /// next restart. Ids are never reused within a session, so one that is gone is gone for good.
    static func unclaimedWindows(alive: Set<UInt32>) -> [String: WindowEntry] {
        restored?.windows.filter { UInt32($0.key).map(alive.contains) == true } ?? [:]
    }

    /// Only when something changed, like the rest of `fullState`. Not under test, where a real window's id
    /// could match a made-up one.
    private static func windowServerWindowIds() -> Set<UInt32> {
        guard !isUnitTest, let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[CFString: Any]] else { return [] }
        return Set(list.compactMap { ($0[kCGWindowNumber] as? Int).map(UInt32.init) })
    }

    /// The fingerprint of each named workspace's monitor.
    ///
    /// Separate from `fullState` so it can be tested without a real window tree: a headless suite
    /// has no `MacWindow`s, so a test driving `save()` end to end always produces an empty map and
    /// cannot tell whether monitors are recorded at all.
    static func workspaceMonitors(for names: Set<String>) -> [String: MonitorFingerprint] {
        var result: [String: MonitorFingerprint] = [:]
        for name in names {
            if let fingerprint = Workspace.get(byName: name).workspaceMonitor.fingerprint {
                result[name] = fingerprint
            }
        }
        return result
    }

    /// Serial, so two writes cannot land out of order.
    ///
    /// Two `Task.detached` writes raced: `.atomic` is write-then-rename, and with no ordering
    /// guarantee the OLDER snapshot won about half the time — measured 240/500. Worse, `lastWritten`
    /// had already recorded the newer one, so the early-out suppressed every attempt to correct it.
    private static let writeQueue = DispatchQueue(label: "\(aeroSporkAppId).workspace-memory")

    private static func write(_ state: State, waitForCompletion: Bool) {
        // Never persist a state whose session we could not determine: `load()` would reject it, so
        // writing it just destroys whatever was there.
        guard !state.session.isEmpty else { return }
        let url = fileUrl
        let work: @Sendable () -> Void = {
            guard let data = try? JSONEncoder().encode(state) else { return }
            try? data.write(to: url, options: .atomic)
            // 0600: this names every running app's bundle id and every monitor's UUID. Set after the
            // write because `.atomic` replaces the file, so any mode set beforehand is discarded.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        if waitForCompletion { writeQueue.sync(execute: work) } else { writeQueue.async(execute: work) }
    }

    /// Persists the tree if it changed. The snapshot stays on the main thread; encoding and writing
    /// do not.
    static func save() {
        guard isLoaded, !isFrozen else { return }
        var key = cheapKey()
        // During startup, add but never prune.
        //
        // AeroSpork launches alongside every other login item and macOS's own window restore, so an
        // app that has not answered Accessibility yet is simply absent from this snapshot. Writing
        // it as-is deletes that window's entry -- and since the memory is only consulted while
        // `isStartup`, the window has already lost its one chance by the time it appears. Keeping
        // the remembered entries means a slow app is restored when it does show up.
        if isStartup, let remembered = restored {
            key = CheapKey(
                windows: remembered.windows.merging(key.windows) { _, new in new },
                workspaceScreens: key.workspaceScreens,
                // What a cold start shows until `restoreVisibleWorkspaces` runs is not worth remembering.
                visibleWorkspaces: remembered.visibleWorkspaces ?? key.visibleWorkspaces,
                // Half a tree, with the windows back so far. The whole one is still what happens next.
                trees: remembered.trees ?? key.trees,
            )
        }
        guard key != lastWritten else { return }
        lastWritten = key
        write(fullState(key), waitForCompletion: false)
    }

    /// The quit-time save. Waits for the write — and because the queue is serial and FIFO, waiting
    /// also drains any refresh-scheduled write still in flight, so none of them can land on top of
    /// this one afterwards.
    static func freezeAndSave() {
        guard isLoaded else { isFrozen = true; return }
        let key = cheapKey()
        lastWritten = key
        write(fullState(key), waitForCompletion: true)
        isFrozen = true
    }

    /// Test seams for the two paths a test cannot otherwise reach: writing a state directly, and
    /// pretending the session could not be read.
    static func writeForTests(_ state: State) { write(state, waitForCompletion: false) }
    static func forceSessionForTests(_ value: String) { sessionOverrideForTests = value }
    /// Plants a value in the production cache, unlike `forceSessionForTests`, which bypasses it --
    /// the only way to check that a cached failure is retried rather than kept.
    static func cacheSessionForTests(_ value: String) { cachedSession = value }

    /// A quit that was asked for and then vetoed leaves us running. Without this the memory stays
    /// frozen for the rest of the session, so a crash hours later restores the layout as it was at
    /// the cancelled logout.
    static func unfreezeAfterCancelledQuit() { isFrozen = false }

    /// Test seam: blocks until every queued write has landed, so a test can read the file back
    /// without racing the asynchronous path that production actually uses.
    static func waitForWrites() { writeQueue.sync {} }

    /// Forgets what was last written, so the next `save()` really tries to write. Without this a
    /// test cannot tell the freeze guard from the unchanged-tree early-out.
    static func invalidateChangeCheckForTests() { lastWritten = nil }

    /// Test seam. All the state here is process-global, which is right for a singleton with one
    /// lifecycle and wrong for a suite that runs many cases in one process.
    static func resetForTests() {
        restored = nil
        placements = [:]
        trees = [:]
        lastWritten = nil
        isLoaded = false
        isFrozen = false
        fileUrlOverride = nil
        cachedSession = nil
        sessionOverrideForTests = nil
    }
}
