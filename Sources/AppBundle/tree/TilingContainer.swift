import AppKit
import Common

class TilingContainer: TreeNode, NonLeafTreeNodeObject {
    fileprivate var _orientation: Orientation
    var orientation: Orientation { _orientation }
    var layout: Layout
    /// See `layoutTiles`.
    var lastLaidOutChildren: Set<ObjectIdentifier>?
    /// Windows that belong in this container but have no tile right now. See `AwayWindow`.
    var awayWindows: [AwayWindow] = []

    @MainActor
    init(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, _ orientation: Orientation, _ layout: Layout, index: Int) {
        self._orientation = orientation
        self.layout = layout
        super.init(parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor
    static func newHTiles(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) -> TilingContainer {
        TilingContainer(parent: parent, adaptiveWeight: adaptiveWeight, .h, .tiles, index: index)
    }

    @MainActor
    static func newVTiles(parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) -> TilingContainer {
        TilingContainer(parent: parent, adaptiveWeight: adaptiveWeight, .v, .tiles, index: index)
    }
}

/// A window macOS has taken out of the tiles, minimized, hidden with its app or in native fullscreen, or
/// one that isn't back yet after a restart. It comes back to its place at its share of the split, however
/// many others left and in whatever order they return.
///
/// `after` names what preceded it rather than an index, because an index goes stale the moment a window
/// opens or closes. `share` is of the whole sequence, away windows included, so that returning first or
/// last gives the same split.
struct AwayWindow: Equatable {
    let id: UInt32
    let share: CGFloat
    let after: [UInt32]
}

extension TilingContainer {
    @MainActor private var liveWeight: CGFloat { CGFloat(children.sumOfDouble { $0.getWeight(orientation) }) }
    private var awayShare: CGFloat { awayWindows.reduce(0) { $0 + $1.share } }

    /// Call while `window` is still a child of this container.
    @MainActor
    func noteAway(_ window: Window) {
        guard let own = window.ownIndex else { return }
        let sequence = sequenceIncludingAway()
        let position = sequence.firstIndex { $0.window == window.windowId } ?? own
        let share = liveWeight > 0 ? window.getWeight(orientation) / liveWeight * (1 - awayShare) : 0
        awayWindows.append(AwayWindow(id: window.windowId, share: share, after: sequence[..<position].flatMap(\.windowIds)))
    }

    /// Takes the window's place back: where to bind it, or nil if it has none here.
    @MainActor
    func takeAwaySlot(of id: UInt32) -> BindingData? {
        guard let i = awayWindows.firstIndex(where: { $0.id == id }) else {
            for case let child as TilingContainer in children {
                if let slot = child.takeAwaySlot(of: id) { return slot }
            }
            return nil
        }
        let away = awayWindows.remove(at: i)
        let previous = children.lastIndex { child in child.allLeafWindowsRecursive.contains { away.after.contains($0.windowId) } }
        let others = 1 - awayShare - away.share
        return BindingData(
            parent: self,
            adaptiveWeight: liveWeight > 0 && others > 0 && away.share > 0 ? liveWeight * away.share / others : WEIGHT_AUTO,
            index: previous.map { $0 + 1 } ?? 0,
        )
    }

    /// Children and away windows in order. An away window goes after the last thing it came after.
    @MainActor
    func sequenceIncludingAway() -> [(windowIds: [UInt32], window: UInt32?, node: TreeNode?)] {
        var sequence: [(windowIds: [UInt32], window: UInt32?, node: TreeNode?)] = children.map { child in
            (child.allLeafWindowsRecursive.map(\.windowId), (child as? Window)?.windowId, child)
        }
        for away in awayWindows {
            let previous = sequence.lastIndex { $0.windowIds.contains(where: away.after.contains) }
            sequence.insert(([away.id], away.id, nil), at: previous.map { $0 + 1 } ?? 0)
        }
        return sequence
    }

    /// What `share` is a share of, in points. The away windows' weights in a frozen tree are in this unit.
    @MainActor var sequenceWeight: CGFloat { awayShare < 1 && liveWeight > 0 ? liveWeight / (1 - awayShare) : 1 }

    /// The window is gone for good.
    @MainActor
    func forgetAway(_ isGone: (UInt32) -> Bool) {
        awayWindows.removeAll { isGone($0.id) }
        for case let child as TilingContainer in children { child.forgetAway(isGone) }
    }

    /// Called as this container empties and is removed, so its away windows keep a place. Not this
    /// container: an empty one would hold an empty tile. They come back side by side at its position.
    @MainActor
    func handAwayWindowsToParent() {
        guard !awayWindows.isEmpty, let parent = parent as? TilingContainer, let own = ownIndex else { return }
        let preceding = parent.children[..<own].flatMap { $0.allLeafWindowsRecursive.map(\.windowId) }
        let ownShare = parent.liveWeight > 0 ? getWeight(parent.orientation) / parent.liveWeight * (1 - parent.awayShare) : 0
        for away in awayWindows {
            parent.awayWindows.append(AwayWindow(id: away.id, share: away.share * ownShare, after: preceding + away.after))
        }
    }

    var isRootContainer: Bool { parent is Workspace }

    @MainActor
    func changeOrientation(_ targetOrientation: Orientation) {
        if orientation == targetOrientation {
            return
        }
        if config.enableNormalizationOppositeOrientationForNestedContainers {
            var orientation = targetOrientation
            parentsWithSelf
                .filterIsInstance(of: TilingContainer.self)
                .forEach {
                    $0._orientation = orientation
                    orientation = orientation.opposite
                }
        } else {
            _orientation = targetOrientation
        }
    }

    func normalizeOppositeOrientationForNestedContainers() {
        if orientation == (parent as? TilingContainer)?.orientation {
            _orientation = orientation.opposite
        }
        for child in children {
            (child as? TilingContainer)?.normalizeOppositeOrientationForNestedContainers()
        }
    }
}

enum Layout: String, Codable {
    case tiles
    case accordion
}

extension String {
    func parseLayout() -> Layout? {
        if let parsed = Layout(rawValue: self) {
            return parsed
        } else if self == "list" {
            return .tiles
        } else {
            return nil
        }
    }
}
