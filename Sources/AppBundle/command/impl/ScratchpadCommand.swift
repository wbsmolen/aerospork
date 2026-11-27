import AppKit
import Common

struct ScratchpadCommand: Command {
    let args: ScratchpadCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let focus = focus
        if let window = focus.windowOrNil, window.isScratchpad, window.isFloating, matches(window) {
            try await window.moveToScratchpad()
            return true
        }
        guard let window = candidate(on: focus.workspace) else {
            return io.err(args.appBundleId.map { "No scratchpad window of \($0)" } ?? "The scratchpad is empty")
        }
        if window.nodeWorkspace != focus.workspace { try await window.showFromScratchpad(on: focus.workspace) }
        return window.focusWindow()
    }

    /// One already on this workspace, then the one put away most recently, then one shown on another workspace.
    @MainActor
    private func candidate(on workspace: Workspace) -> Window? {
        let shown = scratchpadWindowIds.sorted().compactMap { Window.get(byId: $0) }
            .filter { matches($0) && ($0.isFloating || $0.parent is MacosMinimizedWindowsContainer) }
        if let here = shown.first(where: { $0.nodeWorkspace == workspace }) { return here }
        let stowed = scratchpadContainer.childrenInMruOrder.compactMap { $0 as? Window }.filter { matches($0) && !$0.isBackgroundTab }
        return stowed.first ?? shown.first
    }

    @MainActor
    private func matches(_ window: Window) -> Bool {
        args.appBundleId.map { $0 == window.app.bundleId } ?? true
    }
}
