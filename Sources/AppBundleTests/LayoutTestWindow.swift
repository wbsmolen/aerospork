@testable import AppBundle
import AppKit

/// The seam that makes `layoutRecursive.swift` testable.
///
/// Layout's only outputs are AX writes, and `Window`'s AX members all `die("Not implemented")` in
/// the base class -- so `layoutWorkspace()` used to crash on the very first window in a headless
/// test. This subclass absorbs the writes and records them, which turns layout into something whose
/// output can be asserted. Only the four members layout actually touches are overridden.
///
/// Deliberately separate from `TestWindow`: existing tests never run layout and don't want the
/// recording, and layout reads a floating window's AX rect before writing it.
final class LayoutTestWindow: Window, CustomStringConvertible {
    /// Every frame layout asked for, oldest first. Laying out an unchanged tree is expected to be
    /// idempotent, so a second `layoutWorkspace()` appends the same rects again.
    private(set) var appliedFrames: [CGRect] = []
    /// The same sizes, unstandardized. `CGRect.width` is always positive -- it standardizes the rect
    /// on read -- so a bogus negative size layout hands to the AX API is invisible in `appliedFrames`
    /// (a -440pt width reads back as 440). Assert positive sizes against this, not against the rects.
    private(set) var appliedSizes: [CGSize] = []
    /// What layout reads back. Only consulted for floating windows.
    var axRect: Rect

    @MainActor
    private init(_ id: UInt32, _ parent: NonLeafTreeNodeObject, _ adaptiveWeight: CGFloat, _ axRect: Rect) {
        self.axRect = axRect
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: adaptiveWeight, index: INDEX_BIND_LAST)
    }

    @discardableResult
    @MainActor
    static func new(
        id: UInt32,
        parent: NonLeafTreeNodeObject,
        adaptiveWeight: CGFloat = 1,
        axRect: Rect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100),
    ) -> LayoutTestWindow {
        let window = LayoutTestWindow(id, parent, adaptiveWeight, axRect)
        TestApp.shared._windows.append(window)
        return window
    }

    /// The one frame layout applied in the current pass. Fails loudly if layout skipped the window
    /// or wrote it more than once -- both are bugs worth catching.
    @MainActor
    func singleAppliedFrame(file: String = #filePath, line: Int = #line) -> CGRect {
        assertEquals(appliedFrames.count, 1, additionalMsg: "\(self) frames: \(appliedFrames)", file: file, line: line)
        return appliedFrames.last ?? .null
    }

    @MainActor
    func resetRecording() {
        appliedFrames = []
        appliedSizes = []
    }

    nonisolated var description: String { "LayoutTestWindow(\(windowId))" }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        appliedFrames.append(CGRect(origin: topLeft ?? axRect.topLeftCorner, size: size ?? axRect.size))
        appliedSizes.append(size ?? axRect.size)
    }

    override func setAxTopLeftCorner(_ point: CGPoint) {
        appliedFrames.append(CGRect(origin: point, size: appliedFrames.last?.size ?? axRect.size))
        appliedSizes.append(appliedSizes.last ?? axRect.size)
    }

    @MainActor override var isMacosAppHidden: Bool { false }
    @MainActor override func getAxRect() async throws -> Rect? { axRect }
    @MainActor override func getAxTopLeftCorner() async throws -> CGPoint? { axRect.topLeftCorner }
}
