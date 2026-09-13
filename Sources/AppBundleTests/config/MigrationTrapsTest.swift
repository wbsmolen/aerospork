@testable import AppBundle
import Common
import Foundation
import XCTest

/// What an AeroSpace config trips over when it is dropped in unchanged (#40).
///
/// The worst of these was silent: an unknown top-level key is fatal, a fatal config is replaced by
/// the default, and the user gets a keymap they never wrote with nothing to say why.
@MainActor
final class MigrationTrapsTest: XCTestCase {
    private func parse(_ toml: String) -> (result: Result<Config, [TomlParseError]>, warnings: [String]) {
        var warnings: [TomlParseError] = []
        let result = parseConfig(toml, warnings: &warnings)
        return (result, warnings.map(\.description))
    }

    func testAeroSpaceOnlyKeysWarnInsteadOfDiscardingTheConfig() {
        let (result, warnings) = parse("""
            config-version = 2
            auto-reload-config = true
            on-mode-changed = []
            accordion-padding = 7

            [focus-follows-mouse]
            enabled = true
            """)
        guard case .success(let config) = result else { return XCTFail("the whole config was discarded: \(result)") }
        assertEquals(config.accordionPadding, 7, additionalMsg: "the rest of the config must still apply")
        for key in upstreamOnlyKeyParsers.keys {
            XCTAssertTrue(warnings.contains { $0.hasPrefix(key) }, "no warning for \(key): \(warnings)")
        }
    }

    /// Still an error -- the rule cannot be honoured -- but one that names the fix.
    func testAStringIfSaysWhatToWriteInstead() {
        let (result, _) = parse("""
            [[on-window-detected]]
            if = 'test %{app-bundle-id} == com.apple.finder'
            run = 'layout floating'
            """)
        guard case .failure(let errors) = result else { return XCTFail("a string `if` cannot be honoured and must not load") }
        XCTAssertTrue(errors.contains { $0.description.contains("if.app-id") }, "\(errors.map(\.description))")
    }

    /// `$AEROSPACE_FOCUSED_WORKSPACE` expands to nothing and `aerospace` is not on PATH, so a migrated
    /// status-bar hook runs and does nothing.
    func testAeroSpaceNamesInCommandsWarnButStillLoad() {
        let (result, warnings) = parse("""
            # AEROSPACE_FOCUSED_WORKSPACE became AEROSPORK_FOCUSED_WORKSPACE -- a comment must not warn
            exec-on-workspace-change = ['/bin/bash', '-c', 'sketchybar --trigger change FOCUSED=$AEROSPACE_FOCUSED_WORKSPACE']
            after-startup-command = ['exec-and-forget aerospace list-workspaces --all']
            """)
        if case .failure(let errors) = result { return XCTFail("\(errors.map(\.description))") }
        XCTAssertTrue(warnings.contains { $0.contains("Line 2") && $0.contains("AEROSPORK_") }, "\(warnings)")
        XCTAssertTrue(warnings.contains { $0.contains("Line 3") && $0.contains("`aerospork`") }, "\(warnings)")
        XCTAssertFalse(warnings.contains { $0.contains("Line 1") }, "a comment warned: \(warnings)")
    }

    func testAnAppIdContainingAerospaceIsNotACliCall() {
        XCTAssertTrue(upstreamNameWarnings("[on-window]\n'bobko.aerospace' = 'layout floating'\n").isEmpty)
    }

    func testAnAeroSpaceConfigLeftBehindIsFound() throws {
        let home = URL(filePath: NSTemporaryDirectory()).appending(path: "aerospace-hint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertNil(aerospaceConfigLeftBehind(home: home, xdgConfigHome: nil))

        let xdgDir = home.appending(path: ".config").appending(path: "aerospace")
        try FileManager.default.createDirectory(at: xdgDir, withIntermediateDirectories: true)
        try "".write(to: xdgDir.appending(path: "aerospace.toml"), atomically: true, encoding: .utf8)
        assertEquals(aerospaceConfigLeftBehind(home: home, xdgConfigHome: nil)?.lastPathComponent, "aerospace.toml")

        try "".write(to: home.appending(path: ".aerospace.toml"), atomically: true, encoding: .utf8)
        assertEquals(aerospaceConfigLeftBehind(home: home, xdgConfigHome: nil)?.lastPathComponent, ".aerospace.toml")
    }
}
