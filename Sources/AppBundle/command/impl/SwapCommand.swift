import AppKit
import Common

struct SwapCommand: Command {
    let args: SwapCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard var window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        // A background tab's group is one tile, which its selected tab holds.
        if let selected = backgroundTabs[window.windowId].flatMap({ Window.get(byId: $0) }) { window = selected }
        guard window.parent is TilingContainer else { return io.err("swap works only on tiling windows") }

        let other: Window?
        if let direction = args.target.val.direction {
            if let (parent, ownIndex) = window.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                other = parent.children[ownIndex + direction.focusOffset].findFocusTargetRecursive(snappedTo: direction.opposite)
            } else {
                other = args.wrapAround ? target.workspace.findFocusTargetRecursive(snappedTo: direction.opposite) : nil
            }
        } else {
            // The leaf order `focus --dfs-index` counts in.
            let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
            guard let own = windows.firstIndex(of: window) else { return false }
            let next = own + (args.target.val == .dfsNext ? 1 : -1)
            other = args.wrapAround ? windows.get(wrappingIndex: next) : windows.getOrNil(atIndex: next)
        }
        guard let other, other != window else { return io.err("No window to swap with in that direction") }

        swapWindows(window, other)
        if args.swapFocus { return other.focusWindow() }
        window.markAsMostRecentChild() // `bind` left the other one most recent
        return true
    }
}
