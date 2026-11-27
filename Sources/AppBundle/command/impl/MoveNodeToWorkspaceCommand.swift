import Common

struct MoveNodeToWorkspaceCommand: Command {
    let args: MoveNodeToWorkspaceCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        let subjectWs = window.nodeWorkspace
        let targetWorkspace: Workspace
        switch args.target.val {
            case .relative(let nextPrev):
                guard let subjectWs else { return io.err("Window \(window.windowId) doesn't belong to any workspace") }
                let ws = getNextPrevWorkspace(
                    current: subjectWs,
                    isNext: nextPrev == .next,
                    wrapAround: args.wrapAround,
                    stdin: io.readStdin(),
                    target: target,
                )
                guard let ws else { return io.err("Can't resolve next or prev workspace") }
                targetWorkspace = ws
            case .direct(let name):
                targetWorkspace = Workspace.get(byName: name.raw)
        }
        return moveWindowToWorkspace(window, targetWorkspace, io, focusFollowsWindow: args.focusFollowsWindow, failIfNoop: args.failIfNoop)
    }
}

@MainActor
func moveWindowToWorkspace(_ window: Window, _ targetWorkspace: Workspace, _ io: CmdIo, focusFollowsWindow: Bool, failIfNoop: Bool, index: Int = INDEX_BIND_LAST) -> Bool {
    // macOS owns a native-fullscreen or hidden-app window: binding it into the target's tiles would give
    // the target a tile for a window in its own Space (or hidden), and leave a stale away slot behind.
    // Refused like `move` refuses it. A rule on a brand-new window is unaffected: registration binds it
    // into the tiles, and only a later refresh hands it to macOS.
    if window.parent is MacosFullscreenWindowsContainer || window.parent is MacosHiddenAppsWindowsContainer {
        return io.err(moveOutMacosUnconventionalWindow)
    }
    if window.nodeWorkspace == targetWorkspace {
        io.err(noopMessage("Window '\(window.windowId)' already belongs to workspace '\(targetWorkspace.name)'.", failIfNoop: failIfNoop))
        return !failIfNoop
    }
    // Sent somewhere on purpose: following the screen would take it straight back.
    window.isSticky = false
    let targetContainer: NonLeafTreeNodeObject = window.isFloating ? targetWorkspace : targetWorkspace.rootTilingContainer
    window.bind(to: targetContainer, adaptiveWeight: WEIGHT_AUTO, index: index)
    // A completed move is a success whether or not focus was asked to follow it. This used to
    // `return focusFollowsWindow ? … : false`, so the default `move-node-to-workspace <name>` --
    // the single most common command in an i3-style config -- exited 1, with no message, every
    // time it worked. `move-node-to-monitor` hardcoded `focusFollowsWindow: true` to dodge that,
    // which is why its own `--focus-follows-window` flag had nothing left to do.
    guard focusFollowsWindow else { return true }
    return window.focusWindow()
}
