import Common
import Foundation

/// Remembers which workspace each window was on, so an AeroSpork restart does not scatter them.
///
/// ## Why this is needed at all
///
/// Workspaces are emulated, not native Spaces: a hidden workspace's windows are parked off screen.
/// Nothing outside this process knows that a window "belongs to" workspace `A`. At launch a window
/// is bound by where it physically sits (`MacWindow.getOrRegister`), and at a cold start no
/// workspace is active yet, so `getStubWorkspace` invents one per monitor from the first keybound
/// name in sort order. `A` sorts after every digit, so a window left on `A` could never come back to
/// it -- it reappeared on `1` or `3`. That is structural, not chance.
///
/// ## Why `CGWindowID` alone, and nothing cleverer
///
/// The id comes from the WindowServer, and Apple documents it as "a unique value **within the user
/// session**". So it is *exactly* stable across a restart of AeroSpork -- the case this exists for,
/// since our process lifetime means nothing to the WindowServer -- and worthless once the owning app
/// restarts or the machine reboots.
///
/// A composite key (bundle id + title + index + frame) would appear to cover the app-restart case
/// and cannot. `AXIdentifier` names a window *class*, not an instance: every Terminal window reports
/// `TerminalWindowRestoration`, every Finder window `FinderWindow` -- the `axDumps/` fixtures show it.
/// Titles change when a tab does, the index into `kAXWindowsAttribute` is z-order, and the frame is
/// overwritten by our own quit cleanup. Three identical terminal windows are genuinely
/// indistinguishable, so a composite key would shuffle them into an arbitrary permutation, silently
/// and untestably. An exact id match cannot be wrong; it can only be absent.
///
/// So every failure here degrades to "behaves like it did before", never to "puts the window
/// somewhere wrong". Where the id is gone, `on-window-detected` with
/// `if.during-aerospork-startup` is the right tool, because there the user states intent instead of
/// us guessing.
///
/// ## Why the boot time is in the file
///
/// Ids are unique *within a session*, which means they are recycled across boots. Without the guard
/// a stale file could match a live window that happens to have inherited an old id and move it
/// somewhere the user never put it -- the one way this design could produce a wrong answer rather
/// than no answer. `kern.boottime` is exact and costs one `sysctl`.
@MainActor
enum WorkspaceMemory {
    private struct Entry: Codable {
        let workspace: String
        /// Checked against the live window's app. A recycled id landing on a different application
        /// is the residual risk the boot guard does not already remove; this makes it a no-op.
        let bundleId: String?
    }

    private struct State: Codable {
        let bootTime: Double
        let windows: [String: Entry]
    }

    /// Alongside the CLI socket, and deliberately nowhere near the config: this is a disposable
    /// cache, and `ConfigurationWriter`'s do-no-harm invariant must not be dragged into it.
    private static var fileUrl: URL {
        URL(filePath: "/tmp/\(aeroSporkAppId)-\(unixUserName).state.json")
    }

    /// Seconds since the epoch at which the machine last booted. Not `ProcessInfo.systemUptime`,
    /// which is a duration and behaves differently across sleep.
    private static var bootTime: Double {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
        return Double(tv.tv_sec)
    }

    /// Loaded once, at startup, before any window is registered. `nil` means "no usable memory",
    /// which is the same as never having run.
    private static var restored: [String: Entry]?

    /// Reads the file if it belongs to this boot. Call once, early.
    static func load() {
        restored = nil
        guard let data = try? Data(contentsOf: fileUrl),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return }
        // A file from a previous boot describes ids that no longer mean anything.
        guard state.bootTime == bootTime else {
            debugLog("WorkspaceMemory: discarding state from a previous boot")
            try? FileManager.default.removeItem(at: fileUrl)
            return
        }
        restored = state.windows
        debugLog("WorkspaceMemory: restored \(state.windows.count) entries")
    }

    /// The workspace this window was on last run, if we can be certain it is the same window.
    static func workspace(forWindowId id: UInt32, bundleId: String?) -> String? {
        guard let entry = restored?[String(id)] else { return nil }
        // A nil bundle id on either side is not a match: unknown is not the same as equal.
        guard let remembered = entry.bundleId, let bundleId, remembered == bundleId else { return nil }
        return entry.workspace
    }

    /// Snapshots the current tree. Cheap enough for the refresh debounce: a dictionary walk and a
    /// small JSON write, on the order of the window count.
    static func save() {
        var windows: [String: Entry] = [:]
        for window in MacWindow.allWindows {
            guard let workspace = window.nodeWorkspace else { continue }
            windows[String(window.windowId)] = Entry(workspace: workspace.name, bundleId: window.macApp.bundleId)
        }
        let state = State(bootTime: bootTime, windows: windows)
        guard let data = try? JSONEncoder().encode(state) else { return }
        // Written on every debounced refresh rather than only at quit, because a crash never
        // reaches the quit path -- and a crash is when this is worth the most.
        try? data.write(to: fileUrl, options: .atomic)
    }
}
