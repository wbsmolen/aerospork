import AppKit
import Common

struct MoveNodeToScratchpadCommand: Command {
    let args: MoveNodeToScratchpadCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        // A window in the scratchpad hangs off no workspace, so resolving a target fails on it. Only an id names one.
        if let id = args.windowId ?? env.windowId, let window = Window.get(byId: id), window.parent is ScratchpadContainer {
            return handleNoop("Window \(id) is already in the scratchpad.", failIfNoop: args.failIfNoop, io: io)
        }
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = requireWindow(from: target, io) else { return false }
        switch window.parent?.cases {
            case .workspace, .tilingContainer: break
            default: return io.err("Can't put a minimized or macOS fullscreen window, or a window of a hidden app, in the scratchpad")
        }
        try await window.moveToScratchpad()
        return true
    }
}
