import AppKit
import Common

struct FocusMonitorCommand: Command {
    let args: FocusMonitorCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        return switch args.target.val.resolve(target.workspace.workspaceMonitor, wrapAround: args.wrapAround) {
            case .success(let targetMonitor): targetMonitor.activeWorkspace.focusWorkspace()
            case .failure(let msg): io.err(msg)
        }
    }
}

// MonitorTarget.resolve() and Monitor helper extensions moved to MonitorResolution.swift
