import AppKit
import Common

enum EffectiveLeaf {
    case window(Window)
    case emptyWorkspace(Workspace)
}
extension LiveFocus {
    var asLeaf: EffectiveLeaf {
        if let windowOrNil { .window(windowOrNil) } else { .emptyWorkspace(workspace) }
    }
}

/// This object should be only passed around but never memorized
/// Alternative name: ResolvedFocus
struct LiveFocus: AeroAny, Equatable {
    let windowOrNil: Window?
    var workspace: Workspace

    @MainActor var frozen: FrozenFocus {
        return FrozenFocus(
            windowId: windowOrNil?.windowId,
            workspaceName: workspace.name,
            monitorId: workspace.workspaceMonitor.monitorId ?? 0,
        )
    }
}

/// "old", "captured", "frozen in time" Focus
/// It's safe to keep a hard reference to this object.
/// Unlike in LiveFocus, information inside FrozenFocus isn't guaranteed to be self-consistent.
/// window - workspace - monitor relation could change since the object is created
struct FrozenFocus: AeroAny, Equatable, Sendable {
    let windowId: UInt32?
    let workspaceName: String
    // monitorId is not part of the focus. We keep it here only for 'on-monitor-changed' to work
    let monitorId: Int // 0-based

    @MainActor var live: LiveFocus { // Important: don't access focus.monitorId here. monitorId is not part of the focus. Always prefer workspace
        let window: Window? = windowId.flatMap { Window.get(byId: $0) }
        let workspace = Workspace.get(byName: workspaceName)

        let wsFocus = workspace.toLiveFocus()
        let wdFocus = window?.toLiveFocusOrNil() ?? wsFocus

        return wsFocus.workspace != wdFocus.workspace
            ? wsFocus // If window and workspace become separated prefer workspace
            : wdFocus
    }
}

@MainActor private var _focus: FrozenFocus = {
    let monitor = mainMonitor
    return FrozenFocus(windowId: nil, workspaceName: monitor.activeWorkspace.name, monitorId: monitor.monitorId ?? 0)
}()

/// Global focus.
/// Commands must be cautious about accessing this property directly. There are legitimate cases.
/// But, in general, commands must firstly check --window-id, --workspace, AEROSPORK_WINDOW_ID env and
/// AEROSPORK_WORKSPACE env before accessing the global focus.
@MainActor var focus: LiveFocus { _focus.live }

/// The window id focus was last *assigned* to, as opposed to the one `focus` derives now.
///
/// The two differ exactly when the model has drifted: `FrozenFocus.live` falls back to the
/// workspace's most-recent window whenever the stored id no longer resolves, so after
/// `MacWindow.garbageCollect` removes a window from `allWindowsMap`, `focus.windowOrNil` has
/// *already* moved on and cannot answer "was this the focused window?". This can.
@MainActor var focusedWindowId: UInt32? { _focus.windowId }

/// Should the death of `windowId`, last seen on `workspace`, move the user's focus?
///
/// Extracted from `MacWindow.garbageCollect`, which needs a real `MacApp`, so the decision behind
/// issue #39 can be tested headlessly.
///
/// `focusedWindowId`, not `focus.windowOrNil`, is the load-bearing half. By the time this is asked
/// the window is already out of `allWindowsMap`, so the derived focus has fallen back to the
/// workspace's most-recent window and can no longer say whether the dying window was the focused
/// one. Without that check, ANY window dying on the focused workspace re-pointed focus at
/// `mostRecentWindowRecursive ?? anyLeafWindowRecursive` and force-activated it -- and that "any leaf
/// window" fallback is where the reported randomness came from.
@MainActor func shouldRestoreFocusAfterDeath(of windowId: UInt32, on workspace: Workspace?) -> Bool {
    guard let workspace else { return false }
    if focusedWindowId == windowId { return workspace == focus.workspace }
    // The focused window died and macOS got there first: it keyed a window on another workspace, and
    // `updateFocusCache` -- which runs before `refresh()` collects the dead -- followed it, so
    // `focusedWindowId` already names that window. Without this the user is left over there, which
    // is what cmd-W did in an app with windows on several workspaces.
    //
    // Only a macOS-driven adopt records `focusAdoptedAwayFrom`. A workspace switch the user made goes
    // through `setFocus` and can never match, so a slow window closing behind a hotkey switch does not
    // drag the user back. Bounded at a second: an app slower than that to report the death leaves the
    // user where macOS put them.
    guard let away = focusAdoptedAwayFrom else { return false }
    return away.windowId == windowId && away.workspaceName == workspace.name && away.date.distance(to: .now) < 1
}

@MainActor func setFocus(to newFocus: LiveFocus) -> Bool {
    if _focus == newFocus.frozen { return true }
    let oldFocus = focus
    // Normalize mruWindow when focus away from a workspace
    if oldFocus.workspace != newFocus.workspace {
        oldFocus.windowOrNil?.markAsMostRecentChild()
    }

    _focus = newFocus.frozen
    let status = newFocus.workspace.workspaceMonitor.setActiveWorkspace(newFocus.workspace)

    newFocus.windowOrNil?.markAsMostRecentChild()
    return status
}
extension Window {
    @MainActor func focusWindow() -> Bool {
        if let focus = toLiveFocusOrNil() {
            return setFocus(to: focus)
        } else {
            // todo We should also exit-native-hidden/unminimize[/exit-native-fullscreen?] window if we want to fix ID-B6E178F2
            //      and retry to focus the window. Otherwise, it's not possible to focus minimized/hidden windows
            return false
        }
    }

    @MainActor func toLiveFocusOrNil() -> LiveFocus? { visualWorkspace.map { LiveFocus(windowOrNil: self, workspace: $0) } }
}
extension Workspace {
    @MainActor func focusWorkspace() -> Bool {
        setFocus(to: toLiveFocus())
    }

    func toLiveFocus() -> LiveFocus {
        // todo unfortunately mostRecentWindowRecursive may recursively reach empty rootTilingContainer
        //      while floating or macos unconventional windows might be presented.
        //      This should be addressed when robust handling for floating/special windows is implemented.
        if let wd = mostRecentWindowRecursive ?? anyLeafWindowRecursive {
            LiveFocus(windowOrNil: wd, workspace: self)
        } else {
            LiveFocus(windowOrNil: nil, workspace: self) // emptyWorkspace
        }
    }
}

@MainActor private var _lastKnownFocus: FrozenFocus = _focus

// Used by workspace-back-and-forth
@MainActor var _prevFocusedWorkspaceName: String? = nil
@MainActor var prevFocusedWorkspace: Workspace? { _prevFocusedWorkspaceName.map { Workspace.get(byName: $0) } }

// Used by focus-back-and-forth
@MainActor var _prevFocus: FrozenFocus? = nil
@MainActor var prevFocus: LiveFocus? { _prevFocus?.live.takeIf { $0 != focus } }

// Should be called in refreshSession
@MainActor func checkOnFocusChangedCallbacks() {
    if refreshSessionEvent?.isStartup == true {
        return
    }
    let focus = focus
    let frozenFocus = focus.frozen
    var hasFocusChanged = false
    var hasFocusedWorkspaceChanged = false
    var hasFocusedMonitorChanged = false
    if frozenFocus != _lastKnownFocus {
        _prevFocus = _lastKnownFocus
        hasFocusChanged = true
    }
    if frozenFocus.workspaceName != _lastKnownFocus.workspaceName {
        _prevFocusedWorkspaceName = _lastKnownFocus.workspaceName
        hasFocusedWorkspaceChanged = true
    }
    if frozenFocus.monitorId != _lastKnownFocus.monitorId {
        hasFocusedMonitorChanged = true
    }
    // Termination of the recursion below is provided by this assignment, not by a flag: the
    // runSession Tasks re-enter this function via refreshModel(), and by then _lastKnownFocus
    // already equals frozenFocus, so nothing fires and nothing is spawned. (The flag that used to
    // sit here was dead code -- its `defer` released it when this function RETURNED, which is
    // before any Task body runs, so it only ever guarded synchronous re-entry, which cannot occur.)
    _lastKnownFocus = frozenFocus

    if let _prevFocusedWorkspaceName, hasFocusedWorkspaceChanged {
        onWorkspaceChanged(_prevFocusedWorkspaceName, frozenFocus.workspaceName)
    }

    // One session for all of them. Each callback used to spawn its own `Task { runSession }`, and
    // runSession starts with `activeRefreshTask?.cancel()` followed by a fresh non-debounced
    // refresh -- so a workspace switch (which sets both hasFocusChanged and
    // hasFocusedWorkspaceChanged) had callback #2 cancel the refresh callback #1 had just started.
    var callbacks: [(RefreshSessionEvent, [any Command])] = []
    if hasFocusChanged, !config.onFocusChanged.isEmpty {
        callbacks.append((.onFocusChanged, config.onFocusChanged))
    }
    if hasFocusedWorkspaceChanged, !config.onFocusedWorkspaceChanged.isEmpty {
        callbacks.append((.onFocusedWorkspaceChanged, config.onFocusedWorkspaceChanged))
    }
    if hasFocusedMonitorChanged, !config.onFocusedMonitorChanged.isEmpty {
        callbacks.append((.onFocusedMonitorChanged, config.onFocusedMonitorChanged))
    }
    if callbacks.isEmpty { return }
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    // Captured now, not when the session body runs: by then the user may have switched again.
    let workspaceChange = hasFocusedWorkspaceChanged
        ? _prevFocusedWorkspaceName.map { (from: $0, to: frozenFocus.workspaceName) }
        : nil
    // todo potential optimization: don't run runSession if we are already in runSession
    runDetached("onFocusChangedCallbacks") {
        // The session is tagged with the first applicable event; the tag is only used for logging
        // and for `isStartup`, and none of these three are startup events.
        try await runSession(callbacks[0].0, token) {
            for (event, commands) in callbacks {
                var env = CmdEnv.defaultEnv.withFocus(focus)
                if case .onFocusedWorkspaceChanged = event { env.workspaceChange = workspaceChange }
                _ = try await commands.runCmdSeq(env, .emptyStdin)
            }
        }
    }
}

@MainActor private func onWorkspaceChanged(_ oldWorkspace: String, _ newWorkspace: String) {
    if let exec = config.execOnWorkspaceChange.first {
        let process = Process()
        process.executableURL = URL(filePath: exec)
        process.arguments = Array(config.execOnWorkspaceChange.dropFirst())
        process.environment = workspaceChangeEnvVars(config.execConfig.envVariables, from: oldWorkspace, to: newWorkspace)
        do {
            try process.run()
        } catch {
            // This was `.getOrDie()`. `exec-on-workspace-change` is a user-supplied path, so a typo,
            // a script without the executable bit, or a binary removed by a package upgrade all land
            // here -- and killing the window manager on every workspace switch is not a reasonable
            // answer to a config typo. Report it and keep switching workspaces.
            printStderr("exec-on-workspace-change: can't run '\(exec)': \(error.localizedDescription)")
        }
    }
}
