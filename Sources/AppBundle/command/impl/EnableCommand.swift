import AppKit
import Common

struct EnableCommand: Command {
    let args: EnableCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let prevState = TrayMenuModel.shared.isEnabled
        let newState = resolveToggle(args.targetState.val, current: prevState)

        if newState == prevState {
            let message = newState ? "Already enabled" : "Already disabled"
            return handleNoop(message, failIfNoop: args.failIfNoop, io: io)
        }

        TrayMenuModel.shared.isEnabled = newState
        if newState {
            for workspace in Workspace.all {
                for window in workspace.allLeafWindowsRecursive where window.isFloating {
                    window.lastFloatingSize = try await window.getAxSize() ?? window.lastFloatingSize
                }
            }
            activateMode(mainModeId)
        } else {
            activateMode(nil)
        }
        return true
    }
}
