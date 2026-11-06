import AppKit
import Common

extension Workspace {
    @MainActor
    func layoutWorkspace() async throws {
        if isEffectivelyEmpty { return }
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        // Use the whole rect. This was `rect.height - 1` from the initial import -- a 1px dead row at
        // the bottom of every workspace, meant to stop a frame exactly filling the monitor, which
        // upstream believed macOS sometimes refused ("monitors aligned vertically and the monitor
        // below has smaller width ... ¯\_(ツ)_/¯"). There is nothing to defend against. Measured on
        // macOS 26 across exactly that geometry (1512x982 built-in stacked below a 3840x2160, plus a
        // 5120x1440 main and a second 3840x2160): NSWindow.constrainFrameRect(_:to:) -- the clamp
        // AppKit applies inside setFrame:display: -- grants a frame that exactly fills visibleFrame
        // on every monitor, and full width survives with and without the row. Reading the live
        // windows back showed each one landing byte-exactly where layout asked, Electron (Discord)
        // and Chromium (Edge) included, so it is not app-specific either. The belief that the
        // 3840x2160 panels "refuse the top 30pt" was a measurement artifact: NSScreen.visibleFrame
        // only reports the menu-bar inset once NSApp exists, so a probe that skipped that read
        // visibleFrame == frame and mistook the menu bar for a clamp.
        try await layoutRecursive(rect.topLeftCorner, width: rect.width, height: rect.height, virtual: rect, LayoutContext(self))
    }
}

extension TreeNode {
    @MainActor
    fileprivate func layoutRecursive(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        switch nodeCases {
            case .workspace(let workspace):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                try await workspace.rootTilingContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
                for window in workspace.children.filterIsInstance(of: Window.self) {
                    window.lastAppliedLayoutPhysicalRect = nil
                    window.lastAppliedLayoutVirtualRect = nil
                    try await window.layoutFloatingWindow(context)
                }
            case .window(let window):
                if window.windowId != currentlyManipulatedWithMouseWindowId {
                    lastAppliedLayoutVirtualRect = virtual
                    // Fullscreen is window state, not focus state. It used to be applied only while
                    // the window was the workspace's mostRecentWindowRecursive, and cleared
                    // otherwise -- so focusing any other window silently un-fullscreened it. Only
                    // FullscreenCommand may flip the flag now.
                    if window.isFullscreen {
                        lastAppliedLayoutPhysicalRect = nil
                        window.layoutFullscreen(context)
                    } else {
                        lastAppliedLayoutPhysicalRect = physicalRect
                        let tile = CGSize(width: width, height: height)
                        let size = window.observedMinSize.map { CGSize(width: max(width, $0.width), height: max(height, $0.height)) } ?? tile
                        let monitor = context.workspace.workspaceMonitor.visibleRect
                        window.setAxFrame(size == tile ? point : keptInside(monitor, point, size), size)
                    }
                }
            case .tilingContainer(let container):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                switch container.layout {
                    case .tiles:
                        try await container.layoutTiles(point, width: width, height: height, virtual: virtual, context)
                    case .accordion:
                        try await container.layoutAccordion(point, width: width, height: height, virtual: virtual, context)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return // Nothing to do for weirdos
        }
    }
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        let workspace = context.workspace
        let rect = try await getAxRect()
        let currentMonitor = rect?.center.monitorApproximation // Probably not idempotent
        if let currentMonitor, let windowTopLeftCorner = rect?.topLeftCorner, workspace != currentMonitor.activeWorkspace {
            let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
            let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

            let moveTo = workspace.workspaceMonitor
            setAxTopLeftCorner(CGPoint(
                x: moveTo.visibleRect.topLeftX + xProportion * moveTo.visibleRect.width,
                y: moveTo.visibleRect.topLeftY + yProportion * moveTo.visibleRect.height,
            ))
        }
        if isFullscreen {
            // Don't clear the flag here. It used to be cleared right after applying the frame, which
            // made a floating fullscreen window un-fullscreen itself on the very next refresh.
            layoutFullscreen(context)
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}

/// `point`, moved just enough that a window of `size` there stays on the monitor. Only for a window
/// bigger than its tile: grown from its top-left it would hang off the edge -- onto the next monitor,
/// which is another workspace's screen.
func keptInside(_ monitor: Rect, _ point: CGPoint, _ size: CGSize) -> CGPoint {
    CGPoint(
        x: max(monitor.minX, min(point.x, monitor.maxX - size.width)),
        y: max(monitor.minY, min(point.y, monitor.maxY - size.height)),
    )
}

/// Each child's share of `total`: its weight, except that a child whose share is under its minimum gets
/// the minimum, and the rest give it up in proportion to their weights. When the minimums don't fit at
/// all, the plain proportional split stands, and layout keeps each oversize window on its monitor.
/// `weights` must already sum to `total`.
func distribute(_ weights: [CGFloat], minimums: [CGFloat], total: CGFloat) -> [CGFloat] {
    if zip(weights, minimums).allSatisfy({ $0 >= $1 }) || minimums.reduce(0, +) > total { return weights }
    var pinned = Set<Int>()
    while true {
        let free = total - pinned.reduce(0) { $0 + minimums[$1] }
        let unpinned = weights.indices.filter { !pinned.contains($0) }
        let unpinnedWeight = unpinned.reduce(0) { $0 + weights[$1] }
        let sizes = weights.indices.map { i in
            pinned.contains(i) ? minimums[i]
                : unpinnedWeight > 0 ? weights[i] * free / unpinnedWeight : free / CGFloat(unpinned.count)
        }
        let under = unpinned.filter { sizes[$0] < minimums[$0] }
        if under.isEmpty { return sizes }
        pinned.formUnion(under)
    }
}

extension TreeNode {
    /// The least this node can be drawn along `orientation`: the minimums its windows were seen to
    /// enforce (`Window.observedMinSize`) plus the gaps between them. 0 when nothing is known.
    @MainActor
    fileprivate func minimumSize(_ orientation: Orientation, innerGap: CGFloat) -> CGFloat {
        switch nodeCases {
            case .window(let window):
                return window.observedMinSize.map { orientation == .h ? $0.width : $0.height } ?? 0
            case .tilingContainer(let container):
                let mins = container.children.map { $0.minimumSize(orientation, innerGap: innerGap) }
                if mins.allSatisfy({ $0 == 0 }) { return 0 }
                if container.orientation != orientation { return mins.max() ?? 0 }
                return switch container.layout {
                    case .tiles: mins.reduce(0, +) + innerGap * CGFloat(mins.count - 1)
                    // A child gives up to twice the padding to the ones peeking out past it.
                    case .accordion: (mins.max() ?? 0) + (mins.count > 1 ? 2 * CGFloat(config.accordionPadding) : 0)
                }
            default:
                return 0
        }
    }
}

extension TilingContainer {
    @MainActor
    fileprivate func layoutTiles(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        var point = point
        var virtualPoint = virtual.topLeftCorner

        if children.isEmpty { return }
        // The row changed, so its windows are being re-split anyway. That makes it the moment to ask again
        // for less than a minimum on record, which may have come down since.
        let members = Set(children.map { ObjectIdentifier($0) })
        if let lastLaidOutChildren, lastLaidOutChildren != members {
            for case let window as Window in children { window.observedMinSize = nil }
        }
        lastLaidOutChildren = members
        // Weights are denominated in points, so whenever the container's real size stops matching the
        // sum of its children's weights -- a different monitor, a new sibling, a workspace moved --
        // the children have to be re-denominated before they can be rendered. Do it *proportionally*:
        // every child keeps its share of the parent, so nothing can cross zero however much the
        // container shrinks. This spread used to be additive -- the same `(size - sum) / count` came
        // off every child -- which on a much narrower monitor drove small children to a negative
        // weight and handed the AX API a negative size, i.e. a window that silently vanished. See
        // LayoutRecursiveTest.testNarrowerMonitorScalesInsteadOfCollapsingSmallWindows.
        let size = orientation == .h ? width : height
        let sum = CGFloat(children.sumOfDouble { $0.getWeight(orientation) })
        for child in children {
            // `sum <= 0` needs `resize` to have driven every weight to zero or below. There is no
            // ratio left to preserve then, so split evenly -- which is what the additive spread also
            // did when it started from a sum of zero.
            child.setWeight(orientation, sum > 0 ? child.getWeight(orientation) * size / sum : size / CGFloat(children.count))
        }
        // TRADEOFF: still a write-back from what is a render pass, but a harmless one -- it lands on
        // the same weights it just computed, so it converges in one pass and repeated layouts of an
        // unchanged tree agree to ~1 ULP (`Σ w * size / sum` doesn't re-sum to `size` exactly in
        // binary floating point, so frames wobble in their last bits forever;
        // LayoutRecursiveTest.testLayoutIsIdempotent allows a millipixel). Storing weights as
        // fractions of the parent would drop the write entirely, but it buys nothing a user can see:
        // `resize`, mouse-resize and balance-sizes are all denominated in points and would each need
        // the parent's point size to convert. Do it only if the write-back itself starts costing.

        let rawGap = context.resolvedGaps.inner.get(orientation).toDouble()
        let lastIndex = children.indices.last
        // Interior gaps are split in half between the two neighbours that share them, and the
        // container's outer edges get no gap at all (outer gaps are the monitor's job). So the
        // first and last child each give back half a gap, and every boundary between two
        // children ends up exactly `rawGap` wide. See LayoutRecursiveTest.testTilesHalfGapEdges.
        let gaps = children.indices.map { i in rawGap - (i == 0 ? rawGap / 2 : 0) - (i == lastIndex ? rawGap / 2 : 0) }
        // What is drawn, not the weights: a child the app won't shrink to its share gets its minimum
        // and its siblings give the difference up. The weights stay the user's proportions.
        let sizes = distribute(
            children.map { $0.getWeight(orientation) },
            minimums: children.indices.map { i in
                let min = children[i].minimumSize(orientation, innerGap: rawGap)
                return min > 0 ? min + gaps[i] : 0
            },
            total: size,
        )
        for (i, child) in children.enumerated() {
            try await child.layoutRecursive(
                i == 0 ? point : point.addingOffset(orientation, rawGap / 2),
                width: orientation == .h ? sizes[i] - gaps[i] : width,
                height: orientation == .v ? sizes[i] - gaps[i] : height,
                virtual: Rect(
                    topLeftX: virtualPoint.x,
                    topLeftY: virtualPoint.y,
                    width: orientation == .h ? sizes[i] : width,
                    height: orientation == .v ? sizes[i] : height,
                ),
                context,
            )
            virtualPoint = virtualPoint.addingOffset(orientation, sizes[i])
            point = point.addingOffset(orientation, sizes[i])
        }
    }

    @MainActor
    fileprivate func layoutAccordion(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        guard let mruIndex: Int = mostRecentChild?.ownIndex else { return }
        // Inner gaps are deliberately ignored in accordion. Accordion children all occupy (nearly)
        // the whole container and overlap by construction, so there is no space *between* siblings
        // for a gap to live in -- the only meaningful separation is `accordion-padding`. The gap a
        // user perceives *around* an accordion group is applied by its parent tiles container.
        // Pinned by LayoutRecursiveTest.testAccordionIgnoresInnerGaps.
        let padding = CGFloat(config.accordionPadding)
        for (index, child) in children.enumerated() {
            // Case order matters. The MRU child's neighbours must be matched before the generic
            // first/last cases: when the MRU neighbour happens to also be the last (or first) child,
            // the generic case used to win and the neighbour's far edge landed exactly on the MRU
            // child's edge instead of `padding` inside it.
            let (lPadding, rPadding): (CGFloat, CGFloat) = switch index {
                case 0 where children.count == 1: (0, 0)
                case mruIndex - 1:                (0, 2 * padding)
                case mruIndex + 1:                (2 * padding, 0)
                case 0:                           (0, padding)
                case children.indices.last:       (padding, 0)
                default:                          (padding, padding)
            }
            switch orientation {
                case .h:
                    try await child.layoutRecursive(
                        point + CGPoint(x: lPadding, y: 0),
                        width: width - rPadding - lPadding,
                        height: height,
                        virtual: virtual,
                        context,
                    )
                case .v:
                    try await child.layoutRecursive(
                        point + CGPoint(x: 0, y: lPadding),
                        width: width,
                        height: height - lPadding - rPadding,
                        virtual: virtual,
                        context,
                    )
            }
        }
    }
}
