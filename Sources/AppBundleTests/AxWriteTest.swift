@testable import AppBundle
import AppKit
import Common
import XCTest

/// A window (or app) element that answers AX reads and can misbehave on AX writes.
///
/// Reference semantics on purpose: the code under test takes the element as a parameter, and with a
/// struct every write the production path made would be discarded before the test could see it.
final class FakeAxElement: AxUiElementMock {
    /// What the app does with a write. These are the four behaviours seen in production, not
    /// hypotheticals -- see the individual cases.
    enum WriteOutcome {
        /// Well-behaved app: the write lands and a subsequent read observes it.
        case accept
        /// `AXUIElementSetAttributeValue` reports success and the window does not move. Chromium /
        /// Electron with `AXEnhancedUserInterface` on, and apps that re-run their own layout.
        case ignore
        /// The app accepts the write but substitutes a value of its own: a minimum window size, or
        /// a position snapped back onto a screen. The stored value is the *clamped* one.
        case clamp(AnyObject)
        /// The AX message never landed (wedged app hitting `AXUIElementSetMessagingTimeout`).
        case timeout
    }

    private var attrs: [String: AnyObject] = [:]
    /// AX attribute key of every attempted write, in order.
    private(set) var writes: [String] = []
    /// AX attribute key of every read. Recorded because the no-op guard's whole point is trading
    /// writes for reads -- a guard that reads attributes it does not need is also a regression.
    private(set) var reads: [String] = []
    var onWrite: (String) -> WriteOutcome = { _ in .accept }

    /// Install a value as if the app already had it, bypassing `onWrite` and the counters.
    func seed<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) {
        attrs[attr.key] = attr.setter(value)
    }

    func get<Attr: ReadableAttr>(_ attr: Attr) -> Attr.T? {
        reads.append(attr.key)
        return attrs[attr.key].flatMap { attr.getter($0) }
    }

    @discardableResult func set<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> Bool {
        writes.append(attr.key)
        switch onWrite(attr.key) {
            case .accept:
                attrs[attr.key] = attr.setter(value)
                return true
            case .ignore:
                return true // success reported, nothing moved
            case .clamp(let clamped):
                attrs[attr.key] = clamped
                return true
            case .timeout:
                return false
        }
    }

    /// The batch, recorded as ONE read under its own key. Implemented here rather than inherited, so a
    /// `getFrame` that is no longer a protocol requirement shows up as two single reads instead.
    func getFrame() -> (topLeft: CGPoint?, size: CGSize?) {
        reads.append(FakeAxElement.frameRead)
        return (attrs[Ax.topLeftCornerAttr.key].flatMap(Ax.topLeftCornerAttr.getter), attrs[Ax.sizeAttr.key].flatMap(Ax.sizeAttr.getter))
    }

    static let frameRead = "getFrame"

    /// The same, for the fullscreen and minimized batch.
    func getNativeFlags() -> (fullscreen: Bool?, minimized: Bool?) {
        reads.append(FakeAxElement.nativeFlagsRead)
        return (attrs[Ax.isFullscreenAttr.key].flatMap(Ax.isFullscreenAttr.getter), attrs[Ax.minimizedAttr.key].flatMap(Ax.minimizedAttr.getter))
    }

    static let nativeFlagsRead = "getNativeFlags"

    func containingWindowId() -> CGWindowID? { 1 }

    func resetCounters() {
        writes = []
        reads = []
    }
}

/// Value a test can hand to `.clamp`, boxed through the same setter the production path uses.
private func axValue<Attr: WritableAttr>(_ attr: Attr, _ value: Attr.T) -> AnyObject {
    attr.setter(value)!
}

/// The `setAxFrame` body, minus the `RunLoopJob` plumbing that needs a real app thread.
///
/// Mirrors `MacApp.setAxFrame`: guard first, then `disableAnimations`, then the writes. Being a
/// copy, it pins the contract of the three functions it calls, not the order of the three lines
/// inside `MacApp.setAxFrame` -- sinking the guard back inside `disableAnimations` there would not
/// turn anything red here.
private func setAxFramePass(_ app: FakeAxElement, _ window: FakeAxElement, _ topLeft: CGPoint?, _ size: CGSize?) {
    if isFrameSatisfied(window, topLeft, size) { return }
    disableAnimations(app: app) {
        setFrame(window, topLeft, size)
    }
}

private let targetTopLeft = CGPoint(x: 100, y: 200)
private let targetSize = CGSize(width: 800, height: 600)

final class AxWriteTest: XCTestCase {
    private func window(topLeft: CGPoint = targetTopLeft, size: CGSize = targetSize) -> FakeAxElement {
        let w = FakeAxElement()
        w.seed(Ax.topLeftCornerAttr, topLeft)
        w.seed(Ax.sizeAttr, size)
        return w
    }

    // MARK: the no-op guard

    /// The performance claim in dev-docs/performance.md item 6: a window already at its target
    /// frame costs zero AX writes, on every refresh, forever.
    func testGuardSkipsAllWritesWhenFrameAlreadyMatches() {
        let app = FakeAxElement()
        let win = window()
        setAxFramePass(app, win, targetTopLeft, targetSize)
        assertEquals(win.writes, [])
        // Zero AX traffic on the *app* element too: `isFrameSatisfied` touches only the window, so
        // hoisting it above `disableAnimations` (a read plus two writes on the app) costs nothing.
        assertEquals(app.writes, [])
        assertEquals(app.reads, [])
    }

    func testGuardToleratesSubPixelDrift() {
        // AX rounds; a window reporting 0.5pt off is at the target for our purposes.
        let win = window(topLeft: CGPoint(x: 100.5, y: 199.5), size: CGSize(width: 799.5, height: 600.5))
        assertTrue(isFrameSatisfied(win, targetTopLeft, targetSize))
    }

    func testGuardRejectsDriftAtOrBeyondOnePoint() {
        assertFalse(isFrameSatisfied(window(topLeft: CGPoint(x: 101.5, y: 200)), targetTopLeft, targetSize))
        assertFalse(isFrameSatisfied(window(size: CGSize(width: 802, height: 600)), targetTopLeft, targetSize))
    }

    /// A window whose frame cannot be read (dying, or an app that doesn't answer) must be treated
    /// as unsatisfied. "Unknown" has to mean "write it", never "skip it" -- otherwise a window that
    /// hiccups once is never laid out again.
    func testUnreadableFrameIsNotSatisfied() {
        let unreadable = FakeAxElement() // nothing seeded, every get returns nil
        assertFalse(isFrameSatisfied(unreadable, targetTopLeft, targetSize))
        let app = FakeAxElement()
        setAxFramePass(app, unreadable, targetTopLeft, targetSize)
        assertEquals(unreadable.writes, [kAXSizeAttribute, kAXPositionAttribute, kAXSizeAttribute])
    }

    /// Both values in one batched read, through the element's OWN `getFrame`.
    ///
    /// `getFrame` must stay a protocol requirement. As an extension-only method, the generic
    /// `isFrameSatisfied`/`parkAxWindow` would dispatch statically to the two-read default, and production's
    /// `AXUIElement` batch would never run. This fake implements the batch itself, so that regression reads as
    /// two single reads here. Counted, not timed.
    func testGuardReadsTheFrameOnceThroughTheElementsOwnBatch() {
        for win in [window(), window(size: CGSize(width: 10, height: 10)), window(topLeft: .zero)] {
            _ = isFrameSatisfied(win, targetTopLeft, targetSize)
            assertEquals(win.reads, [FakeAxElement.frameRead])
        }
        let parked = window()
        parkAxWindow(parked, app: FakeAxElement()) { _ in targetTopLeft }
        assertEquals(parked.reads, [FakeAxElement.frameRead])
    }

    /// A one-sided guard reads only its side: `setAxTopLeftCorner` asks about the position alone, and
    /// reading the size there would be pure waste.
    func testGuardOnlyReadsWhatItWasAsked() {
        let posOnly = window()
        _ = isFrameSatisfied(posOnly, targetTopLeft, nil)
        assertEquals(posOnly.reads, [kAXPositionAttribute])

        let sizeOnly = window()
        _ = isFrameSatisfied(sizeOnly, nil, targetSize)
        assertEquals(sizeOnly.reads, [kAXSizeAttribute])
    }

    /// Parking: the spot comes from the size read in the same batch, a window already there costs no write, and
    /// a window whose size cannot be read is left alone.
    func testParkingWritesThePositionOnlyWhenTheWindowIsNotThere() {
        let spot = { (size: CGSize) in CGPoint(x: -size.width, y: 900) }
        let there = window(topLeft: spot(targetSize))
        parkAxWindow(there, app: FakeAxElement(), at: spot)
        assertEquals(there.writes, [])

        let elsewhere = window()
        parkAxWindow(elsewhere, app: FakeAxElement(), at: spot)
        assertEquals(elsewhere.writes, [kAXPositionAttribute])
        assertEquals(elsewhere.get(Ax.topLeftCornerAttr), spot(targetSize))

        let unreadable = FakeAxElement()
        parkAxWindow(unreadable, app: FakeAxElement(), at: spot)
        assertEquals(unreadable.writes, [])
    }

    /// macOS keeps a title bar on screen, so a spot near the bottom edge is clamped upwards. Compared with
    /// the spot alone, that window never looked parked and was written again on every refresh.
    func testAClampedParkIsWrittenOnceNotOnEveryRefresh() {
        let spot = { (_: CGSize) in CGPoint(x: 2047, y: 1329) }
        let clamped = CGPoint(x: 2047, y: 1289)
        let win = window()
        win.onWrite = { _ in .clamp(axValue(Ax.topLeftCornerAttr, clamped)) }
        var settled: ParkedSpot?

        parkAxWindow(win, app: FakeAxElement(), at: spot, settled: &settled)
        assertEquals(win.writes, [kAXPositionAttribute])
        for _ in 0 ..< 3 { parkAxWindow(win, app: FakeAxElement(), at: spot, settled: &settled) }
        assertEquals(win.writes, [kAXPositionAttribute], additionalMsg: "a window macOS clamped was parked again on every refresh")

        // Moved away by its app: parked again.
        win.seed(Ax.topLeftCornerAttr, CGPoint(x: 300, y: 300))
        parkAxWindow(win, app: FakeAxElement(), at: spot, settled: &settled)
        assertEquals(win.writes.count, 2)
    }

    /// A write that did not take leaves the window on screen, far from the spot. That is not a clamp, so it is
    /// not remembered, and the next refresh tries again.
    func testAParkThatDidNotTakeIsNotRememberedAsParked() {
        let spot = { (_: CGSize) in CGPoint(x: 2047, y: 1329) }
        let win = window()
        win.onWrite = { _ in .ignore }
        var settled: ParkedSpot?
        parkAxWindow(win, app: FakeAxElement(), at: spot, settled: &settled)
        XCTAssertNil(settled)
        parkAxWindow(win, app: FakeAxElement(), at: spot, settled: &settled)
        assertEquals(win.writes, [kAXPositionAttribute, kAXPositionAttribute])
    }

    // MARK: write ordering

    /// size, then position, then size again -- issues #143 and #335. The trailing size write is
    /// what un-breaks apps that resize themselves when moved, so losing it is a real regression.
    func testSetFrameWritesSizePositionSize() {
        let win = window()
        setFrame(win, targetTopLeft, targetSize)
        assertEquals(win.writes, [kAXSizeAttribute, kAXPositionAttribute, kAXSizeAttribute])
    }

    func testSetFrameWithoutPositionWritesSizeOnce() {
        let win = window()
        setFrame(win, nil, targetSize)
        assertEquals(win.writes, [kAXSizeAttribute])
    }

    // MARK: failing writes

    /// An app that reports success and ignores the write: the guard stays unsatisfied, so the next
    /// refresh retries. That retry is *bounded* -- one `setFrame` per pass, not a loop -- which is
    /// the property that keeps a stubborn app from wedging a refresh.
    func testIgnoredWriteRetriesOncePerPassAndDoesNotSpin() {
        let app = FakeAxElement()
        let win = window(topLeft: .zero, size: .zero)
        win.onWrite = { _ in .ignore }

        setAxFramePass(app, win, targetTopLeft, targetSize)
        assertEquals(win.writes.count, 3)
        assertFalse(isFrameSatisfied(win, targetTopLeft, targetSize))

        win.resetCounters()
        setAxFramePass(app, win, targetTopLeft, targetSize)
        assertEquals(win.writes.count, 3)
    }

    /// The clamping app (minimum window size). Two things must hold and they pull in opposite
    /// directions: the clamped window must not be *permanently skipped* (so the guard keeps
    /// reporting unsatisfied and we keep correcting it), and a pass must not spin trying to
    /// converge on a value the app will never accept.
    func testClampedWriteRetriesButNeverSpinsWithinAPass() {
        let app = FakeAxElement()
        let win = window(topLeft: .zero, size: .zero)
        let minimumSize = axValue(Ax.sizeAttr, CGSize(width: 400, height: 300))
        win.onWrite = { $0 == kAXSizeAttribute ? .clamp(minimumSize) : .accept }

        setAxFramePass(app, win, targetTopLeft, targetSize)
        assertEquals(win.writes.count, 3) // bounded: no retry loop inside a single pass
        assertEquals(win.get(Ax.sizeAttr), CGSize(width: 400, height: 300))
        assertFalse(isFrameSatisfied(win, targetTopLeft, targetSize)) // not permanently satisfied

        win.resetCounters()
        setAxFramePass(app, win, targetTopLeft, targetSize)
        assertEquals(win.writes.count, 3) // still bounded on the next refresh

        // ...and once layout asks for a frame the app is willing to hold, the guard goes quiet.
        win.resetCounters()
        setAxFramePass(app, win, targetTopLeft, CGSize(width: 400, height: 300))
        assertEquals(win.writes, [])
    }

    /// A wedged app: the write returns failure and the value never changes. Nothing may crash, and
    /// the guard must not conclude the window is placed.
    func testTimedOutWriteReportsFailureAndChangesNothing() {
        let win = window(topLeft: .zero, size: .zero)
        win.onWrite = { _ in .timeout }
        assertFalse(win.set(Ax.sizeAttr, targetSize))
        assertEquals(win.get(Ax.sizeAttr), CGSize.zero)
        assertFalse(isFrameSatisfied(win, targetTopLeft, targetSize))
    }

    // MARK: AXEnhancedUserInterface

    /// The Electron fight: the flag must be put back exactly as it was found, even though the body
    /// in between is what moves the window.
    func testDisableAnimationsRestoresEnhancedUserInterface() {
        let app = FakeAxElement()
        app.seed(Ax.enhancedUserInterfaceAttr, true)
        var bodyRan = false
        disableAnimations(app: app) { bodyRan = true }
        assertTrue(bodyRan)
        assertEquals(app.writes, ["AXEnhancedUserInterface", "AXEnhancedUserInterface"])
        assertEquals(app.get(Ax.enhancedUserInterfaceAttr), true)
    }

    /// An app that never had the flag must not have it *introduced* by us -- writing `false` there
    /// would be two AX writes per frame change for no reason, and would leave the app in a state it
    /// never asked for.
    func testDisableAnimationsWritesNothingWhenFlagIsAbsent() {
        let app = FakeAxElement()
        disableAnimations(app: app) {}
        assertEquals(app.writes, [])
        assertNil(app.get(Ax.enhancedUserInterfaceAttr))
    }
}

/// Focus is handed over by an AX write, and for a long time it was the *wrong* write.
final class AxFocusWriteTest: XCTestCase {
    /// The regression. `kAXFocusedAttribute` is the attribute `kAXFocusedWindowAttribute` reports
    /// back, and `getNativeFocusedWindow` reads exactly that -- so a focus path that never writes it
    /// is telling macOS nothing and reading macOS's unchanged answer one refresh later.
    ///
    /// Symptom when it was missing: switching to a workspace whose app ALSO had windows on another
    /// workspace bounced focus (and the active workspace, and the mouse) to that other workspace.
    /// Raising and setting `isMain` reorder windows; neither moves the app's focused-window pointer.
    func testFocusWritesTheAttributeMacOsReadsBack() {
        let win = FakeAxElement()
        setAxFocus(win)
        XCTAssertTrue(win.writes.contains(kAXFocusedAttribute), "focus never wrote \(kAXFocusedAttribute): \(win.writes)")
        assertEquals(win.get(Ax.isFocused), true)
    }

    /// Order matters: point the app at the window before reordering, so a raise cannot be applied
    /// against a stale focused window.
    func testFocusedIsWrittenBeforeMain() {
        let win = FakeAxElement()
        setAxFocus(win)
        assertEquals(win.writes, [kAXFocusedAttribute, kAXMainAttribute])
    }

    /// An app that ignores the write must not leave us believing it took. `nativeFocus` is
    /// best-effort by nature, but `updateFocusCache`'s grace period is what covers this -- the write
    /// silently doing nothing is the case that used to be indistinguishable from success.
    func testAnAppThatIgnoresTheWriteDoesNotReportFocused() {
        let win = FakeAxElement()
        win.onWrite = { _ in .ignore }
        setAxFocus(win)
        assertNil(win.get(Ax.isFocused))
    }
}

/// What a new window costs to classify. Every read is an AX round trip, during registration.
final class AxWindowTypeReadTest: XCTestCase {
    /// `isWindowHeuristicOld` always reads the subrole and `isDialogHeuristic` read it again.
    func testTheWindowTypeReadsTheSubroleOnce() {
        for (subrole, expected) in [(kAXStandardWindowSubrole, AxUiElementWindowType.dialog), (kAXDialogSubrole, .dialog)] {
            let win = FakeAxElement()
            win.seed(Ax.subroleAttr, subrole)
            assertEquals(win.getWindowType(axApp: FakeAxElement(), appBundleId: nil), expected)
            assertEquals(win.reads.count(where: { $0 == kAXSubroleAttribute }), 1)
        }
    }
}

/// The paired native-state read behind `normalizeLayoutReason`.
///
/// That function asks every window of every workspace for its fullscreen and minimized flags on
/// every refresh. Asking through the two separate properties cost two `runInLoop` round trips per
/// window; `readMacosNativeState` is the single-traversal form. Asserted on the AX mock's recorded
/// operations rather than on wall-clock, per dev-docs/performance.md.
final class AxNativeStateReadTest: XCTestCase {
    /// One batched read through the element's own `getNativeFlags`, not the two-read default, so a
    /// `getNativeFlags` that is no longer a protocol requirement fails here.
    func testAnOrdinaryWindowIsAskedBothFlagsInOneRead() {
        let win = FakeAxElement()
        win.seed(Ax.isFullscreenAttr, false)
        win.seed(Ax.minimizedAttr, false)

        let state = readMacosNativeState(win)
        assertEquals(state.fullscreen, false)
        assertEquals(state.minimized, false)
        assertEquals(win.reads, [FakeAxElement.nativeFlagsRead])
    }

    /// The short-circuit used to save the minimized read, an IPC; a batch has no second IPC to save.
    /// What stays is the answer: a fullscreen window cannot be minimized, whatever the app says.
    func testAFullscreenWindowIsNeverMinimized() {
        let win = FakeAxElement()
        win.seed(Ax.isFullscreenAttr, true)
        win.seed(Ax.minimizedAttr, true) // would be a lie; must not count

        let state = readMacosNativeState(win)
        assertEquals(state.fullscreen, true)
        assertEquals(state.minimized, false)
        assertEquals(win.reads, [FakeAxElement.nativeFlagsRead])
    }

    /// A window that answers nothing (dying, or an unresponsive app) must read as "conventional",
    /// not crash and not get bound into the minimized container.
    func testAnUnreadableWindowIsNeitherFullscreenNorMinimized() {
        let state = readMacosNativeState(FakeAxElement())
        assertEquals(state.fullscreen, false)
        assertEquals(state.minimized, false)
    }

    func testMinimizedIsReported() {
        let win = FakeAxElement()
        win.seed(Ax.isFullscreenAttr, false)
        win.seed(Ax.minimizedAttr, true)
        assertEquals(readMacosNativeState(win).minimized, true)
    }
}
