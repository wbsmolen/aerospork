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

    override func setUp() async throws {
        saved = settingsOpener
    }

    override func tearDown() async throws {
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
        let body = try sourceBody("func openSettingsWindow()", in: "Sources/AppBundle/ui/MenuBar.swift")
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

    /// "Open in…" creates and opens the file the server reads. With `--config-path` naming a file not
    /// created yet, it used to create `~/.aerospork.toml` instead, which the server never reads, and a
    /// failed copy said nothing.
    func testOpenInEditorTargetsTheFileTheServerReads() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "open-in-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appending(path: "explicit.toml")
        var opened: [URL] = []

        XCTAssertNil(openConfigInExternalEditor(target: .success(target)) { opened.append($0) })
        assertEquals(opened, [target])
        assertEquals(try String(contentsOf: target, encoding: .utf8), try String(contentsOf: defaultConfigUrl, encoding: .utf8))

        // An existing file is opened as it is, not replaced by the default.
        try "accordion-padding = 7\n".write(to: target, atomically: true, encoding: .utf8)
        XCTAssertNil(openConfigInExternalEditor(target: .success(target)) { opened.append($0) })
        assertEquals(opened, [target, target])
        assertEquals(try String(contentsOf: target, encoding: .utf8), "accordion-padding = 7\n")

        // A copy that fails, and a target that cannot be resolved, are reported, and nothing opens.
        let unwritable = dir.appending(path: "missing-folder/explicit.toml")
        let copyFailure = try XCTUnwrap(openConfigInExternalEditor(target: .success(unwritable)) { opened.append($0) })
        XCTAssertTrue(copyFailure.contains(unwritable.path(percentEncoded: false)), copyFailure)
        assertEquals(openConfigInExternalEditor(target: .failure("Several config files exist")) { opened.append($0) }, "Several config files exist")
        assertEquals(opened.count, 2)
    }
}
