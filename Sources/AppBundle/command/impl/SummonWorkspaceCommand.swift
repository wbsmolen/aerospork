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
        let displaced = monitor.activeWorkspace
        let vacated = workspace.isVisible ? workspace.workspaceMonitor : nil
        if monitor.setActiveWorkspace(workspace) {
            // The two trade monitors, so nothing that was on screen disappears. A force-assigned
            // `displaced` can't go there; the stub `setActiveWorkspace` put there then stays.
            if let vacated { _ = vacated.setActiveWorkspace(displaced) }
            return workspace.focusWorkspace()
        } else {
            return io.err("Can't move workspace '\(workspace.name)' to monitor '\(monitor.name)'. [monitors] pins it to another monitor")
        }
    }
}
