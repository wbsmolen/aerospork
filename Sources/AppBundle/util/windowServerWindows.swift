import AppKit
import Common

/// Every window WindowServer still has, by id, whatever its app's Accessibility lists: background native tabs,
/// a hidden app's windows, every tab of a minimized group, `sharingType = .none` windows, and windows on other
/// Spaces are all on it until the window is destroyed (probed on macOS 27.2). About 1.5 ms, so never per refresh:
/// `WorkspaceMemory.fullState` and the 30 s sweep only.
///
/// Empty under test, where a real window's id could match a made-up one. `nil` when the read fails: WindowServer
/// always lists some window (the menu bar, the Dock), so an empty list is a failed read too.
func windowServerWindowIds() -> Set<UInt32>? {
    if isUnitTest { return [] }
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[CFString: Any]] else { return nil }
    let ids = Set(list.compactMap { ($0[kCGWindowNumber] as? Int).map(UInt32.init) })
    return ids.isEmpty ? nil : ids
}

/// The registered windows WindowServer no longer has. `registered` must be read before `alive`, so every id in it
/// existed before the snapshot, and ids are never reused within a WindowServer session: absence is proof of death.
///
/// Nothing when `alive` is `nil` or empty: a failure to look is not proof that anything died. Background tabs are
/// left out though the probe found them listed, because losing one is a lost place.
func windowsGoneFromWindowServer(registered: Set<UInt32>, alive: Set<UInt32>?, backgroundTabs: [UInt32: UInt32]) -> Set<UInt32> {
    guard let alive, !alive.isEmpty else { return [] }
    return registered.subtracting(alive).filter { backgroundTabs[$0] == nil }
}

/// Whether the session reports the screen locked. A query, not a flag kept from lock and unlock notifications,
/// which one missed unlock would leave stuck. About 0.3 ms, so read only when the answer changes something.
func screenIsLocked() -> Bool {
    if isUnitTest { return false }
    return (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] != nil
}

/// While the screen is locked, Accessibility can go blank and every window looks closed, so only WindowServer's word
/// that a window is gone counts. The rest wait for the first refresh after unlock, when a dead one is gone for good.
func shouldCollect(_ windowId: UInt32, provenDead: Set<UInt32>, screenIsLocked: Bool) -> Bool {
    !screenIsLocked || provenDead.contains(windowId)
}
