@testable import AppBundle
import Common
import XCTest

/// Deprecations are warnings, not failures.
///
/// They used to be `.failure`, so a single legacy line made the whole config unloadable -- and the
/// startup fallback then replaced the user's entire keymap with the bundled default. Deleting one
/// obsolete key is not worth losing a config over.
@MainActor
final class ConfigSafetyDeprecationTest: XCTestCase {
    /// The regression that matters: everything else in the file must still take effect.
    func testOneDeprecatedKeyDoesNotCostTheUserTheirConfig() {
        let (config, warnings, errors) = parseWithWarnings(
            """
            after-login-command = ['workspace 1']
            accordion-padding = 42

            [mode.main.binding]
            alt-h = 'focus left'
            """,
        )
        assertEquals(errors, [])
        assertEquals(config?.accordionPadding, 42)
        assertEquals(config?.modes["main"]?.bindings.count, 1)
        assertEquals(warnings.count, 1)
    }

    /// Every key in the deprecated set, so adding one to `configParser` without adding it to
    /// `deprecatedKeys` -- which would silently make it fatal again -- fails here.
    func testEveryDeprecatedKeyOnlyWarns() {
        let samples = [
            "after-login-command = ['workspace 1']",
            "exec-on-workspace-change = ['/bin/true']",
            "non-empty-workspaces-root-containers-layout-on-startup = 'smart'",
            "indent-for-nested-containers-with-the-same-orientation = 1",
        ]
        for sample in samples {
            let (config, warnings, errors) = parseWithWarnings(sample)
            assertEquals(errors, [], additionalMsg: sample)
            XCTAssertNotNil(config, sample)
            assertEquals(warnings.count, 1, additionalMsg: sample)
        }
    }

    /// A key that is accepted and does nothing is a lie. `[]` used to be accepted in silence.
    func testNoOpKeysSayTheyAreNoOps() {
        assertEquals(parseWithWarnings("after-login-command = []").warnings.count, 1)
        assertEquals(
            parseWithWarnings("non-empty-workspaces-root-containers-layout-on-startup = 'smart'").warnings.count,
            1,
        )
    }

    /// The dead key made live. Its consumer in `focus.swift` was unreachable while the parser
    /// accepted only `[]`.
    func testExecOnWorkspaceChangeReachesTheConfig() {
        let (config, _, errors) = parseWithWarnings("exec-on-workspace-change = ['/bin/bash', '-c', 'echo hi']")
        assertEquals(errors, [])
        assertEquals(config?.execOnWorkspaceChange, ["/bin/bash", "-c", "echo hi"])
    }

    /// Warning severity is keyed on the deprecated key, not on the message text: a real mistake in
    /// a live key must still refuse the config.
    func testRealErrorsStillFail() {
        let (config, _, errors) = parseWithWarnings("accordion-padding = 'thirty'")
        XCTAssertNil(config)
        assertEquals(errors.count, 1)
    }

    /// An unknown key is not a deprecation. The parser is strict on purpose -- a typo'd key that
    /// loads silently does nothing and is impossible to debug.
    func testUnknownKeysStillFail() {
        XCTAssertNil(parseWithWarnings("after-login-comand = []").0)
    }
}
