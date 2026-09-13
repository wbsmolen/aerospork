import AppKit

@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

/// The window we asked macOS to focus, and how long we are willing to wait for it to agree.
@MainActor private var pendingNativeFocus: (windowId: UInt32, deadline: Date)? = nil

/// The last time macOS moved focus to another workspace on its own, and the window it moved us off.
///
/// `runRefreshSessionBlocking` adopts macOS's focus BEFORE `refresh()` collects dead windows. So when
/// the focused window dies and macOS keys a window on another workspace -- cmd-W in an app with
/// windows on several workspaces, cmd-Q when the next app's key window is on a hidden one -- the model
/// has already followed it by the time the death is seen, and `focusedWindowId` names the new window.
/// This is what lets `shouldRestoreFocusAfterDeath` still recognise the death as the cause.
///
/// Recorded only here, on an adopt. Commands and hotkeys move focus through `setFocus` directly and
/// never touch it, which is what keeps a window dying late behind a workspace switch the user asked
/// for from dragging them back.
@MainActor var focusAdoptedAwayFrom: (windowId: UInt32, workspaceName: String, date: Date)? = nil

/// How long a focus request stays authoritative. Long enough for an app to answer an activate
/// (Chromium-family apps are the slow ones), short enough that a request macOS silently drops
/// cannot wedge focus tracking. If it expires we go back to trusting macOS, which is the correct
/// failure mode: worst case the user gets today's behaviour.
///
/// The known cost of the bound: an app slower than this to answer has its request expire, so a
/// same-workspace `focus` into it can revert to the previous window and come forward again when the
/// app finally answers, firing `on-focus-changed` each way. Holding the request until the app
/// answers would trade that flicker for a focus lock -- every click into the window ignored while the
/// app is hung -- which is what `testAnUnacknowledgedRequestExpiresInsteadOfLockingFocus` prevents.
private let nativeFocusGrace: TimeInterval = 1.0

/// Both globals survive for the lifetime of the process, which is right for the app and wrong for a
/// test suite: `lastKnownNativeFocusedWindowId` left over from one test suppresses the adopt in the
/// next, so the tests would pass or fail depending on their order.
@MainActor func resetFocusCacheForTests() {
    lastKnownNativeFocusedWindowId = nil
    pendingNativeFocus = nil
    focusAdoptedAwayFrom = nil
}

/// Called by `MacApp.nativeFocus`. Until macOS reports this window focused, reports of *other*
/// windows are treated as our own request still in flight rather than as a user focus change.
@MainActor func expectNativeFocus(_ windowId: UInt32, deadline: Date = Date().addingTimeInterval(nativeFocusGrace)) {
    pendingNativeFocus = (windowId, deadline)
}

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    // A focus request we issued is still in flight. `MacApp.nativeFocus` raises the target window
    // and then calls `nsApp.activate`, both asynchronously on the app's thread; `runSession` starts
    // another refresh immediately afterwards. In that window an app can report a DIFFERENT window
    // of its own as focused -- typically its previous frontmost one -- and this function used to
    // adopt that as a genuine user focus change and move the model's focus to it.
    //
    // The visible symptom: `workspace 1` (two Edge windows) would land focus on the workspace
    // holding a THIRD Edge window, because activating Edge briefly reported that one. Focus, the
    // active workspace, and therefore `move-mouse` all followed it to the wrong monitor. Only
    // reproducible when the source and target workspaces share an app, which is why it read as
    // intermittent.
    if let pending = pendingNativeFocus {
        if nativeFocused?.windowId == pending.windowId {
            pendingNativeFocus = nil // macOS agreed; resume trusting it
        } else if Date() < pending.deadline {
            return // still in flight -- do not adopt, and do not record it as last known either
        } else {
            pendingNativeFocus = nil // gave up waiting; macOS wins
        }
    }
    // Two reasons to adopt, not one. The original test -- "macOS is reporting a different window
    // than last time" -- cannot fix a model that drifted while macOS's answer stayed put, and the
    // model does drift: `focus` is derived from the MRU, and any rebind moves it. `runSession` then
    // pushes that drift OUT to macOS, so the two disagree and neither side ever corrects the other.
    // Comparing against the model as well makes macOS the tiebreaker, which is the direction of
    // truth this function already documents. A request we issued is still protected by
    // `pendingNativeFocus` above.
    let macOsChangedItsMind = nativeFocused?.windowId != lastKnownNativeFocusedWindowId
    // Same workspace, and that qualifier carries the whole safety of this clause. macOS may correct
    // WHICH WINDOW is focused on the workspace the user is on; it may not, on drift alone, change
    // which workspace that is. `MacApp.nativeFocus` issues its AX writes asynchronously and
    // `pendingNativeFocus` guards them for only a second; past that, an app that has not answered yet
    // leaves macOS still naming a window on the workspace we just left. Adopting it drags the user
    // back, then forward again when the write lands -- a workspace switch that reads as delayed, or
    // as a bounce. So drift alone never moves the user across workspaces.
    //
    // That only holds if `lastKnownNativeFocusedWindowId` is not spent by a read the app never
    // answered. An unanswered read used to arrive here as `nil`, "no focused window", which recorded
    // nil -- and the app's next, stale answer then counted as `macOsChangedItsMind` and bounced the
    // user anyway. `syncFocusFromMacOs` keeps unanswered reads out of this function entirely.
    //
    // Focus on an EMPTY workspace while macOS goes on naming its last window needs no special case:
    // that window is on another workspace, and the clause below already rejects it. Where it is NOT on
    // another workspace -- a window appeared on the empty workspace the user is looking at and macOS
    // focused it -- adopting is the right answer.
    let theModelDrifted = nativeFocused?.windowId != focusedWindowId
        && nativeFocused?.visualWorkspace == focus.workspace
    if macOsChangedItsMind || theModelDrifted {
        let workspaceBefore = focus.workspace
        let windowBefore = focusedWindowId
        // Before the adopt: afterwards the target workspace is on screen by definition.
        let targetWasOnScreen = nativeFocused?.visualWorkspace?.isVisible ?? true
        // Record only what we actually ADOPTED. `focusWindow()` answers false for a window with no
        // `visualWorkspace`, and one occurs routinely: macOS reports a window it has just
        // un-minimized as focused during the SAME refresh whose `normalizeLayoutReason` -- which runs
        // later -- is what moves it out of the global minimized container. Recording it here spent
        // `macOsChangedItsMind` on an adopt that could not happen, so the retry never came. The
        // window ended up rebound to its own workspace, hidden in the corner by `layoutWorkspaces`
        // if that workspace was invisible, and still holding the keyboard -- with nothing left that
        // could reconcile the two. `!= false` keeps the nil case, "macOS reports no focused window",
        // recording exactly as before.
        if nativeFocused?.focusWindow() != false {
            lastKnownNativeFocusedWindowId = nativeFocused?.windowId
        }
        if focus.workspace != workspaceBefore {
            // A workspace switch is a layout change, and `closedWindowsCache` must not outlive one:
            // `restoreClosedWindowsCacheIfNeeded` reapplies every monitor's visible workspace from the
            // snapshot, so a stale cache silently undoes the switch when some window is re-detected
            // later. The existing resets cover commands and clicks; this is the switch nothing else
            // covers, because adopting macOS's focus happens inside `runRefreshSessionBlocking`.
            //
            // Here rather than in `setFocus`, which would look tidier and be wrong: `garbageCollect`
            // captures the cache and *then* calls `setFocus`, so resetting there can wipe the very
            // snapshot the later restore depends on.
            resetClosedWindowsCache()
            if let windowBefore {
                focusAdoptedAwayFrom = (windowBefore, workspaceBefore.name, .now)
            }
            // Only onto a workspace that was not on screen. Clicking a window on another monitor
            // changes the focused workspace too, dozens of times a day and always on purpose; macOS
            // pulling the user onto a HIDDEN workspace -- an app activating itself, the next key window
            // after a close -- is the rare, surprising case a "focus jumped" report is about.
            if !targetWasOnScreen {
                AppLog.session.notice("focus followed macOS to a hidden workspace: \(workspaceBefore.name, privacy: .public) -> \(focus.workspace.name, privacy: .public), window \(windowBefore ?? 0, privacy: .public) -> \(nativeFocused?.windowId ?? 0, privacy: .public)")
            }
        }
    }
}
