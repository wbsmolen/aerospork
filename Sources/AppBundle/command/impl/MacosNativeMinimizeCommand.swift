import AppKit
import Common

/// See: MacosNativeFullscreenCommand. Problem ID-B6E178F2
struct MacosNativeMinimizeCommand: Command {
    let args: MacosNativeMinimizeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        // resolveTargetOrReportError on already minimized windows will alwyas fail
        // It would be easier if minimized windows were part of the workspace in tree hierarchy
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = requireWindow(from: target, io) else { return false }
        let newState: Bool = try await !window.isMacosMinimized
        window.asMacWindow().setNativeMinimized(newState)
        if newState { // minimize
            // Record where it came from BEFORE binding. `macosMinimizedWindowsContainer` is global,
            // so once the window is in it the tree no longer knows its workspace -- and
            // `normalizeLayoutReason` would then stamp `nil` and restore it to whatever workspace
            // happened to be focused later. cmd-M and the Dock go through `normalizeLayoutReason`,
            // which records it correctly, so without this the same user action performed through the
            // CLI behaved differently from the same action performed with the mouse.
            if let parent = window.parent {
                window.layoutReason = .macos(prevParentKind: parent.kind, prevWorkspaceName: window.nodeWorkspace?.name)
            }
            window.bind(to: macosMinimizedWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            return true
        } else { // unminimize
            return io.err("The command is uncapable of unminimizing windows yet. Sorry") // dead code. should never be possible, see the comment above
        }
    }
}
