import AppKit
import Common

struct ResizeCommand: Command {
    let args: ResizeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        if let window = target.windowOrNil, window.isFloating {
            guard target.workspace.isVisible else { return io.err(floatingWindowIsParked) }
            return try await resizeFloating(window, on: target.workspace)
        }

        let candidates = target.windowOrNil?.parentsWithSelf
            .filter { ($0.parent as? TilingContainer)?.layout == .tiles }
            ?? []

        let orientation: Orientation?
        let parent: TilingContainer?
        let node: TreeNode?
        switch args.dimension.val {
            case .width:
                orientation = .h
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .height:
                orientation = .v
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .smart:
                node = candidates.first
                parent = node?.parent as? TilingContainer
                orientation = parent?.orientation
            case .smartOpposite:
                orientation = (candidates.first?.parent as? TilingContainer)?.orientation.opposite
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
        }
        guard let parent else { return io.err(target.windowOrNil == nil ? noWindowIsFocused : "This window isn't in a tiles layout, so it has no size of its own to change") }
        guard let orientation else { return false }
        guard let node else { return false }
        target.workspace.denominateWeightsInPoints()
        let diff: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit) - node.getWeight(orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }

        guard let childDiff = diff.div(parent.children.count - 1) else { return false }
        parent.children.lazy
            .filter { $0 != node }
            .forEach { $0.setWeight(parent.orientation, $0.getWeight(parent.orientation) - childDiff) }

        node.setWeight(orientation, node.getWeight(orientation) + diff)
        return true
    }

    /// There is no parent to take the size from, so this is just the window's own. `smart` is its width
    /// and `smart-opposite` its height, since a floating window has no orientation to go by. Kept on its
    /// monitor, which is another workspace's screen past the edge.
    @MainActor
    private func resizeFloating(_ window: Window, on workspace: Workspace) async throws -> Bool {
        guard let rect = try await window.getAxRect() else { return false }
        let isWidth = switch args.dimension.val {
            case .width, .smart: true
            case .height, .smartOpposite: false
        }
        let current = isWidth ? rect.width : rect.height
        let wanted: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit)
            case .add(let unit): current + CGFloat(unit)
            case .subtract(let unit): current - CGFloat(unit)
        }
        let monitor = workspace.workspaceMonitor.visibleRect
        let size = isWidth
            ? CGSize(width: max(1, min(wanted, monitor.width)), height: rect.height)
            : CGSize(width: rect.width, height: max(1, min(wanted, monitor.height)))
        window.lastFloatingSize = size
        window.setAxFrame(keptInside(monitor, rect.topLeftCorner, size), size)
        return true
    }
}
