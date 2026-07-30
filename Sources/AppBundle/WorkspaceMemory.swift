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
    }

    struct State: Codable, Equatable, Sendable {
        let session: String
        let windows: [String: WindowEntry]
        /// Workspace name to the monitor it was on. Without this the restore is worse than useless
        /// on a multi-monitor setup; see the note above.
        let workspaceMonitors: [String: MonitorFingerprint]
    }

    /// Overridable so tests do not read or delete the real file. The default sits beside the CLI
    /// socket and deliberately nowhere near the config: this is a disposable cache, and
    /// `ConfigurationWriter`'s do-no-harm invariant must not be dragged into it.
    static var fileUrlOverride: URL?
    static var fileUrl: URL {
        fileUrlOverride ?? URL(filePath: "/tmp/\(aeroSporkAppId)-\(unixUserName).state.json")
    }

    /// WindowServer's pid and start time. Changes on every event that resets the id counter, and on
    /// reboot too, so it strictly dominates `kern.boottime`.
    static func currentSession() -> String {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var len = 0
        guard sysctl(&name, 4, nil, &len, nil, 0) == 0, len > 0 else { return "" }
        let capacity = len / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: capacity)
        guard sysctl(&name, 4, &procs, &len, nil, 0) == 0 else { return "" }
        for var proc in procs[0 ..< min(capacity, len / MemoryLayout<kinfo_proc>.stride)] {
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
        if let cachedSession { return cachedSession }
        let value = currentSession()
        cachedSession = value
        return value
    }

    private static var restored: State?
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
    /// Set the moment quitting begins. `makeAllWindowsVisibleAndRestoreSize` moves every window, and
    /// each AX write emits a notification that schedules a refresh -- which would call `save()`
    /// again and persist where the windows were dumped instead of where they belonged. Freezing is
    /// simpler than cancelling the pending refresh and does not depend on the debouncer's state.
    private static var isFrozen = false


    /// Reads the file if it belongs to this WindowServer session. Call once, before any window can
    /// be registered.
    static func load() {
        restored = nil
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
        let workspace = Workspace.get(byName: name)
        restoreMonitor(of: workspace)
        return workspace
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
    static func restoreMonitor(of workspace: Workspace) {
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
    }

    private static func cheapKey() -> CheapKey {
        var windows: [String: WindowEntry] = [:]
        var workspaceScreens: [String: Int] = [:]
        for window in MacWindow.allWindows {
            guard let workspace = window.nodeWorkspace else { continue }
            windows[String(window.windowId)] = WindowEntry(
                workspace: workspace.name,
                bundleId: window.macApp.bundleId,
            )
            if workspaceScreens[workspace.name] == nil {
                workspaceScreens[workspace.name] = workspace.workspaceMonitor.monitorAppKitNsScreenScreensId
            }
        }
        return CheapKey(windows: windows, workspaceScreens: workspaceScreens)
    }

    /// The full state. `MonitorFingerprint.fromScreen` is four CoreGraphics round trips per monitor
    /// and the monitor list is rebuilt on every access, so this is only reached when `cheapKey`
    /// says something actually changed.
    private static func fullState(_ key: CheapKey) -> State {
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
        return State(session: session(), windows: key.windows, workspaceMonitors: monitors)
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
        let work = {
            guard let data = try? JSONEncoder().encode(state) else { return }
            try? data.write(to: url, options: .atomic)
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
    static func forceSessionForTests(_ value: String) { cachedSession = value }

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
        lastWritten = nil
        isLoaded = false
        isFrozen = false
        fileUrlOverride = nil
        cachedSession = nil
    }
}
