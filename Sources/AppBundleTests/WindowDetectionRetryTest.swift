@testable import AppBundle
import Common
import XCTest

/// A new window has to be managed without the user clicking it (#40).
///
/// Rules that send an app to its workspace and tile it took effect only once the window was clicked.
/// Two paths ended in "nothing happens until something else refreshes": an app whose AX subscription
/// failed while it was still launching (it sends no events, so nothing ever retried), and a window
/// that looked like a popup when it first appeared (re-checked only on some later refresh). A third
/// path could run a rule halfway: a refresh cancelled between `layout tiling` and
/// `move-node-to-workspace` left the window registered, so the rest never ran.
@MainActor
final class WindowDetectionRetryTest: XCTestCase {
    func testAFailedRegistrationSchedulesItsRetry() throws {
        let body = try sourceBody("static func getOrRegister(_ nsApp: NSRunningApplication)", in: "Sources/AppBundle/tree/MacApp.swift", length: 5000)
        let failure = try XCTUnwrap(body.range(of: "failedPids[pid] = (nextAttempt:"))
        let retry = try XCTUnwrap(body.range(of: "scheduleFollowUpRefresh(after: backoff"), "a failed registration no longer schedules a look back")
        XCTAssertLessThan(failure.lowerBound, retry.lowerBound)
    }

    func testAWindowThatArrivesLookingLikeAPopupIsLookedAtAgain() throws {
        let body = try sourceBody("static func getOrRegister(windowId: UInt32", in: "Sources/AppBundle/tree/MacWindow.swift", length: 3600)
        XCTAssertTrue(body.contains("if case .macosPopupWindowsContainer = window.parent?.cases {"))
        XCTAssertTrue(body.contains(#"scheduleFollowUpRefresh(after: 1, "popupRecheck")"#))
    }

    // MARK: - A rule, once started, runs to the end

    /// What every AX round trip inside a window rule does -- `checkCancellation` -- must not stop the
    /// rule once its window is registered.
    func testTheShieldFinishesWorkItsCancelledCallerStarted() async {
        @MainActor final class Box { var finished = false }
        let box = Box()
        let caller = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await shieldedFromCancellation {
                try checkCancellation()
                box.finished = true
            }
        }
        _ = await caller.result
        XCTAssertTrue(box.finished, "a cancelled refresh stopped a window rule halfway")
    }

    func testWindowRulesRunShieldedEverywhereTheyRun() throws {
        let sites = [
            ("Sources/AppBundle/tree/MacWindow.swift", "static func getOrRegister(windowId: UInt32"),
            ("Sources/AppBundle/normalizeLayoutReason.swift", "private func validateStillPopups"),
        ]
        for (file, declaration) in sites {
            let body = try sourceBody(declaration, in: file, length: 3600)
            let shield = try XCTUnwrap(body.range(of: "shieldedFromCancellation {"), "\(file): window rules run unshielded")
            let rules = try XCTUnwrap(body.range(of: "tryOnWindowDetected("), "\(file): \(declaration) no longer runs window rules")
            XCTAssertLessThan(shield.lowerBound, rules.lowerBound, "\(file): window rules run before the shield")
        }
    }
}
