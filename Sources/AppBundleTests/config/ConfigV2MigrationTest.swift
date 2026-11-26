@testable import AppBundle
import Common
import Foundation
import TOMLKit
import XCTest

/// Migration from v1 to v2.
///
/// One invariant carries the whole feature: **the migrated config must parse to a `Config` equal to
/// the original**. `migrateToConfigV2` checks it itself and returns nil when it does not hold, so
/// these tests are also asserting that the runtime guard cannot be tricked into a false positive.
@MainActor
final class ConfigV2MigrationTest: XCTestCase {
    private func parsed(_ toml: String) -> Config {
        switch parseConfig(toml) {
            case .success(let config): return config
            case .failure(let errors): XCTFail("did not parse: \(errors.descriptions)"); return Config()
        }
    }

    /// Migrate, and prove the result describes the same window manager.
    @discardableResult
    private func migrate(_ v1: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        guard let v2 = migrateToConfigV2(v1) else {
            XCTFail("refused to migrate:\n\(v1)", file: file, line: line)
            return ""
        }
        XCTAssertTrue(configsAreEquivalent(parsed(v1), parsed(v2)), "migration changed the config:\n\(v2)", file: file, line: line)
        return v2
    }

    /// The v1 config the schema was designed against: i3 defaults plus thirty lines of workspace
    /// boilerplate.
    private var boilerplateV1: String {
        var lines = [
            "accordion-padding = 30",
            "[mode.main.binding]",
            "alt-h = 'focus left'", "alt-j = 'focus down'", "alt-k = 'focus up'", "alt-l = 'focus right'",
            "alt-shift-h = 'move left'", "alt-shift-j = 'move down'", "alt-shift-k = 'move up'", "alt-shift-l = 'move right'",
            "alt-minus = 'resize smart -50'", "alt-equal = 'resize smart +50'",
            "alt-slash = 'layout tiles horizontal vertical'", "alt-comma = 'layout accordion horizontal vertical'",
            "alt-tab = 'workspace-back-and-forth'",
        ]
        for i in 1 ... 9 {
            lines.append("alt-\(i) = 'workspace \(i)'")
            lines.append("alt-shift-\(i) = 'move-node-to-workspace \(i)'")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Collapsing

    func testBoilerplateCollapsesToModAndWorkspaces() {
        let v2 = migrate(boilerplateV1)
        XCTAssertTrue(v2.contains("mod = 'alt'") || v2.contains("mod = \"alt\""), v2)
        XCTAssertTrue(v2.contains("1-9"), "workspaces were not compacted into a range:\n\(v2)")
        XCTAssertFalse(v2.contains("workspace 5"), "boilerplate survived:\n\(v2)")
        XCTAssertFalse(v2.contains("[mode."), "v1 sections survived:\n\(v2)")
        // The headline claim: ~15 lines replacing 200.
        XCTAssertLessThan(v2.split(separator: "\n").count, boilerplateV1.split(separator: "\n").count / 2, v2)
    }

    /// Anything the collapser does not recognise is left as an explicit `[keys]` entry rather than
    /// guessed at.
    func testUnrecognisedBindingsSurviveVerbatim() {
        let v2 = migrate(boilerplateV1 + "\nalt-shift-semicolon = 'mode service'\nalt-q = ['close', 'focus left']")
        XCTAssertTrue(v2.contains("alt-shift-semicolon"), v2)
        XCTAssertTrue(v2.contains("alt-q"), v2)
    }

    /// A workspace binding whose partner is missing is NOT generated-looking, so both halves stay
    /// explicit -- generating the missing one would hand the user a binding they never had.
    func testHalfAWorkspacePairIsNotCollapsed() {
        let v2 = migrate(boilerplateV1 + "\nalt-z = 'workspace Z'")
        XCTAssertTrue(v2.contains("alt-z"), "the unpaired binding was swallowed:\n\(v2)")
    }

    /// Miss one i3 default and `mod` cannot explain the file, so nothing is generated and every
    /// binding is written out. Still a win (`[keys]` over `[mode.main.binding]`), still equivalent.
    func testConfigThatDoesNotMatchTheDefaultsGetsNoMod() {
        let v1 = boilerplateV1.replacingOccurrences(of: "alt-j = 'focus down'", with: "alt-j = 'close'")
        let v2 = migrate(v1)
        XCTAssertFalse(v2.contains("mod ="), "invented a mod that does not explain the file:\n\(v2)")
        XCTAssertTrue(v2.contains("[keys]"), v2)
    }

    func testNamedModesBecomeKeysSubTables() {
        let v2 = migrate(boilerplateV1 + "\n[mode.service.binding]\nesc = ['reload-config', 'mode main']")
        XCTAssertTrue(v2.contains("[keys.service]"), v2)
        assertEquals(parsed(v2).modes["service"]?.bindings.count, 1)
    }

    func testAssignmentsAreRenamedToMonitors() {
        let v2 = migrate(boilerplateV1 + "\n[workspace-to-monitor-force-assignment]\n2 = 'main'")
        XCTAssertTrue(v2.contains("[monitors]"), v2)
        XCTAssertFalse(v2.contains("workspace-to-monitor-force-assignment"), v2)
    }

    /// Everything the schema does not rename is copied across untouched.
    func testUnrelatedKeysSurvive() {
        let v2 = migrate("start-at-login = true\n" + boilerplateV1 + "\n[gaps]\ninner.horizontal = 4")
        let config = parsed(v2)
        assertEquals(config.startAtLogin, true)
        assertEquals(config.gaps.inner.horizontal, .constant(4))
        assertEquals(config.accordionPadding, 30)
    }

    // MARK: - When NOT to migrate

    func testAlreadyV2IsLeftAlone() {
        XCTAssertNil(migrateToConfigV2("mod = 'alt'\nworkspaces = '1-9'"))
        XCTAssertNil(migrateToConfigV2("[keys]\nalt-h = 'focus left'"))
    }

    /// Nothing to gain, and rewriting a file for no reason is its own kind of damage.
    func testConfigWithoutBindingsIsLeftAlone() {
        XCTAssertNil(migrateToConfigV2("accordion-padding = 30"))
    }

    /// A config that does not load is one we cannot prove anything about.
    func testUnparseableConfigIsLeftAlone() {
        XCTAssertNil(migrateToConfigV2("[mode.main.binding]\nalt-h = 'no-such-command'"))
        XCTAssertNil(migrateToConfigV2("this is not toml ["))
    }

    // MARK: - The real thing

    // MARK: - The oracle

    /// The migration rewrites the user's file, and `configsAreEquivalent` is its only safety net. It
    /// compared fields by hand, and skipped the two icon fields: a field added to `Config` escaped it
    /// with no word. Each field must make two configs differ, or be exempt here with its reason.
    func testEquivalenceCoversEveryConfigField() {
        let focus = parseCommand("focus left").cmdOrDie
        let changes: [String: (inout Config) -> Void] = [
            "afterStartupCommand": { $0.afterStartupCommand = [focus] },
            "enableNormalizationFlattenContainers": { $0.enableNormalizationFlattenContainers.toggle() },
            "defaultRootContainerLayout": { $0.defaultRootContainerLayout = .accordion },
            "defaultRootContainerOrientation": { $0.defaultRootContainerOrientation = .horizontal },
            "startAtLogin": { $0.startAtLogin.toggle() },
            "automaticallyUnhideMacosHiddenApps": { $0.automaticallyUnhideMacosHiddenApps.toggle() },
            "accordionPadding": { $0.accordionPadding += 1 },
            "enableNormalizationOppositeOrientationForNestedContainers": { $0.enableNormalizationOppositeOrientationForNestedContainers.toggle() },
            "execOnWorkspaceChange": { $0.execOnWorkspaceChange = ["/bin/echo"] },
            "keyMapping": { $0.keyMapping = KeyMapping(preset: .dvorak) },
            "execConfig": { $0.execConfig.envVariables = [:] },
            "onFocusChanged": { $0.onFocusChanged = [focus] },
            "onFocusedWorkspaceChanged": { $0.onFocusedWorkspaceChanged = [focus] },
            "onFocusedMonitorChanged": { $0.onFocusedMonitorChanged = [focus] },
            "gaps": { $0.gaps.inner = .init(vertical: 1, horizontal: 1) },
            "workspaceToMonitorForceAssignment": { $0.workspaceToMonitorForceAssignment = ["1": [.main]] },
            "modes": { $0.modes = self.parsed("[mode.main.binding]\nalt-h = 'focus left'").modes },
            "onWindowDetected": { $0.onWindowDetected = [WindowDetectedCallback(rawRun: [parseCommand("layout floating").cmdOrDie])] },
            "preservedWorkspaceNames": { $0.preservedWorkspaceNames = ["z"] },
            "autoMoveWorkspacesOnMonitorConnect": { $0.autoMoveWorkspacesOnMonitorConnect.toggle() },
            "showMenuBarIcon": { $0.showMenuBarIcon.toggle() },
            "showDockIcon": { $0.showDockIcon.toggle() },
        ]
        let exempt: [String: String] = [
            "_deprecatedNoOp": "a Void sink for keys the table walker must not write; it holds nothing",
            "persistentWorkspaces": "folding alt-1..9 into `workspaces` makes them persistent, deliberately",
        ]
        let fields = Mirror(reflecting: Config()).children.compactMap(\.label)
        assertEquals(Set(fields), Set(changes.keys).union(exempt.keys))

        let base = Config()
        XCTAssertTrue(configsAreEquivalent(base, base))
        for (field, change) in changes {
            var changed = base
            change(&changed)
            XCTAssertFalse(configsAreEquivalent(base, changed), "configsAreEquivalent does not compare \(field)")
        }

        // A rule that gains a regex matcher is a different rule.
        var rule = WindowDetectedCallback(rawRun: [parseCommand("layout floating").cmdOrDie])
        var plain = base
        plain.onWindowDetected = [rule]
        rule.matcher.windowTitleRegexSubstring = try? Regex("x")
        var matched = base
        matched.onWindowDetected = [rule]
        XCTAssertFalse(configsAreEquivalent(plain, matched))
    }

    // MARK: - The file migration

    private static let v1 = "[mode.main.binding]\nalt-h = 'focus left'\n"

    /// The `.pre-v2` copy was written fresh, so it got 0644 from the umask even when the config was
    /// 0600, and `[exec.env-vars]` can hold secrets.
    func testPreV2BackupKeepsTheOriginalMode() throws {
        let url = try useTemporaryConfig(Self.v1, for: self)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

        migrateConfigToV2(at: url)

        let backup = url.appendingPathExtension("pre-v2")
        assertEquals(try String(contentsOf: backup, encoding: .utf8), Self.v1)
        assertEquals(try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int, 0o600)
    }

    /// The migration's atomic write replaced a linked config with a regular file, as the Settings save did.
    func testMigrationThroughALinkKeepsTheLink() throws {
        let url = try useTemporaryConfig(Self.v1, for: self)
        let link = url.deletingLastPathComponent().appending(path: "link.toml")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)

        migrateConfigToV2(at: link)

        assertEquals(try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType, .typeSymbolicLink)
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("mode.main.binding"))
        let backup = link.appendingPathExtension("pre-v2")
        assertEquals(try FileManager.default.attributesOfItem(atPath: backup.path)[.type] as? FileAttributeType, .typeRegular)
        assertEquals(try String(contentsOf: backup, encoding: .utf8), Self.v1)
    }

    /// The measured 202-line config this schema was designed from. READ ONLY, and skipped when it is
    /// not on this machine -- but when it IS, it is the only test here whose input was written by a
    /// user rather than by the person implementing the feature.
    ///
    /// Prefers `.pre-v2`, because on a machine where the app has already run once, that is where the
    /// v1 original now lives.
    func testRealUserConfigMigratesEquivalently() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appending(path: ".aerospork-debug.toml.pre-v2"), home.appending(path: ".aerospork-debug.toml")]
        guard let v1 = candidates.lazy.compactMap({ try? String(contentsOf: $0, encoding: .utf8) })
            .first(where: { (try? TOMLTable(string: $0)).map { !isConfigV2($0) } == true })
        else {
            throw XCTSkip("no v1 config on this machine")
        }
        guard case .success = parseConfig(v1) else { throw XCTSkip("the local config does not currently parse") }
        let v2 = migrate(v1)
        XCTAssertLessThan(
            v2.split(separator: "\n").count,
            v1.split(separator: "\n").count,
            "migration made the config longer",
        )
    }
}
