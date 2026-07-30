@testable import AppBundle
import XCTest

/// `open-settings` must not report success when it opened nothing.
///
/// The settings window is opened through `\.openSettings`, which is only readable inside a view, so
/// the menu bar label captures it into `settingsOpener` when it appears. Until that happens the
/// opener is nil -- a window of a few seconds after launch, which `aerospork open-settings` can land
/// in.
///
/// The nil branch used to fall through to the pre-Ventura `showPreferencesWindow:` selector.
/// `sendAction` returns true for it on macOS 14+ while opening nothing, so the command exited 0
/// having done nothing visible: exactly the silent success this whole path was rewritten to remove,
/// reintroduced through the fallback. Measured against a real 1.1.4 build, eight seconds after
/// launch: exit 0, zero windows.
@MainActor
final class OpenSettingsTest: XCTestCase {
    private var saved: (() -> Void)?

    override func setUp() {
        saved = settingsOpener
    }

    override func tearDown() {
        settingsOpener = saved
    }

    /// The regression, pinned by reading the source rather than by calling it.
    ///
    /// Calling `openSettingsWindow()` with a nil opener cannot distinguish the two versions here:
    /// in a headless test process there is no responder chain, so `sendAction` returns false and the
    /// buggy code returns false too. The behavioural test passes either way — verified by putting
    /// the fallthrough back and watching it stay green — so it would have been a test that only
    /// looked like coverage. The difference exists solely in a real app, where `sendAction` returns
    /// true for a selector that opens nothing.
    func testTheSelectorFallbackIsNotReachedOnModernMacOS() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/MenuBar.swift"),
            encoding: .utf8,
        )
        let body = try XCTUnwrap(
            source.range(of: "func openSettingsWindow()").map { String(source[$0.lowerBound...].prefix(900)) },
            "openSettingsWindow() not found",
        )
        let guardIndex = try XCTUnwrap(body.range(of: "#available(macOS 14, *) { return false }")?.lowerBound)
        let selectorIndex = try XCTUnwrap(body.range(of: "showPreferencesWindow:")?.lowerBound)
        XCTAssertLessThan(
            guardIndex, selectorIndex,
            """
            macOS 14+ must return false before reaching the pre-Ventura selector. sendAction returns
            true for it while opening nothing, so `open-settings` exits 0 having done nothing visible.
            """,
        )
    }

    /// And when it has been captured, it is used and reported as success.
    func testUsesTheCapturedOpenerAndReportsSuccess() {
        var called = 0
        settingsOpener = { called += 1 }

        XCTAssertTrue(openSettingsWindow())
        assertEquals(called, 1)
    }
}
