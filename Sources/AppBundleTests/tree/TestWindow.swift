@testable import AppBundle
import AppKit

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?

    @MainActor
    private init(_ id: UInt32, _ parent: NonLeafTreeNodeObject, _ adaptiveWeight: CGFloat, _ rect: Rect?) {
        _rect = rect
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: adaptiveWeight, index: INDEX_BIND_LAST)
    }

    @discardableResult
    @MainActor
    static func new(id: UInt32, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat = 1, rect: Rect? = nil) -> TestWindow {
        let wi = TestWindow(id, parent, adaptiveWeight, rect)
        TestApp.shared._windows.append(wi)
        return wi
    }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    @MainActor
    override func nativeFocus() {
        appForTests = TestApp.shared
        TestApp.shared.focusedWindow = self
    }

    override func closeAxWindow() {
        unbindFromParent()
    }

    override var title: String { description }

    /// What macOS would say about this window. `normalizeLayoutReason` is the only production path
    /// that rebinds windows on an ordinary refresh, and it is driven entirely by this pair -- so
    /// without a seam it cannot be exercised headlessly at all.
    /// nil is an app that did not answer.
    @MainActor var nativeState: (fullscreen: Bool, minimized: Bool)? = (false, false)

    @MainActor override func macosNativeState() async throws -> (fullscreen: Bool, minimized: Bool) {
        nativeState ?? nativeStateTheTreeRecords(for: self) // what `MacWindow` answers for a timed-out read
    }
    @MainActor var appHidden = false
    @MainActor override var isMacosAppHidden: Bool { appHidden }

    @MainActor override func getAxRect() async throws -> Rect? { // todo change to not Optional
        _rect
    }
}
