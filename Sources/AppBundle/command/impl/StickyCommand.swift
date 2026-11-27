import AppKit
import Common

struct StickyCommand: Command {
    let args: StickyCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = requireWindow(from: target, io) else { return false }

        let newState = resolveToggle(args.toggle, current: window.isSticky)
        if newState == window.isSticky {
            return handleNoop(newState ? "Already sticky." : "Already not sticky.", failIfNoop: args.failIfNoop, io: io)
        }
        if newState {
            // A sticky window is floating: `followVisibleWorkspaces` moves only floating windows.
            switch window.parent?.cases {
                case .workspace: break
                case .tilingContainer:
                    guard let workspace = window.nodeWorkspace else { return false }
                    window.bindAsFloatingWindow(to: workspace)
                    if let size = window.lastFloatingSize { window.setSizeAsync(size) }
                default:
                    return io.err("Can't make a minimized or macOS fullscreen window, or a window of a hidden app, sticky")
            }
        }
        window.isSticky = newState
        if newState { window.isScratchpad = false } // following the screen and being put away are exclusive
        return true
    }
}
