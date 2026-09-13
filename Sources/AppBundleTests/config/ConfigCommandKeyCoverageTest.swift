@testable import AppBundle
import Common
import XCTest

/// `config --get <key>` must be able to answer for every key the parser accepts.
///
/// `buildConfigMap` is a hand-maintained mirror of the parser's key set, and nothing kept the two in
/// sync. `show-menu-bar-icon` and `show-dock-icon` were added to the parser -- they configured the
/// running app correctly -- while `config --get show-dock-icon` replied "No value at key token", so
/// the only way to find out the current value was to read the TOML by hand.
@MainActor
final class ConfigCommandKeyCoverageTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testEveryParsedTopLevelKeyIsInspectable() {
        var inspectable: [String] = []
        buildConfigMap().dumpAllKeysRecursive(path: ".", result: &inspectable)
        // `dumpAllKeysRecursive` emits dotted paths like `.gaps.inner.horizontal`; a top-level key
        // is present if any path starts with it.
        let topLevel = Set(inspectable.map { $0.drop(while: { $0 == "." }).split(separator: ".").first.map(String.init) ?? "" })

        // Keys that legitimately have no effective value to report.
        //
        //   * the config v2 surface (`mod`, `workspaces`, `keys`, `monitors`, `on-window`) is input
        //     *sugar*: `parseConfigV2` desugars it into `mode` / `workspace-to-monitor-force-
        //     assignment`, and the v1 parser binds it to `_deprecatedNoOp`. `config --get` reports
        //     effective state, and the effective state IS those other keys.
        //   * the rest are deprecated no-ops that parse only so an old config still loads.
        //
        // Anything else missing is a key that configures the app but cannot be inspected.
        let inputSugarOrNoOp: Set<String> = [
            "mod", "workspaces", "keys", "monitors", "on-window",
            "after-login-command", "exec-on-workspace-change",
            "indent-for-nested-containers-with-the-same-orientation",
            "non-empty-workspaces-root-containers-layout-on-startup",
        ]
        // Upstream-only keys are accepted so a migrated config loads; they configure nothing.
        let missing = configParserKeys.subtracting(topLevel).subtracting(inputSugarOrNoOp)
            .subtracting(upstreamOnlyKeyParsers.keys).sorted()
        XCTAssertEqual(missing, [], "these keys parse but `config --get` cannot read them: \(missing)")
    }

    /// Counter-check: the comparison must be reading real data on both sides, or the test above
    /// passes vacuously when either map is empty.
    func testBothSidesAreNonEmpty() {
        var inspectable: [String] = []
        buildConfigMap().dumpAllKeysRecursive(path: ".", result: &inspectable)
        XCTAssertGreaterThan(configParserKeys.count, 15, "parser key set looks empty")
        XCTAssertGreaterThan(inspectable.count, 15, "config map looks empty")
    }
}
