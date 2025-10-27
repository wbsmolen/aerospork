import AppKit
import Common

struct FullscreenCommand: Command {
    let args: FullscreenCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = requireWindow(from: target, io) else { return false }

        let newState = resolveToggle(args.toggle, current: window.isFullscreen)

        if newState == window.isFullscreen {
            let message = newState ? "Already fullscreen." : "Already not fullscreen."
            return handleNoop(message, failIfNoop: args.failIfNoop, io: io)
        }

        window.isFullscreen = newState
        window.noOuterGapsInFullscreen = args.noOuterGaps

        // Focus on its own workspace
        window.markAsMostRecentChild()
        return true
    }
}
