import AppKit
import Common

enum FrozenTreeNode: Sendable, Codable, Equatable {
    case container(FrozenContainer)
    case window(FrozenWindow)
}

/// A weight is compared to the point. Layout re-splits weights on every pass and they wobble in their last
/// bits, so exact equality would call every refresh a change, and `WorkspaceMemory` would rewrite its file.
private func sameWeight(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1 }

struct FrozenContainer: Sendable, Codable, Equatable {
    let children: [FrozenTreeNode]
    let layout: Layout
    let orientation: Orientation
    let weight: CGFloat

    init(children: [FrozenTreeNode], layout: Layout, orientation: Orientation, weight: CGFloat) {
        self.children = children
        self.layout = layout
        self.orientation = orientation
        self.weight = weight
    }

    static func == (a: FrozenContainer, b: FrozenContainer) -> Bool {
        a.layout == b.layout && a.orientation == b.orientation && sameWeight(a.weight, b.weight) && a.children == b.children
    }

    var allWindowIds: [UInt32] {
        children.flatMap { child -> [UInt32] in
            switch child {
                case .window(let window): [window.id]
                case .container(let container): container.allWindowIds
            }
        }
    }

    @MainActor init(_ container: TilingContainer) {
        children = container.children.map {
            switch $0.nodeCases {
                case .window(let w): .window(FrozenWindow(w))
                case .tilingContainer(let c): .container(FrozenContainer(c))
                case .workspace,
                     .macosMinimizedWindowsContainer,
                     .macosHiddenAppsWindowsContainer,
                     .macosFullscreenWindowsContainer,
                     .macosPopupWindowsContainer:
                    illegalChildParentRelation(child: $0, parent: container)
            }
        }
        layout = container.layout
        orientation = container.orientation
        weight = getWeightOrNil(container) ?? 1
    }
}

struct FrozenWindow: Sendable, Codable, Equatable {
    let id: UInt32
    let weight: CGFloat

    init(id: UInt32, weight: CGFloat) {
        self.id = id
        self.weight = weight
    }

    static func == (a: FrozenWindow, b: FrozenWindow) -> Bool { a.id == b.id && sameWeight(a.weight, b.weight) }

    @MainActor init(_ window: Window) {
        id = window.windowId
        weight = getWeightOrNil(window) ?? 1
    }
}

@MainActor private func getWeightOrNil(_ node: TreeNode) -> CGFloat? {
    ((node.parent as? TilingContainer)?.orientation).map { node.getWeight($0) }
}
