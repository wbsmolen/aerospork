@testable import AppBundle
import Common
import Foundation
import XCTest

/// Correctness regressions: the unbounded project-root walk, the
/// upstream branding leak in config keys and `exec` env vars, and the gaps collapse the v2
/// migration used to skip.
@MainActor
final class CleanupConfigTest: XCTestCase {
    // MARK: - Bounded project-root walk

    /// `deleteLastPathComponent()` does not stop at "/", so the old `while !exists(.git)` loop spun
    /// forever -- no error, no output, 100% CPU -- for sources outside a git checkout.
    func testGitRootAboveTerminatesWithoutARepo() {
        assertNil(gitRootAbove(URL(filePath: "/private/var/empty/aerospork-not-a-repo/Config.swift")))
    }

    func testGitRootAboveStillFindsThisCheckout() {
        let root = gitRootAbove(URL(filePath: #filePath))
        assertNotNil(root)
        assertTrue(FileManager.default.fileExists(atPath: root!.appending(component: ".git").path))
    }

    /// The tests' own root comes from `#filePath`, not a `.git` walk, so a tree with no `.git` runs too.
    func testProjectRootIsThePackageRoot() {
        assertTrue(FileManager.default.fileExists(atPath: projectRoot.appending(component: "Package.swift").path))
    }

    // MARK: - Source scans read whole declarations

    func testSourceBodyIsTheWholeDeclaration() throws {
        let source = """
            enum E {
                func a() {
                    if x {
                        // }
                        let s = "}"
                    }
                    last()
                }

                func b() {}
            }
            """
        let body = try XCTUnwrap(declarationBody("func a()", in: source))
        XCTAssertTrue(body.hasPrefix("    func a() {"), body)
        XCTAssertTrue(body.hasSuffix("        last()\n    }"), body)
        XCTAssertFalse(body.contains("func b"), body)
        XCTAssertFalse(body.contains("// }"), "comments are stripped")
    }

    /// `sourceBody` turns nil into a test failure.
    func testSourceBodyFailsWithoutItsClosingLine() {
        XCTAssertNil(declarationBody("func a()", in: "    func a() {\n        last()\n}\n"), "closed at the wrong indentation")
        XCTAssertNil(declarationBody("func gone()", in: "func a() {\n}\n"))
    }

    // MARK: - Branding: `during-aerospork-startup`

    private func startupMatcher(_ key: String) -> (Bool?, warnings: [String], errors: [String]) {
        let (config, warnings, errors) = parseWithWarnings(
            """
            [[on-window-detected]]
            if.app-id = 'com.apple.finder'
            if.\(key) = true
            run = ['layout floating']
            """,
        )
        return (config?.onWindowDetected.first?.matcher.duringAeroSporkStartup, warnings, errors)
    }

    func testNewStartupMatcherSpellingWorksSilently() {
        let (value, warnings, errors) = startupMatcher("during-aerospork-startup")
        assertEquals(errors, [])
        assertEquals(warnings, [])
        assertEquals(value, true)
    }

    /// The upstream-branded spelling was **removed**, not deprecated. It has to be a hard error, not
    /// a silently ignored key: an ignored `if.during-…-startup = true` turns a startup-only rule
    /// into one that fires for every matching window forever, which is worse than refusing to load.
    ///
    /// Breaking change for anyone migrating from upstream.
    func testOldStartupMatcherSpellingIsRejected() {
        let (value, _, errors) = startupMatcher("during-aerospace-startup")
        assertNil(value)
        assertEquals(errors.count, 1)
        // The backtrace has to name the offending key, or the user cannot find it in their file.
        XCTAssertTrue(errors.first?.contains("during-aerospace-startup") == true, errors.description)
    }

    /// Severity is carried by the error case, not by a set of deprecated *top-level* names -- the
    /// root key here (`on-window-detected`) is perfectly live.
    func testARealErrorInAWindowRuleIsStillFatal() {
        let (config, _, errors) = parseWithWarnings(
            """
            [[on-window-detected]]
            if.app-id = 'com.apple.finder'
            if.during-aerospork-startup = 'yes'
            run = ['layout floating']
            """,
        )
        assertNil(config)
        assertTrue(!errors.isEmpty)
    }

    // MARK: - Branding: exec-on-workspace-change env vars

    /// One spelling. The `AEROSPACE_*` aliases were removed, so a script still reading them gets an
    /// unset variable -- breaking change, documented in docs/guide.adoc and 06-decisions.md D2.
    func testWorkspaceChangeExportsOnlyAerosporkNames() {
        let env = workspaceChangeEnvVars(["PATH": "/usr/bin"], from: "1", to: "2")
        assertEquals(env["AEROSPORK_FOCUSED_WORKSPACE"], "2")
        assertEquals(env["AEROSPORK_PREV_WORKSPACE"], "1")
        assertNil(env["AEROSPACE_FOCUSED_WORKSPACE"])
        assertNil(env["AEROSPACE_PREV_WORKSPACE"])
        assertEquals(env["PATH"], "/usr/bin")
    }

    /// The other half of the same removal. `exec-and-forget` children read these to find out which
    /// window or workspace the command targeted.
    @MainActor
    func testCmdEnvExportsOnlyAerosporkNames() {
        let byWindow = CmdEnv(windowId: 42, workspaceName: nil, pwd: nil).asMap
        assertEquals(byWindow["AEROSPORK_WINDOW_ID"], "42")
        assertNil(byWindow["AEROSPACE_WINDOW_ID"])

        let byWorkspace = CmdEnv(windowId: nil, workspaceName: "web", pwd: nil).asMap
        assertEquals(byWorkspace["AEROSPORK_WORKSPACE"], "web")
        assertNil(byWorkspace["AEROSPACE_WORKSPACE"])
        // A window-targeted env must not also claim a workspace, and vice versa.
        assertNil(byWindow["AEROSPORK_WORKSPACE"])
        assertNil(byWorkspace["AEROSPORK_WINDOW_ID"])
    }

    /// A shipped `.app` whose `default-config.toml` resource is missing falls through to the project
    /// lookup — on a machine that has no `.git` anywhere above the *build-time* `#filePath`. That
    /// used to `die()`, turning one missing bundle resource into a startup crash for every user.
    ///
    /// It must degrade instead: return an unreadable URL so `defaultConfig` uses hardcoded defaults.
    func testMissingProjectRootDegradesInsteadOfTrapping() {
        let outsideAnyRepo = URL(filePath: "/private/tmp/definitely-not-a-git-checkout/Config.swift")
        let url = getDefaultConfigUrlFromProject(startingAt: outsideAnyRepo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "must be unreadable so the hardcoded defaults win")
        assertNil(try? String(contentsOf: url, encoding: .utf8))
    }

    /// ...and inside a checkout it still resolves the real file, or debug builds lose their defaults.
    func testInsideACheckoutItStillFindsTheDefaultConfig() {
        let url = getDefaultConfigUrlFromProject()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(url.path)")
    }

    // MARK: - v2 migration: gaps collapse

    private var minimalV1: String { "[mode.main.binding]\nalt-h = 'focus left'\n" }

    private func migrated(_ v1: String) -> String {
        guard let v2 = migrateToConfigV2(v1) else { XCTFail("refused to migrate:\n\(v1)"); return "" }
        return v2
    }

    func testUniformGapsCollapseToScalars() {
        let v2 = migrated(minimalV1 + """
            [gaps]
            inner.horizontal = 8
            inner.vertical = 8
            outer.top = 4
            outer.bottom = 4
            outer.left = 4
            outer.right = 4
            """)
        assertTrue(v2.contains("inner = 8"))
        assertTrue(v2.contains("outer = 4"))
        guard case .success(let config) = parseConfig(v2) else { return XCTFail("did not parse:\n\(v2)") }
        assertEquals(config.gaps.inner.vertical, .constant(8))
        assertEquals(config.gaps.outer.right, .constant(4))
    }

    /// The aliasing this collapse used to be skipped over: a missing edge parses as 0, so
    /// `{horizontal = 8}` is NOT `inner = 8`.
    func testPartialGapsAreNotCollapsed() {
        let v2 = migrated(minimalV1 + "[gaps]\ninner.horizontal = 8\n")
        assertTrue(!v2.contains("inner = 8"))
        guard case .success(let config) = parseConfig(v2) else { return XCTFail("did not parse:\n\(v2)") }
        assertEquals(config.gaps.inner.vertical, .constant(0))
        assertEquals(config.gaps.inner.horizontal, .constant(8))
    }

    /// Differing edges, and per-monitor values (an array, never an int), stay in the long form.
    func testNonUniformAndPerMonitorGapsAreNotCollapsed() {
        let v2 = migrated(minimalV1 + """
            [gaps]
            inner.horizontal = 8
            inner.vertical = 3
            outer.top = [{ monitor.main = 3 }, 6]
            outer.bottom = 6
            outer.left = 6
            outer.right = 6
            """)
        assertTrue(!v2.contains("inner = "))
        assertTrue(!v2.contains("outer = "))
    }
}
