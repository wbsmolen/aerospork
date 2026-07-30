import AppKit
import Common

struct OpenSettingsCommand: Command {
    let args: OpenSettingsCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        // Goes through `\.openSettings`, captured by the menu bar label. This used to send the
        // private `showSettingsWindow:` selector, which on macOS 27 is still accepted by the
        // responder chain but no longer opens the window -- `sendAction` returned true, so this
        // guard passed and the command exited 0 having done nothing visible.
        guard openSettingsWindow() else {
            return io.err("Couldn't open the settings window")
        }
        return true
    }
}
