import AppKit
import Common

/// See: MacosNativeFullscreenCommand. Problem ID-B6E178F2
struct MacosNativeMinimizeCommand: Command {
    let args: MacosNativeMinimizeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        // A minimized window hangs off a global container, so resolving a target fails on it. Only
        // `--window-id` can name one, and for that one this command is the way back.
        if let windowId = args.windowId, let window = Window.get(byId: windowId), case .macosMinimizedWindowsContainer? = window.parent?.cases {
            try await window.exitMacosMinimizedOrHidden()
            return true
        }
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
            window.leaveTilesForMacos(macosMinimizedWindowsContainer, adaptiveWeight: 1)
            return true
        } else { // unminimize
            return true
        }
    }
}
