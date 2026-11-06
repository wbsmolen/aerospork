import AppKit
import Common

struct ModeCommand: Command {
    let args: ModeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let target = args.targetMode.val
        // Reported rather than falling back: whoever typed this has a typo to hear about, and
        // `activateMode`'s fallback would look like the command worked.
        guard config.modes[target] != nil else { return io.err("The config has no mode '\(target)'") }
        activateMode(target)
        return true
    }
}
