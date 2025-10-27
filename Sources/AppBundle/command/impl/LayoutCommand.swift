import AppKit
import Common

struct LayoutCommand: Command {
    let args: LayoutCmdArgs

    init(args: LayoutCmdArgs) {
        self.args = args
        debugLog("COMMAND: LayoutCommand initialized with args: \(args.toggleBetween.val)")
    }

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        debugLog("COMMAND: LayoutCommand starting - toggling between \(args.toggleBetween.val)")

        guard let target = args.resolveTargetOrReportError(env, io) else {
            debugLog("COMMAND: LayoutCommand failed - no target resolved")
            return false
        }
        guard let window = target.windowOrNil else {
            debugLog("COMMAND: LayoutCommand failed - no window focused")
            return io.err(noWindowIsFocused)
        }

        debugLog("COMMAND: Current window: \(window.windowId), parent: \(String(describing: window.parent))")
        let targetDescription = args.toggleBetween.val.first(where: { !window.matchesDescription($0) })
            ?? args.toggleBetween.val.first.orDie()

        debugLog("COMMAND: Target layout description: \(targetDescription)")

        if window.matchesDescription(targetDescription) {
            debugLog("COMMAND: Window already matches target layout \(targetDescription) - nothing to do")
            return true // Return true since the window is already in the desired state
        }
        debugLog("COMMAND: Switching to layout: \(targetDescription)")
        switch targetDescription {
            case .h_accordion:
                return changeTilingLayout(io, targetLayout: .accordion, targetOrientation: .h, window: window)
            case .v_accordion:
                return changeTilingLayout(io, targetLayout: .accordion, targetOrientation: .v, window: window)
            case .h_tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: .h, window: window)
            case .v_tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: .v, window: window)
            case .accordion:
                return changeTilingLayout(io, targetLayout: .accordion, targetOrientation: nil, window: window)
            case .tiles:
                return changeTilingLayout(io, targetLayout: .tiles, targetOrientation: nil, window: window)
            case .horizontal:
                return changeTilingLayout(io, targetLayout: nil, targetOrientation: .h, window: window)
            case .vertical:
                return changeTilingLayout(io, targetLayout: nil, targetOrientation: .v, window: window)
            case .tiling:
                guard let parent = window.parent else { return false }
                switch parent.cases {
                    case .macosPopupWindowsContainer:
                        return false // Impossible
                    case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
                        return io.err("Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps. This behavior is subject to change")
                    case .tilingContainer:
                        return true // Nothing to do
                    case .workspace(let workspace):
                        window.lastFloatingSize = try await window.getAxSize() ?? window.lastFloatingSize
                        try await window.relayoutWindow(on: workspace, forceTile: true)
                        return true
                }
            case .floating:
                let workspace = target.workspace
                window.bindAsFloatingWindow(to: workspace)
                if let size = window.lastFloatingSize { window.setSizeAsync(size) }
                return true
        }
    }
}

@MainActor private func changeTilingLayout(_ io: CmdIo, targetLayout: Layout?, targetOrientation: Orientation?, window: Window) -> Bool {
    debugLog("COMMAND: changeTilingLayout - targetLayout: \(String(describing: targetLayout)), targetOrientation: \(String(describing: targetOrientation))")

    guard let parent = window.parent else {
        debugLog("COMMAND: changeTilingLayout failed - window has no parent")
        return false
    }
    switch parent.cases {
        case .tilingContainer(let parent):
            let currentLayout = parent.layout
            let currentOrientation = parent.orientation
            let targetOrientation = targetOrientation ?? parent.orientation
            let targetLayout = targetLayout ?? parent.layout

            debugLog("COMMAND: Changing from \(currentLayout)/\(currentOrientation) to \(targetLayout)/\(targetOrientation)")

            parent.layout = targetLayout
            parent.changeOrientation(targetOrientation)

            // Mark workspace as needing layout after changing container layout
            if let workspace = parent.nodeWorkspace {
                workspace.markNeedsLayout()
            }

            // Trigger immediate refresh to apply layout changes
            Task { @MainActor in
                runRefreshSession(.hotkeyBinding, screenIsDefinitelyUnlocked: true, debounce: false)
            }

            debugLog("COMMAND: Layout change successful")
            return true
        case .workspace, .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
             .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
            debugLog("COMMAND: changeTilingLayout failed - window is non-tiling (parent: \(parent.cases))")
            return io.err("The window is non-tiling - it may be floating or in a special container")
    }
}

extension Window {
    fileprivate func matchesDescription(_ layout: LayoutCmdArgs.LayoutDescription) -> Bool {
        return switch layout {
            case .accordion:   (parent as? TilingContainer)?.layout == .accordion
            case .tiles:       (parent as? TilingContainer)?.layout == .tiles
            case .horizontal:  (parent as? TilingContainer)?.orientation == .h
            case .vertical:    (parent as? TilingContainer)?.orientation == .v
            case .h_accordion: (parent as? TilingContainer).map { $0.layout == .accordion && $0.orientation == .h } == true
            case .v_accordion: (parent as? TilingContainer).map { $0.layout == .accordion && $0.orientation == .v } == true
            case .h_tiles:     (parent as? TilingContainer).map { $0.layout == .tiles && $0.orientation == .h } == true
            case .v_tiles:     (parent as? TilingContainer).map { $0.layout == .tiles && $0.orientation == .v } == true
            case .tiling:      parent is TilingContainer
            case .floating:    parent is Workspace
        }
    }
}
