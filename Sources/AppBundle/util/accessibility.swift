import AppKit
import Common
import PrivateApi

@MainActor
func checkAccessibilityPermissions() {
    let options = [axTrustedCheckOptionPrompt: true]
    if !AXIsProcessTrustedWithOptions(options as CFDictionary) {
        resetAccessibility() // Because macOS doesn't reset it for us when the app signature changes...
        terminateApp()
    }
}

/// Accessibility can be revoked while AeroSpork runs, and trust is checked only at startup. Untrusted, AX
/// answers may read as "destroyed", and a refresh would collect every window and save a memory file
/// without them. So the background refresh is skipped until trust returns. Sessions are not: they collect
/// nothing and save nothing, and the CLI and status bars keep answering.
@MainActor private var trustLost = false

/// The background refresh found trust revoked. True, and one record, only at the start of an episode.
@MainActor @discardableResult func noteTrustLost() -> Bool {
    if trustLost { return false }
    trustLost = true
    AppLog.session.fault("Accessibility permission is revoked: windows are not refreshed until it is granted again")
    return true
}

/// The 30 s sweep's half: true once, when trust is back after an episode, so the sweep refreshes.
@MainActor func noteTrustRegained(isTrusted: Bool) -> Bool {
    guard trustLost, isTrusted else { return false }
    trustLost = false
    return true
}

private func resetAccessibility() {
    _ = try? Process.run(URL(filePath: "/usr/bin/tccutil"), arguments: ["reset", "Accessibility", aeroSporkAppId])
}

protocol ReadableAttr: Sendable {
    associatedtype T
    var getter: @Sendable (AnyObject) -> T? { get }
    var key: String { get }
}

protocol WritableAttr: ReadableAttr, Sendable {
    var setter: @Sendable (T) -> CFTypeRef? { get }
}

enum Ax {
    struct ReadableAttrImpl<T>: ReadableAttr {
        var key: String
        var getter: @Sendable (AnyObject) -> T?
    }

    struct WritableAttrImpl<T>: WritableAttr {
        var key: String
        var getter: @Sendable (AnyObject) -> T?
        var setter: @Sendable (T) -> CFTypeRef?
    }

    static let titleAttr = WritableAttrImpl<String>(
        key: kAXTitleAttribute,
        getter: { $0 as? String },
        setter: { $0 as CFTypeRef },
    )
    static let roleAttr = WritableAttrImpl<String>(
        key: kAXRoleAttribute,
        getter: { $0 as? String },
        setter: { $0 as CFTypeRef },
    )
    static let subroleAttr = WritableAttrImpl<String>(
        key: kAXSubroleAttribute,
        getter: { $0 as? String },
        setter: { $0 as CFTypeRef },
    )
    static let identifierAttr = ReadableAttrImpl<String>(
        key: kAXIdentifierAttribute,
        getter: { $0 as? String },
    )
    static let enabledAttr = ReadableAttrImpl<Bool>(
        key: kAXEnabledAttribute,
        getter: { $0 as? Bool },
    )
    static let enhancedUserInterfaceAttr = WritableAttrImpl<Bool>(
        key: "AXEnhancedUserInterface",
        getter: { $0 as? Bool },
        setter: { $0 as CFTypeRef },
    )
    static let minimizedAttr = WritableAttrImpl<Bool>(
        key: kAXMinimizedAttribute,
        getter: { $0 as? Bool },
        setter: { $0 as CFTypeRef },
    )
    static let isFullscreenAttr = WritableAttrImpl<Bool>(
        key: "AXFullScreen",
        getter: { $0 as? Bool },
        setter: { $0 as CFTypeRef },
    )
    /// Writable on purpose. Setting this is what actually moves an app's focused window; it is the
    /// attribute `Ax.focusedWindowAttr` (`kAXFocusedWindowAttribute`) reads back, so it is the only
    /// write that closes the loop with `getNativeFocusedWindow`. `isMainAttr` + `kAXRaiseAction`
    /// change window ORDER, which is not the same thing and is why focusing a window of an app that
    /// also has windows on another workspace could leave the app pointing at the old one.
    static let isFocused = WritableAttrImpl<Bool>(
        key: kAXFocusedAttribute,
        getter: { $0 as? Bool },
        setter: { $0 as CFTypeRef },
    )
    static let isMainAttr = WritableAttrImpl<Bool>(
        key: kAXMainAttribute,
        getter: { $0 as? Bool },
        setter: { $0 as CFTypeRef },
    )
    static let sizeAttr = WritableAttrImpl<CGSize>(
        key: kAXSizeAttribute,
        getter: {
            guard CFGetTypeID($0) == AXValueGetTypeID() else { return nil }
            let val = $0 as! AXValue
            var raw: CGSize = .zero
            guard AXValueGetValue(val, .cgSize, &raw) else { return nil }
            return raw
        },
        setter: {
            var size = $0
            return AXValueCreate(.cgSize, &size) as CFTypeRef
        },
    )
    static let topLeftCornerAttr = WritableAttrImpl<CGPoint>(
        key: kAXPositionAttribute,
        getter: {
            guard CFGetTypeID($0) == AXValueGetTypeID() else { return nil }
            let val = $0 as! AXValue
            var raw: CGPoint = .zero
            guard AXValueGetValue(val, .cgPoint, &raw) else { return nil }
            return raw
        },
        setter: {
            var size = $0
            return AXValueCreate(.cgPoint, &size) as CFTypeRef
        },
    )
    /// Returns windows visible on all monitors
    /// If some windows are located on not active macOS Spaces then they won't be returned
    static let windowsAttr = ReadableAttrImpl<[WindowIdAndAxUiElement]>(
        key: kAXWindowsAttribute,
        getter: { ($0 as? NSArray)?.compactMap(windowOrNil).compactMap {
            guard let casted = $0.ax.cast else { return nil }
            return ($0.windowId, casted)
        } ?? [] },
    )
    /// The raw `kAXWindowsAttribute` list, with no window id read per element. `identifyWindows` names them.
    static let windowElementsAttr = ReadableAttrImpl<[AXUIElement]>(
        key: kAXWindowsAttribute,
        getter: { ($0 as? NSArray)?.compactMap { castToAxUiElementMock($0 as AnyObject)?.cast } ?? [] },
    )
    static let childrenAttr = ReadableAttrImpl<[any AxUiElementMock]>(
        key: kAXChildrenAttribute,
        getter: { ($0 as? NSArray)?.compactMap { castToAxUiElementMock($0 as AnyObject) } ?? [] },
    )
    static let tabsAttr = ReadableAttrImpl<[any AxUiElementMock]>(
        key: kAXTabsAttribute,
        getter: { ($0 as? NSArray)?.compactMap { castToAxUiElementMock($0 as AnyObject) } ?? [] },
    )
    static let focusedWindowAttr = ReadableAttrImpl<WindowIdAndAxUiElementMock>(
        key: kAXFocusedWindowAttribute,
        getter: windowOrNil,
    )
    static let closeButtonAttr = ReadableAttrImpl<any AxUiElementMock>(
        key: kAXCloseButtonAttribute,
        getter: castToAxUiElementMock,
    )
    // Note! fullscreen is not the same as "zoom" (green plus)
    static let fullscreenButtonAttr = ReadableAttrImpl<any AxUiElementMock>(
        key: kAXFullScreenButtonAttribute,
        getter: castToAxUiElementMock,
    )
    // green plus
    static let zoomButtonAttr = ReadableAttrImpl<any AxUiElementMock>(
        key: kAXZoomButtonAttribute,
        getter: castToAxUiElementMock,
    )
    static let minimizeButtonAttr = ReadableAttrImpl<any AxUiElementMock>(
        key: kAXMinimizeButtonAttribute,
        getter: castToAxUiElementMock,
    )
}

let kAXAeroSynthetic = "Aero.synthetic"

private func castToAxUiElementMock(_ a: AnyObject) -> AxUiElementMock? {
    if isUnitTest {
        if let str = a as? String, let commaIndex = str.firstIndex(of: ",") {
            let windowId = UInt32.init(String(str.prefix(upTo: commaIndex)).removePrefix("AXUIElement(AxWindowId="))
            if let windowId {
                return castToAxUiElementMock([
                    "Aero.axWindowId": Json.uint32(windowId),
                    kAXAeroSynthetic: Json.bool(true),
                ] as AnyObject)
            }
        }
        if let dict = a as? [String: Json] { // Convert from _SwiftDeferredNSDictionary<String, Json>
            return dict as? AxUiElementMock ?? dieT("Cannot cast \(type(of: a)) to AxUiElementMock")
        }
        return nil
    }
    if CFGetTypeID(a) == AXUIElementGetTypeID() {
        return (a as! AXUIElement)
    }
    return nil
}

typealias WindowIdAndAxUiElement = (windowId: UInt32, ax: AXUIElement)
typealias WindowIdAndAxUiElementMock = (windowId: UInt32, ax: AxUiElementMock)

private func windowOrNil(_ any: Any?) -> WindowIdAndAxUiElementMock? {
    guard let any else { return nil }
    guard let potentialWindow = castToAxUiElementMock(any as AnyObject) else { return nil }
    // Filter out non-window objects (e.g. Finder's desktop)
    let windowId = potentialWindow.containingWindowId()
    if let windowId {
        return (windowId, potentialWindow)
    } else {
        return nil
    }
}

/// Each element's window id, keeping only the elements that are windows. An element AeroSpork already tracks
/// answers from `known`, a local `CFHash`/`CFEqual` lookup of tens of nanoseconds. Only a miss pays
/// `containingWindowId()`, an `_AXUIElementGetWindow` IPC (about 71 µs, the whole `axMessagingTimeout` for a busy
/// app), and only a miss is asked `isWindow`.
///
/// Safe because an element's window id never changes, and AppKit never hands a new window a dead window's element
/// (dev-docs/performance.md item 22). It says which window an element is, never whether a window is alive: that
/// stays with `isDestroyed()` and the `.cannotComplete` rule (#39).
func identifyWindows<E: AxUiElementMock & Hashable>(
    _ elements: [E],
    known: [E: UInt32],
    isWindow: (E) -> Bool = { _ in true },
) -> [(windowId: UInt32, ax: E)] {
    elements.compactMap { element in
        if let id = known[element] { return (id, element) }
        // Filters out non-window objects (e.g. Finder's desktop)
        guard let id = element.containingWindowId(), isWindow(element) else { return nil }
        return (id, element)
    }
}

extension AXUIElement: AxUiElementMock {
    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        let state = signposter.beginInterval(#function, id: signposter.makeSignpostID(), "attr: \(attr.key) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        var raw: AnyObject?
        return AXUIElementCopyAttributeValue(self, attr.key as CFString, &raw) == .success
            ? raw.flatMap(attr.getter)
            : nil
    }

    /// One `AXUIElementCopyMultipleAttributeValues` costs what one single read does; two reads cost 2-10x.
    ///
    /// Options `[]`, never `.stopOnError`: that mode was the pessimization in the deleted `AxBatchFetcher`
    /// (dev-docs/performance.md). Without it a failed attribute comes back as an `AXValue` of type
    /// `kAXValueAXErrorType`, which the getters below decode to nil, as a failed single read would.
    /// Signposted as `get(_:)`, so Instruments counts stay comparable with the single reads it replaces.
    private func get<A: ReadableAttr, B: ReadableAttr>(_ a: A, _ b: B) -> (A.T?, B.T?) {
        let state = signposter.beginInterval("get(_:)", id: signposter.makeSignpostID(), "attr: \(a.key)+\(b.key) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval("get(_:)", state) }
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(self, [a.key, b.key] as CFArray, [], &raw) == .success,
              let values = raw as? [AnyObject], values.count == 2
        else { return (nil, nil) }
        return (a.getter(values[0]), b.getter(values[1]))
    }

    func getFrame() -> (topLeft: CGPoint?, size: CGSize?) {
        get(Ax.topLeftCornerAttr, Ax.sizeAttr)
    }

    /// On Finder `AXFullScreen` comes back as an error slot, which decodes to nil, as its single read did.
    func getNativeFlags() -> (fullscreen: Bool?, minimized: Bool?) {
        get(Ax.isFullscreenAttr, Ax.minimizedAttr)
    }

    @discardableResult func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool {
        let state = signposter.beginInterval(#function, id: signposter.makeSignpostID(), "attr: \(attr.key) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        guard let value = attr.setter(value) else { return false }
        return AXUIElementSetAttributeValue(self, attr.key as CFString, value) == .success
    }

    func containingWindowId() -> CGWindowID? {
        let state = signposter.beginInterval(#function, id: signposter.makeSignpostID(), "axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        var cgWindowId = CGWindowID()
        return _AXUIElementGetWindow(self, &cgWindowId) == .success ? cgWindowId : nil
    }

    func isDestroyed() -> Bool {
        let state = signposter.beginInterval(#function, id: signposter.makeSignpostID(), "axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
        defer { signposter.endInterval(#function, state) }
        var cgWindowId = CGWindowID()
        return axErrorMeansDestroyed(_AXUIElementGetWindow(self, &cgWindowId))
    }
}

/// Does this `_AXUIElementGetWindow` result mean the window is gone, as opposed to unanswered?
///
/// "Anything but the timeout", and deliberately NOT `== .invalidUIElement`. What a real TextEdit
/// window's element returns on macOS 26 and 27 when it is held and read again:
///
///   window alive                          -> .success
///   window closed, app still running      -> kAXErrorIllegalArgument (-25201)
///   app busy past `axMessagingTimeout`    -> .cannotComplete, after the full timeout
///   app terminated                        -> .cannotComplete
///   AeroSpork has no Accessibility access  -> .apiDisabled (-25211), for every read of every app
///
/// So the intuitive spelling would be wrong twice over. `.invalidUIElement` is never what a destroyed
/// window reports, so windows would linger in the tree forever; and a busy app is indistinguishable
/// from a terminated one. Excluding only `.cannotComplete` gets both right: a closed window is still
/// collected, and a busy app keeps its windows. A terminated app is handled before this is reached --
/// `refreshAllAndGetAliveWindowIds` drops it from `allAppsMap`, so its windows leave the tree by being
/// absent from the mapping rather than by this check.
///
/// Not an allowlist of "destroyed" codes either. The alive-window filter only ever removes entries,
/// so a closed window reported with a code missing from such a list would keep its tiling slot until
/// the app quits. Treating an unexpected code as destroyed costs one re-registration instead.
///
/// `.apiDisabled` is the second exception: it says nothing about the window, only that AeroSpork may
/// not ask. Read as "destroyed", one refresh that ran just as Accessibility was turned off would
/// collect every window, and each would lose its place and workspace.
func axErrorMeansDestroyed(_ error: AXError) -> Bool {
    error != .success && error != .cannotComplete && error != .apiDisabled
}

extension AXObserver {
    static func new(_ pid: pid_t, _ handler: AXObserverCallback) -> AXObserver? {
        var observer: AXObserver? = nil
        return AXObserverCreate(pid, handler, &observer) == .success ? observer : nil
    }
}
