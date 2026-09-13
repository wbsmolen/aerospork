import AppKit
import Common

/// Alternative name: AttrAddressibleStorage
protocol AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T?
    /// The AX *write* seam.
    ///
    /// `AXUIElement` already satisfies this from its extension in `accessibility.swift`, so nothing
    /// on the production path changed: every real call site holds a concrete `AXUIElement` (or a
    /// `some AxUiElementMock` generic that specializes to one), which the compiler dispatches
    /// straight to that extension -- the witness table entry is never consulted, and the
    /// `OSSignposter` intervals there are untouched.
    ///
    /// It exists because writes are the half of the AX API that actually fails in production --
    /// silently ignored, clamped to another value, or timed out -- and until now none of that was
    /// reachable from a test.
    @discardableResult func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool
    func containingWindowId() -> CGWindowID?

    /// Is this element *destroyed*, as opposed to merely unresponsive?
    ///
    /// `refreshAndGetAliveWindowIds` stops tracking a window this answers `true` for, and `refresh`
    /// then garbage collects it -- which unbinds it from its workspace and hands focus to whatever
    /// window is most recent there. So a false `true` costs the user a window that reappears on
    /// whatever workspace is focused next, plus a focus steal. That was
    /// https://github.com/wbsmolen/aerospork/issues/39, and it read as random because it needed an
    /// app to be busy at the moment of a refresh.
    ///
    /// `containingWindowId()` cannot answer this: it collapses every failure to `nil`, and the
    /// failures mean opposite things. Answering it needs the `AXError` itself, which only a real
    /// `AXUIElement` has.
    func isDestroyed() -> Bool
}

extension AxUiElementMock {
    /// Conservative default, and the answer every test double gets unless it says otherwise: an
    /// element we cannot interrogate is never assumed dead. Being wrong this way costs one stale
    /// entry until the next refresh; being wrong the other way is the bug above.
    func isDestroyed() -> Bool { false }
}

extension AxUiElementMock {
    var cast: AXUIElement? {
        if CFGetTypeID(self as CFTypeRef) == AXUIElementGetTypeID() {
            return (self as! AXUIElement)
        }
        return nil
    }
}
