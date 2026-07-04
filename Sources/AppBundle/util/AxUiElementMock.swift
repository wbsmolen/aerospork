import AppKit
import Common

/// Alternative name: AttrAddressibleStorage
protocol AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T?
    func containingWindowId() -> CGWindowID?
}

extension AxUiElementMock {
    var cast: AXUIElement? {
        if CFGetTypeID(self as CFTypeRef) == AXUIElementGetTypeID() {
            return (self as! AXUIElement)
        }
        return nil
    }
}
