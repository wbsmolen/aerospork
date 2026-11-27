import AppKit
import Common

@MainActor let scratchpadContainer = ScratchpadContainer()
/// The windows `move-node-to-scratchpad` put away, parked off screen until `scratchpad` shows one. Global, like
/// `macosMinimizedWindowsContainer`: it hangs off no workspace, so no workspace enumeration (`list-workspaces`, the
/// menu bar, `next`/`prev`, the stubs, the rearrange, the memory, the collection) ever sees it.
class ScratchpadContainer: TreeNode, NonLeafTreeNodeObject {
    @MainActor
    fileprivate init() {
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }
}

/// The scratchpad windows by id: the ones in `scratchpadContainer`, and the ones `scratchpad` shows, which float on a
/// workspace until they go back. Not cleared when a window is collected, for the reason `stickyWindowIds` gives: the
/// lock screen collects live windows, and registration puts them back by this set.
@MainActor var scratchpadWindowIds: Set<UInt32> = []

extension Window {
    @MainActor var isScratchpad: Bool {
        get { scratchpadWindowIds.contains(windowId) }
        set { if newValue { scratchpadWindowIds.insert(windowId) } else { scratchpadWindowIds.remove(windowId) } }
    }

    /// Puts the window away: off its workspace and into the scratchpad, where the next layout parks it. It keeps no
    /// away place, and comes back floating at `lastFloatingSize`, so a floating window's size now is that size.
    @MainActor
    func moveToScratchpad() async throws {
        if isFloating { lastFloatingSize = try await getAxSize() ?? lastFloatingSize }
        isSticky = false // sticky and scratchpad are exclusive: following the screen would show it again
        isFullscreen = false // it comes back at its floating size
        isScratchpad = true
        scratchpadWindowsPutAwayWhileNamed.insert(windowId)
        bind(to: scratchpadContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
    }

    /// Shows a scratchpad window on `workspace`: floating, centred on its monitor at `lastFloatingSize`. A minimized
    /// one is unminimized first, and comes from wherever it was.
    @MainActor
    func showFromScratchpad(on workspace: Workspace) async throws {
        if parent is MacosMinimizedWindowsContainer { try await exitMacosMinimizedOrHidden() }
        bindAsFloatingWindow(to: workspace)
        // Not where it was parked: `unhideFromCorner` would put it back where it was when it went away.
        (self as? MacWindow)?.parkedPosition = nil
        let visibleRect = workspace.workspaceMonitor.visibleRect
        let size = if let lastFloatingSize { lastFloatingSize } else { try await getAxSize() }
        if let size {
            setAxFrame(centredOnMonitor(visibleRect, size), size)
        }
    }

    /// Where a window still in the scratchpad goes when AeroSpork stops parking it, at quit or `enable off`: centred
    /// on the main monitor at its floating size, as `scratchpad` shows it. Not where it was put away: after a crash,
    /// a forced quit or the lock screen, the window registers again while parked, and its "unparked" spot is the
    /// corner, which would leave it off screen for good.
    @MainActor var onScreenFrameOutsideTheScratchpad: (topLeft: CGPoint, size: CGSize)? {
        guard parent is ScratchpadContainer else { return nil }
        let visibleRect = mainMonitor.visibleRect
        let size = lastFloatingSize ?? CGSize(width: visibleRect.width / 2, height: visibleRect.height / 2)
        return (centredOnMonitor(visibleRect, size), size)
    }

    /// The monitor a parked window goes back to: its workspace's. A window in the scratchpad has no workspace, so the
    /// main monitor, which is where the quit cleanup and `enable off` put it.
    @MainActor var unparkedMonitor: Monitor? {
        nodeWorkspace?.workspaceMonitor ?? (parent is ScratchpadContainer ? mainMonitor : nil)
    }

    /// Where a background tab of this window's group waits: with this window, out of sight.
    @MainActor var backgroundTabHome: NonLeafTreeNodeObject? {
        parent is ScratchpadContainer ? scratchpadContainer : nodeWorkspace?.macOsNativeHiddenAppsWindowsContainer
    }
}

/// Parks every window in the scratchpad, against the focused monitor, as `layoutWorkspaces` parks a hidden
/// workspace's windows. An empty container is the whole cost for anyone who does not use the scratchpad.
@MainActor
func parkScratchpadWindows(monitors: [Monitor], onlyUnparked: Bool) async throws {
    if scratchpadContainer.children.isEmpty { return }
    let monitor = focus.workspace.workspaceMonitor
    let others = monitors.map(\.rect).filter { $0.topLeftCorner != monitor.rect.topLeftCorner }
    for window in scratchpadContainer.children.compactMap({ $0 as? MacWindow }) where shouldPark(
        inNativeFullscreen: false,
        isBackgroundTab: window.isBackgroundTab,
        isParked: window.isHiddenInCorner,
        onlyUnparked: onlyUnparked,
    ) {
        try await window.hideInCorner(on: monitor.visibleRect, otherMonitors: others)
    }
}
