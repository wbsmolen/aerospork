import AppKit
import Common

/// Not private: tests build these to exercise monitor-description resolution headlessly.
struct MonitorImpl {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    var fingerprint: MonitorFingerprint? = nil
}

extension MonitorImpl: Monitor {
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

/// Use it instead of NSScreen because it can be mocked in tests
protocol Monitor: AeroAny {
    /// The index in NSScreen.screens array. 1-based index
    var monitorAppKitNsScreenScreensId: Int { get }
    var name: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
    /// On the protocol, not just ``LazyMonitor``: resolution code used to downcast to `LazyMonitor`,
    /// which made fingerprint matching structurally untestable (mocked monitors always failed the cast).
    var fingerprint: MonitorFingerprint? { get }
}

class LazyMonitor: Monitor {
    private let screen: NSScreen
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let width: CGFloat
    let height: CGFloat
    private var _rect: Rect?
    private var _visibleRect: Rect?
    private var _fingerprint: MonitorFingerprint?
    private var _fingerprintComputed = false

    init(monitorAppKitNsScreenScreensId: Int, _ screen: NSScreen) {
        self.monitorAppKitNsScreenScreensId = monitorAppKitNsScreenScreensId
        self.name = screen.localizedName
        self.width = screen.frame.width // Don't call rect because it would cause recursion during mainMonitor init
        self.height = screen.frame.height // Don't call rect because it would cause recursion during mainMonitor init
        self.screen = screen
    }

    var rect: Rect {
        _rect ?? screen.rect.apply { _rect = $0 }
    }

    var visibleRect: Rect {
        _visibleRect ?? screen.visibleRect.apply { _visibleRect = $0 }
    }

    var fingerprint: MonitorFingerprint? {
        if !_fingerprintComputed {
            _fingerprint = MonitorFingerprint.fromScreen(screen)
            _fingerprintComputed = true
        }
        return _fingerprint
    }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    fileprivate var isMainScreen: Bool {
        frame.minX == 0 && frame.minY == 0
    }

    /// The property is a replacement for Apple's crazy ``frame``
    ///
    /// - For ``MacWindow.topLeftCorner``, (0, 0) is main screen top left corner, and positive y-axis goes down.
    /// - For ``frame``, (0, 0) is main screen bottom left corner, and positive y-axis goes up (which is crazy).
    ///
    /// The property "normalizes" ``frame``
    fileprivate var rect: Rect { frame.monitorFrameNormalized() }

    /// Same as ``rect`` but for ``visibleFrame``
    fileprivate var visibleRect: Rect { visibleFrame.monitorFrameNormalized() }
}

private let testMonitorRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
/// The monitor the tests run against, and also `mainMonitor`'s answer of last resort when AppKit
/// reports no screens at all. Nothing can be laid out in that state; the point is to answer the
/// question instead of taking the process down.
let defaultTestMonitor = MonitorImpl(
    monitorAppKitNsScreenScreensId: 1,
    name: "Test Monitor",
    rect: testMonitorRect,
    visibleRect: testMonitorRect,
)

/// Test seam. Only read when ``isUnitTest``; tests swap in fingerprinted fakes to exercise
/// monitor-description resolution (and reset it in `tearDown`).
nonisolated(unsafe) var testMonitors: [Monitor] = [defaultTestMonitor]

/// Which screen of an arrangement is the main one, given "is this one at the origin?" per screen.
///
/// A free function so the degrade path is testable without AppKit. `firstIndex(of: true)` rather
/// than "exactly one, else die": mirrored displays report identical frames, so **several** screens
/// legitimately sit at the origin. Falling back to index 0 covers the arrangement macOS briefly
/// reports mid-reconfiguration, where no screen claims the origin at all.
func mainScreenIndex(isMainFlags: [Bool]) -> Int? {
    isMainFlags.firstIndex(of: true) ?? isMainFlags.indices.first
}

var mainMonitor: Monitor {
    // Mirrors `isMainScreen`: the main monitor is the one anchored at the origin.
    if isUnitTest { return testMonitors.first { $0.rect.topLeftCorner == .zero } ?? testMonitors.first ?? defaultTestMonitor }
    let screens = NSScreen.screens
    // Was `singleOrNil(where: \.value.isMainScreen).orDie()`, i.e. a fatalError for any arrangement
    // with two screens at the origin (display mirroring) or none (all displays asleep, or a
    // DisplayLink dock mid-reconnect). Both are states the user is allowed to be in.
    //
    // `isMainScreen` reads AppKit's raw `frame` on purpose: going through `rect` would recurse back
    // into this property via `monitorFrameNormalized`.
    // NOT `map(\.isMainScreen)`: swiftformat's `redundantFileprivate` does not count a key-path as a
    // use, so with the key path it rewrites `fileprivate` above to `private` and `./format.sh`
    // stops the project compiling. The explicit closure is the same code and is stable under it.
    guard let index = mainScreenIndex(isMainFlags: screens.map { $0.isMainScreen }) else {
        return defaultTestMonitor // no screens at all: nothing to lay out, so answer instead of dying
    }
    return LazyMonitor(monitorAppKitNsScreenScreensId: index + 1, screens[index])
}

var monitors: [Monitor] {
    isUnitTest
        ? testMonitors
        : NSScreen.screens.enumerated().map { LazyMonitor(monitorAppKitNsScreenScreensId: $0.offset + 1, $0.element) }
}

var sortedMonitors: [Monitor] {
    monitors.sortedBy([\.rect.minX, \.rect.minY])
}
