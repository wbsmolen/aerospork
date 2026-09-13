import AppKit
import Common

final class MacWindow: Window {
    let macApp: MacApp
    private var prevUnhiddenProportionalPositionInsideWorkspaceRect: CGPoint?

    @MainActor
    private init(_ id: UInt32, _ actor: MacApp, lastFloatingSize: CGSize?, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat, index: Int) {
        self.macApp = actor
        super.init(id: id, actor, lastFloatingSize: lastFloatingSize, parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    @MainActor static var allWindowsMap: [UInt32: MacWindow] = [:]
    @MainActor static var allWindows: [MacWindow] { Array(allWindowsMap.values) }

    @MainActor
    @discardableResult
    static func getOrRegister(windowId: UInt32, macApp: MacApp) async throws -> MacWindow {
        if let existing = allWindowsMap[windowId] { return existing }
        let rect = try await macApp.getAxRect(windowId)
        let data = try await unbindAndGetBindingDataForNewWindow(
            windowId,
            macApp,
            // Startup consults the memory; a mid-session registration does not, and deliberately.
            // `WorkspaceMemory`'s map is read from disk once in `load()` and never updated, so it
            // answers "where this window was at launch" -- a window the user has moved since would
            // be dragged back. The case it would otherwise have covered, a live window collected by
            // mistake and then re-detected, is removed at the source by `AxUiElementMock.isDestroyed`.
            // If it ever needs covering again, the sound key is the workspace at the moment of
            // collection, not the one on disk.
            isStartup
                // Where this window was before the restart, when it is provably the same window.
                // Location is the fallback, not the first answer: at a cold start no workspace is
                // active, so that branch resolves to a stub invented from the first keybound name in
                // sort order -- which a named workspace like `A` can never be.
                ? WorkspaceMemory.restoredWorkspace(forWindowId: windowId, bundleId: macApp.bundleId)
                    ?? (rect?.center.monitorApproximation ?? mainMonitor).activeWorkspace
                : focus.workspace,
            window: nil,
        )

        // atomic synchronous section
        if let existing = allWindowsMap[windowId] { return existing }
        let window = MacWindow(windowId, macApp, lastFloatingSize: rect?.size, parent: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
        allWindowsMap[windowId] = window

        // Committed: from here the window is registered, and no refresh looks at it as new again. So
        // the rest runs to the end even if this refresh is cancelled; see `shieldedFromCancellation`.
        try await shieldedFromCancellation {
            try await debugWindowsIfRecording(window)
            if try await !restoreClosedWindowsCacheIfNeeded(newlyDetectedWindow: window) {
                try await tryOnWindowDetected(window)
            }
        }
        // A window that arrives looking like a popup is re-checked by `validateStillPopups` -- but only
        // when something refreshes, and an app still drawing its first window (Electron) may send
        // nothing more. Two bounded looks, so it is laid out and its rules run without a click (#40).
        if case .macosPopupWindowsContainer = window.parent?.cases {
            scheduleFollowUpRefresh(after: 1, "popupRecheck")
            scheduleFollowUpRefresh(after: 3, "popupRecheck")
        }
        return window
    }

    @MainActor
    func isWindowHeuristic() async throws -> Bool { // todo cache
        try await macApp.isWindowHeuristic(windowId)
    }

    @MainActor
    func isDialogHeuristic() async throws -> Bool { // todo cache
        try await macApp.isDialogHeuristic(windowId)
    }

    @MainActor
    func getAxUiElementWindowType() async throws -> AxUiElementWindowType {
        try await macApp.getAxUiElementWindowType(windowId)
    }

    @MainActor
    func dumpAxInfo() async throws -> [String: Json] {
        try await macApp.dumpWindowAxInfo(windowId: windowId)
    }

    func setNativeFullscreen(_ value: Bool) {
        macApp.setNativeFullscreen(windowId, value)
    }

    func setNativeMinimized(_ value: Bool) {
        macApp.setNativeMinimized(windowId, value)
    }

    // skipClosedWindowsCache is an optimization when it's definitely not necessary to cache closed window.
    //                        If you are unsure, it's better to pass `false`
    @MainActor
    func garbageCollect(skipClosedWindowsCache: Bool) {
        if MacWindow.allWindowsMap.removeValue(forKey: windowId) == nil {
            return
        }
        if !skipClosedWindowsCache { cacheClosedWindowIfNeeded(window: self) }
        let parent = unbindFromParent().parent
        let deadWindowWorkspace = parent.nodeWorkspace
        let focus = focus
        // See `shouldRestoreFocusAfterDeath`. The old test was "the dead window was on the focused
        // workspace", which moved the user whenever ANY window died there -- including one that only
        // looked dead, before the `isDestroyed()` fix above.
        if shouldRestoreFocusAfterDeath(of: windowId, on: deadWindowWorkspace), let deadWindowWorkspace {
            switch parent.cases {
                case .tilingContainer, .workspace, .macosHiddenAppsWindowsContainer, .macosFullscreenWindowsContainer:
                    let deadWindowFocus = deadWindowWorkspace.toLiveFocus()
                    _ = setFocus(to: deadWindowFocus)
                    let successor = deadWindowFocus.windowOrNil?.windowId ?? 0
                    AppLog.session.notice("focus moved by window death: \(self.windowId, privacy: .public) (\(self.app.bundleId ?? "?", privacy: .public)) died on \(deadWindowWorkspace.name, privacy: .public), focus -> \(successor, privacy: .public)")
                    // Guard against "Apple Reminders popup" bug: https://github.com/wbsmolen/aerospork/issues/201
                    // -- which is about focus still being on the dead window's workspace. When macOS
                    // has already moved us to another workspace, `focus` is a window over there, often
                    // of the SAME app (cmd-W in Chrome keys Chrome's next window), and skipping the push
                    // on the pid alone left the keyboard on a window parked off screen.
                    if focus.workspace != deadWindowWorkspace || focus.windowOrNil?.app.pid != app.pid {
                        // Force focus to fix macOS annoyance with focused apps without windows.
                        //   https://github.com/wbsmolen/aerospork/issues/65
                        deadWindowFocus.windowOrNil?.nativeFocus()
                    }
                case .macosPopupWindowsContainer, .macosMinimizedWindowsContainer:
                    break // Don't switch back on popup destruction
            }
        }
    }

    @MainActor override var title: String { get async throws { try await macApp.getAxTitle(windowId) ?? "" } }
    @MainActor override var isMacosFullscreen: Bool { get async throws { try await macApp.isMacosNativeFullscreen(windowId) == true } }
    @MainActor override var isMacosMinimized: Bool { get async throws { try await macApp.isMacosNativeMinimized(windowId) == true } }
    @MainActor override func macosNativeState() async throws -> (fullscreen: Bool, minimized: Bool) {
        // Unanswered is not "neither": see `nativeStateTheTreeRecords`.
        try await macApp.macosNativeState(windowId) ?? nativeStateTheTreeRecords(for: self)
    }

    @MainActor
    override func nativeFocus() {
        macApp.nativeFocus(windowId)
    }

    override func closeAxWindow() {
        garbageCollect(skipClosedWindowsCache: true)
        macApp.closeAndUnregisterAxWindow(windowId)
    }

    // todo it's part of the window layout and should be moved to layoutRecursive.swift
    @MainActor
    func hideInCorner(_ corner: OptimalHideCorner) async throws {
        guard let nodeMonitor else { return }
        // Don't accidentally override prevUnhiddenEmulationPosition in case of subsequent
        // `hideEmulation` calls
        if !isHiddenInCorner {
            guard let windowRect = try await getAxRect() else { return }
            let topLeftCorner = windowRect.topLeftCorner
            let monitorRect = windowRect.center.monitorApproximation.rect // Similar to layoutFloatingWindow. Non idempotent
            let absolutePoint = topLeftCorner - monitorRect.topLeftCorner
            prevUnhiddenProportionalPositionInsideWorkspaceRect =
                CGPoint(x: absolutePoint.x / monitorRect.width, y: absolutePoint.y / monitorRect.height)
        }
        let p: CGPoint
        switch corner {
            case .bottomLeftCorner:
                guard let s = try await getAxSize() else { fallthrough }
                // Zoom will jump off if you do one pixel offset https://github.com/wbsmolen/aerospork/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.isZoom ? .zero : CGPoint(x: 1, y: -1)
                p = nodeMonitor.visibleRect.bottomLeftCorner + onePixelOffset + CGPoint(x: -s.width, y: 0)
            case .bottomRightCorner:
                // Zoom will jump off if you do one pixel offset https://github.com/wbsmolen/aerospork/issues/527
                // todo this ad hoc won't be necessary once I implement optimization suggested by Zalim
                let onePixelOffset = macApp.isZoom ? .zero : CGPoint(x: 1, y: 1)
                p = nodeMonitor.visibleRect.bottomRightCorner - onePixelOffset
        }
        setAxTopLeftCorner(p)
    }

    @MainActor
    func unhideFromCorner() {
        guard let prevUnhiddenProportionalPositionInsideWorkspaceRect else { return }
        guard let nodeWorkspace else { return } // hiding only makes sense for workspace windows
        guard let parent else { return }

        switch getChildParentRelation(child: self, parent: parent) {
            // Just a small optimization to avoid unnecessary AX calls for non floating windows
            // Tiling windows should be unhidden with layoutRecursive anyway
            case .floatingWindow:
                let workspaceRect = nodeWorkspace.workspaceMonitor.rect
                let pointInsideWorkspace = CGPoint(
                    x: workspaceRect.width * prevUnhiddenProportionalPositionInsideWorkspaceRect.x,
                    y: workspaceRect.height * prevUnhiddenProportionalPositionInsideWorkspaceRect.y,
                )
                setAxTopLeftCorner(workspaceRect.topLeftCorner + pointInsideWorkspace)
            case .macosNativeFullscreenWindow, .macosNativeHiddenAppWindow, .macosNativeMinimizedWindow,
                 .macosPopupWindow, .tiling, .rootTilingContainer, .shimContainerRelation: break
        }

        self.prevUnhiddenProportionalPositionInsideWorkspaceRect = nil
    }

    override var isHiddenInCorner: Bool {
        prevUnhiddenProportionalPositionInsideWorkspaceRect != nil
    }

    @MainActor
    override func getAxSize() async throws -> CGSize? {
        try await macApp.getAxSize(windowId)
    }

    override func setAxTopLeftCorner(_ point: CGPoint) {
        macApp.setAxTopLeftCorner(windowId, point)
    }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        macApp.setAxFrame(windowId, topLeft, size)
    }

    @MainActor
    override func setAxFrameBlocking(_ topLeft: CGPoint?, _ size: CGSize?) async throws {
        try await macApp.setAxFrameBlocking(windowId, topLeft, size)
    }

    override func setSizeAsync(_ size: CGSize) {
        macApp.setAxSize(windowId, size)
    }

    override func getAxTopLeftCorner() async throws -> CGPoint? {
        try await macApp.getAxTopLeftCorner(windowId)
    }

    override func getAxRect() async throws -> Rect? {
        try await macApp.getAxRect(windowId)
    }
}

extension Window {
    @MainActor
    func relayoutWindow(on workspace: Workspace, forceTile: Bool = false) async throws {
        let data = forceTile
            ? unbindAndGetBindingDataForNewTilingWindow(workspace, window: self)
            : try await unbindAndGetBindingDataForNewWindow(self.asMacWindow().windowId, self.asMacWindow().macApp, workspace, window: self)
        bind(to: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index)
    }
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingDataForNewWindow(_ windowId: UInt32, _ macApp: MacApp, _ workspace: Workspace, window: Window?) async throws -> BindingData {
    switch try await macApp.getAxUiElementWindowType(windowId) {
        case .popup: BindingData(parent: macosPopupWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .dialog: BindingData(parent: workspace, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        case .window: unbindAndGetBindingDataForNewTilingWindow(workspace, window: window)
    }
}

// The function is private because it's unsafe. It leaves the window in unbound state
@MainActor
private func unbindAndGetBindingDataForNewTilingWindow(_ workspace: Workspace, window: Window?) -> BindingData {
    window?.unbindFromParent() // It's important to unbind to get correct data from below
    let mruWindow = workspace.mostRecentWindowRecursive
    if let mruWindow, let tilingParent = mruWindow.parent as? TilingContainer {
        return BindingData(
            parent: tilingParent,
            adaptiveWeight: WEIGHT_AUTO,
            index: mruWindow.ownIndex.orDie() + 1,
        )
    } else {
        return BindingData(
            parent: workspace.rootTilingContainer,
            adaptiveWeight: WEIGHT_AUTO,
            index: INDEX_BIND_LAST,
        )
    }
}

@MainActor
func tryOnWindowDetected(_ window: Window) async throws {
    guard let parent = window.parent else { return }
    switch parent.cases {
        case .tilingContainer, .workspace, .macosMinimizedWindowsContainer,
             .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
            try await onWindowDetected(window)
        case .macosPopupWindowsContainer:
            break
    }
}

@MainActor
private func onWindowDetected(_ window: Window) async throws {
    for callback in config.onWindowDetected where try await callback.matches(window) {
        _ = try await callback.run.runCmdSeq(.defaultEnv.copy(\.windowId, window.windowId), .emptyStdin)
        if !callback.checkFurtherCallbacks {
            return
        }
    }
}

extension WindowDetectedCallback {
    @MainActor
    func matches(_ window: Window) async throws -> Bool {
        if let startupMatcher = matcher.duringAeroSporkStartup, startupMatcher != isStartup {
            return false
        }
        if let regex = matcher.windowTitleRegexSubstring, !(try await window.title).contains(regex) {
            return false
        }
        if let appId = matcher.appId, appId != window.app.bundleId {
            return false
        }
        if let regex = matcher.appNameRegexSubstring, !(window.app.name ?? "").contains(regex) {
            return false
        }
        if let workspace = matcher.workspace, workspace != window.nodeWorkspace?.name {
            return false
        }
        return true
    }
}
