import AppKit
import Common

struct MoveWorkspaceToMonitorCommand: Command {
    let args: MoveWorkspaceToMonitorCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        let focusedWorkspace = target.workspace
        let prevMonitor = focusedWorkspace.workspaceMonitor

        switch args.target.val.resolve(target.workspace.workspaceMonitor, wrapAround: args.wrapAround) {
            case .success(let targetMonitor):
                if targetMonitor.monitorId == prevMonitor.monitorId {
                    return true
                }
                if targetMonitor.setActiveWorkspace(focusedWorkspace) {
                    return true // the monitor it was visible on, if any, got its stub in there
                } else {
                    return io.err(
                        "Can't move workspace '\(focusedWorkspace.name)' to monitor '\(targetMonitor.name)'. workspace-to-monitor-force-assignment doesn't allow it",
                    )
                }
            case .failure(let msg):
                return io.err(msg)
        }
    }
}
