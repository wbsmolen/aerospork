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
            // A disabled server answers nothing but `enable`, and a stream would otherwise sit silent.
            EventBroadcaster.shared.removeAll(sending: serverAnswer(
                ExitCode.failure,
                stderr: "\(aeroSporkAppName) server was disabled. Run 'aerospork enable on', then subscribe again",
            ))
        }
        return true
    }
}
