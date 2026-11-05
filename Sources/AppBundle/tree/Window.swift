import AppKit
import Common

class Window: TreeNode, Hashable {
    // `nonisolated` dropped: it was redundant. `UInt32` is Sendable and `Window` is not an
    // isolated type, so a `let` of it is already reachable from `hash(into:)` and friends.
    let windowId: UInt32
    let app: any AbstractApp
    var lastFloatingSize: CGSize?
    var isFullscreen: Bool = false
    var noOuterGapsInFullscreen: Bool = false
    var layoutReason: LayoutReason = .standard
    /// The smallest size the app was seen to accept (0 on an axis nothing was learned about). Layout
    /// gives the window at least this, so a tile narrower than the app allows is planned around rather
    /// than overflowed. See `noteRefusedSize`.
    var observedMinSize: CGSize?

    @MainActor
    init(id: UInt32, _ app: any AbstractApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.windowId = id
        self.app = app
        self.lastFloatingSize = lastFloatingSize
        super.init(parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static func get(byId windowId: UInt32) -> Window? { // todo make non optional
        isUnitTest
            ? Workspace.all.flatMap { $0.allLeafWindowsRecursive }.first(where: { $0.windowId == windowId })
            : MacWindow.allWindowsMap[windowId]
    }

    @MainActor
    func closeAxWindow() { die("Not implemented") }

    /// The app answered a resize to `asked` with the larger `got`: it will not go that small. Only ever
    /// raised. Returns whether anything was learned, i.e. whether the tiles need re-splitting.
    /// ponytail: never lowered -- a window whose minimum later shrinks keeps the old one until it closes.
    @MainActor
    func noteRefusedSize(asked: CGSize, got: CGSize) -> Bool {
        let old = observedMinSize ?? .zero
        let new = CGSize(
            width: got.width > asked.width + 1 ? max(old.width, got.width) : old.width,
            height: got.height > asked.height + 1 ? max(old.height, got.height) : old.height,
        )
        if new == old { return false }
        observedMinSize = new
        return true
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(windowId)
    }

    // Still required on Swift 6.2 -- checked by deleting these three and rebuilding: 4 errors.
    // Not a "drop it in a future version" note until someone re-runs that experiment.
    @MainActor
    func getAxTopLeftCorner() async throws -> CGPoint? { die("Not implemented") }
    @MainActor
    func getAxSize() async throws -> CGSize? { die("Not implemented") }
    @MainActor
    var title: String { get async throws { die("Not implemented") } }
    @MainActor
    var isMacosFullscreen: Bool { get async throws { false } }
    @MainActor
    var isMacosMinimized: Bool { get async throws { false } }
    /// Both native-state flags in one round trip. Overridden by `MacWindow`; the default composes
    /// the two properties so test doubles need not implement it.
    @MainActor
    func macosNativeState() async throws -> (fullscreen: Bool, minimized: Bool) {
        let full = try await isMacosFullscreen
        return (full, full ? false : (try await isMacosMinimized))
    } // todo replace with enum MacOsWindowNativeState { normal, fullscreen, invisible }
    /// Is this window's app hidden (cmd-H)? A member rather than `macAppUnsafe.nsApp.isHidden` at the
    /// call site so `normalizeLayoutReason`'s hidden-app branch is reachable from a test double.
    @MainActor
    var isMacosAppHidden: Bool { macAppUnsafe.nsApp.isHidden }
    /// Drawn fully transparent by WindowServer; see `transparentWindowIds`. A member for the same reason.
    @MainActor
    var isTransparent: Bool { transparentWindowIds.contains(windowId) }
    var isHiddenInCorner: Bool { die("Not implemented") }
    @MainActor
    func nativeFocus() { die("Not implemented") }
    @MainActor
    func getAxRect() async throws -> Rect? { die("Not implemented") }
    @MainActor
    func getCenter() async throws -> CGPoint? { try await getAxRect()?.center }

    func setAxTopLeftCorner(_ point: CGPoint) { die("Not implemented") }
    func setAxFrameBlocking(_ topLeft: CGPoint?, _ size: CGSize?) async throws { die("Not implemented") }
    func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) { die("Not implemented") }
    func setSizeAsync(_ size: CGSize) { die("Not implemented") }
}

enum LayoutReason: Equatable {
    case standard
    /// Reason for the cur temp layout is macOS native fullscreen, minimize, or hide
    ///
    /// `prevWorkspaceName` is carried because `macosMinimizedWindowsContainer` is global -- it hangs
    /// off `NilTreeNode`, not off a workspace -- so once a window is minimized the tree no longer
    /// records where it came from. Restoring used `focus.workspace`, which teleported a window
    /// minimized on one workspace onto whichever one happened to be focused when it came back.
    /// Nil for a window whose parent had no workspace to begin with (a popup).
    case macos(prevParentKind: NonLeafTreeNodeKind, prevWorkspaceName: String?)
}

extension Window {
    /// "Floating" is not stored state -- it's just "bound directly to the workspace instead of to a
    /// tiling container". That holds for every parent kind we have today. `sticky` (a window pinned
    /// across all workspaces) would break it, but sticky is not implemented and not planned, so
    /// there is nothing to design around yet.
    var isFloating: Bool { parent is Workspace }

    @discardableResult
    @MainActor
    func bindAsFloatingWindow(to workspace: Workspace) -> BindingData? {
        bind(to: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }

    func asMacWindow() -> MacWindow { self as! MacWindow }
}
