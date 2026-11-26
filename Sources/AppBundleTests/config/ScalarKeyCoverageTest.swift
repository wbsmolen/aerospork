@testable import AppBundle
import Common
import XCTest

/// The scalar keys are listed by hand in the parser and in `Settings.scalarKeys`, which the panes load
/// and the writer diffs. A key added to the parser only configures the app, while Settings cannot show
/// or edit it, and nothing said so. `ConfigCommandKeyCoverageTest` does the same for `config --get`.
@MainActor
final class ScalarKeyCoverageTest: XCTestCase {
    /// Parser keys that are deliberately not in `Settings.scalarKeys`, each with why.
    private static let exempt: [String: String] = [
        // Compound sections: each has a pane or loader of its own, not a scalar row.
        "key-mapping": "the keyboard layout, read with the bindings",
        "mode": "bindings, the Bindings pane",
        "exec": "a table, the Callbacks pane's environment section",
        "gaps": "per-monitor values, the Gaps pane",
        "workspace-to-monitor-force-assignment": "the Monitors pane",
        "on-window-detected": "the Window rules pane",
        "persistent-workspaces": "a set of names, the Workspaces pane",
        // The v2 spelling, desugared into the sections above.
        "mod": "v2 spelling of the bindings",
        "workspaces": "v2 spelling of persistent workspaces and their monitors",
        "keys": "v2 spelling of the bindings",
        "monitors": "v2 spelling of the monitor assignments",
        "on-window": "v2 spelling of the window rules",
        // Deprecated: they load so an old config keeps working, and Settings must not offer them.
        "exec-on-workspace-change": "deprecated, use on-focused-workspace-changed",
        "after-login-command": "deprecated no-op",
        "non-empty-workspaces-root-containers-layout-on-startup": "deprecated no-op",
        "indent-for-nested-containers-with-the-same-orientation": "deprecated no-op",
    ]

    func testEveryScalarParserKeyIsEditableOrExempt() {
        let editable = Set(ConfigurationViewModel.Settings.scalarKeys.map(\.key))
        let missing = configParserKeys
            .subtracting(editable)
            .subtracting(Self.exempt.keys)
            .subtracting(upstreamOnlyKeyParsers.keys) // reported and ignored, they configure nothing
            .sorted()
        XCTAssertEqual(missing, [], "add these to Settings.scalarKeys, or to `exempt` with a reason: \(missing)")

        // An exemption for a key that is gone, or that Settings now edits, hides nothing and misleads.
        let stale = Set(Self.exempt.keys).subtracting(configParserKeys).union(editable.intersection(Self.exempt.keys)).sorted()
        XCTAssertEqual(stale, [], "remove these from `exempt`: \(stale)")
    }
}
