import AppKit
import Common

struct SummonWorkspaceCommand: Command {
    let args: SummonWorkspaceCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let workspace = Workspace.get(byName: args.target.val.raw)
        let monitor = focus.workspace.workspaceMonitor
        if monitor.activeWorkspace == workspace {
            return handleNoop("Workspace '\(workspace.name)' is already visible on the focused monitor.", failIfNoop: args.failIfNoop, io: io)
        }
        if monitor.setActiveWorkspace(workspace) {
            return workspace.focusWorkspace()
        } else {
            return io.err("Can't move workspace '\(workspace.name)' to monitor '\(monitor.name)'. workspace-to-monitor-force-assignment doesn't allow it")
        }
    }
}
