@testable import AppBundle
import Common
import TOMLKit
import XCTest

/// Config v2: the schema that replaced 63 lines of `alt-N = 'workspace N'` boilerplate with two.
///
/// v2 is a front-end that desugars into the existing `Config`, so everything here is asserted
/// against the parsed `Config` -- the shape of the file changed, the shape of the program did not.
@MainActor
final class ConfigV2Test: XCTestCase {
    private func parse(_ toml: String) -> Config {
        switch parseConfig(toml) {
            case .success(let config): return config
            case .failure(let errors): XCTFail("did not parse: \(errors.descriptions)"); return Config()
        }
    }

    private func errors(_ toml: String) -> [String] {
        switch parseConfig(toml) {
            case .success: return []
            case .failure(let e): return e.map(\.description)
        }
    }

    /// key notation -> command, for one mode. The notation is what the user typed, which is what
    /// these tests are about.
    private func bindings(_ config: Config, _ mode: String = mainModeId) -> [String: String] {
        var result: [String: String] = [:]
        for binding in (config.modes[mode]?.bindings ?? [:]).values {
            result[binding.descriptionWithKeyNotation] = binding.commands.map { $0.args.description }.joined(separator: " ; ")
        }
        return result
    }

    // MARK: - Shape detection

    /// Nobody should have to write `version = 2`.
    func testSchemaIsDetectedByShape() {
        func isV2(_ toml: String) -> Bool { isConfigV2(try! TOMLTable(string: toml)) }
        XCTAssertTrue(isV2("mod = 'alt'"))
        XCTAssertTrue(isV2("workspaces = '1-9'"))
        XCTAssertTrue(isV2("[keys]\nalt-h = 'focus left'"))
        XCTAssertTrue(isV2("[monitors]\n1 = 'main'"))
        XCTAssertTrue(isV2("[on-window]\n'com.apple.mail' = 'layout floating'"))
        XCTAssertFalse(isV2("[mode.main.binding]\nalt-h = 'focus left'"))
        // Silence is v1: generation is opt-in, and an empty file must not sprout thirty bindings.
        XCTAssertFalse(isV2(""))
        XCTAssertFalse(isV2("accordion-padding = 30"))
    }

    // MARK: - Generated bindings

    func testModGeneratesTheI3Defaults() {
        let b = bindings(parse("mod = 'alt'"))
        assertEquals(b["alt-h"], "focus left")
        assertEquals(b["alt-shift-j"], "move down")
        assertEquals(b["alt-minus"], "resize smart -50")
        assertEquals(b["alt-equal"], "resize smart +50")
        assertEquals(b["alt-slash"], "layout tiles horizontal vertical")
        assertEquals(b["alt-comma"], "layout accordion horizontal vertical")
        assertEquals(b["alt-tab"], "workspace-back-and-forth")
        assertEquals(b.count, 13)
    }

    /// The whole point of the schema: two lines instead of sixty-three.
    func testWorkspacesGenerateSwitchAndMoveBindings() {
        let b = bindings(parse("mod = 'alt'\nworkspaces = '1-3'"))
        assertEquals(b["alt-1"], "workspace 1")
        assertEquals(b["alt-3"], "workspace 3")
        assertEquals(b["alt-shift-1"], "move-node-to-workspace 1")
        assertEquals(b["alt-shift-3"], "move-node-to-workspace 3")
        assertEquals(b.count, 13 + 6)
    }

    func testWorkspacesAcceptRangesListsAndBoth() {
        assertEquals(bindings(parse("mod = 'alt'\nworkspaces = ['dev', 'web']"))["alt-d"], "workspace dev")
        assertEquals(bindings(parse("mod = 'alt'\nworkspaces = ['dev', 'web']"))["alt-w"], "workspace web")
        // A hyphen in a multi-character name is a name, not a range.
        assertEquals(bindings(parse("mod = 'alt'\nworkspaces = ['my-space']"))["alt-m"], "workspace my-space")
        let both = bindings(parse("mod = 'alt'\nworkspaces = ['1-2', 'chat']"))
        assertEquals(both["alt-1"], "workspace 1")
        assertEquals(both["alt-c"], "workspace chat")
    }

    /// A capital workspace name is reached by the lower-case key -- `alt-A` is not a thing.
    func testWorkspaceKeyIsTheFirstCharacterLowerCased() {
        assertEquals(bindings(parse("mod = 'alt'\nworkspaces = ['A']"))["alt-a"], "workspace A")
    }

    /// A workspace with no shortcut is the worst possible outcome, so a clash is reported rather
    /// than resolved by whichever one the dictionary happened to iterate last.
    func testTwoWorkspacesSharingAKeyIsAnError() {
        XCTAssertTrue(
            errors("mod = 'alt'\nworkspaces = ['dev', 'docs']").contains { $0.contains("generated twice") },
            "\(errors("mod = 'alt'\nworkspaces = ['dev', 'docs']"))",
        )
    }

    func testUnknownModifierIsReported() {
        XCTAssertTrue(errors("mod = 'meta'").contains { $0.contains("is not a modifier") })
    }

    /// No `mod` means no generation. Without this, migrating a config whose bindings do NOT match
    /// the generated set would silently hand the user thirteen bindings they never had.
    func testWithoutModNothingIsGenerated() {
        let config = parse("[keys]\nalt-q = 'close'")
        assertEquals(bindings(config), ["alt-q": "close"])
    }

    // MARK: - [keys]

    func testKeysIsTheMainMode() {
        let config = parse("[keys]\nalt-h = 'focus left'")
        assertEquals(bindings(config), ["alt-h": "focus left"])
    }

    func testKeysSubTableIsANamedMode() {
        let config = parse("[keys.service]\nesc = ['reload-config', 'mode main']")
        assertEquals(bindings(config, "service"), ["esc": "reload-config ; mode main"])
        // `main` always exists in v2 -- there is nothing to declare.
        XCTAssertNotNil(config.modes[mainModeId])
    }

    /// "Anything in [keys] overrides a generated binding with the same key" -- defaults must never
    /// trap you.
    func testKeysOverridesAGeneratedBinding() {
        let b = bindings(parse("mod = 'alt'\n[keys]\nalt-h = 'close'"))
        assertEquals(b["alt-h"], "close")
        assertEquals(b["alt-j"], "focus down") // the rest still generated
    }

    /// The settings GUI writes `[mode.<name>.binding]` into whatever file it is handed, so a v2
    /// config that has been edited in the GUI is a mixture of both spellings and must keep loading.
    func testModeSectionStillWorksInV2AndWins() {
        let b = bindings(parse("mod = 'alt'\n[keys]\nalt-h = 'close'\n[mode.main.binding]\nalt-h = 'fullscreen'"))
        assertEquals(b["alt-h"], "fullscreen")
        assertEquals(errors("mod = 'alt'\n[mode.service.binding]\nesc = 'mode main'"), [])
    }

    /// v1 keeps its own rule: `[mode.*]` without `main` is a mistake there, because nothing else
    /// would supply it.
    func testV1StillRequiresTheMainMode() {
        assertEquals(errors("[mode.foo.binding]\nalt-h = 'focus left'"), ["mode: Please specify 'main' mode"])
    }

    // MARK: - Gaps, monitors, window rules

    func testScalarGapsBroadcastToEveryEdge() {
        let gaps = parse("mod = 'alt'\n[gaps]\ninner = 8\nouter = 12").gaps
        assertEquals(gaps.inner, Gaps.Inner(vertical: 8, horizontal: 8))
        assertEquals(gaps.outer, Gaps.Outer(left: 12, bottom: 12, top: 12, right: 12))
    }

    /// Scalar gaps are additive: the per-edge and per-monitor spellings still parse.
    func testPerEdgeAndPerMonitorGapsStillParse() {
        let gaps = parse("[gaps]\ninner = { horizontal = 1, vertical = 2 }\nouter = [{ monitor.main = 16 }, 8]").gaps
        assertEquals(gaps.inner.horizontal, .constant(1))
        assertEquals(gaps.inner.vertical, .constant(2))
        assertEquals(gaps.outer.top, .perMonitor([PerMonitorValue(description: .main, value: 16)], default: 8))
    }

    func testMonitorsReplacesTheLongAssignmentKey() {
        let config = parse("[monitors]\n1 = 'main'\n2 = { uuid = 'AAAAAAAA-0000-4000-8000-000000000001' }")
        assertEquals(config.workspaceToMonitorForceAssignment["1"]?.map(\.humanDescription), ["main"])
        assertEquals(
            config.workspaceToMonitorForceAssignment["2"]?.map(\.humanDescription),
            ["fingerprint(uuid AAAAAAAA-0000-4000-8000-000000000001)"],
        )
    }

    /// The v1 `{ fingerprint = { … } }` wrapper still parses -- the settings GUI writes it.
    func testWrappedFingerprintStillParses() {
        let config = parse("[monitors]\n2 = { fingerprint = { uuid = 'A' } }")
        assertEquals(config.workspaceToMonitorForceAssignment["2"]?.map(\.humanDescription), ["fingerprint(uuid A)"])
    }

    func testOnWindowIsTheCommonCaseOfOnWindowDetected() {
        let config = parse("[on-window]\n'com.apple.mail' = 'move-node-to-workspace 3'")
        assertEquals(config.onWindowDetected.count, 1)
        assertEquals(config.onWindowDetected.first?.matcher.appId, "com.apple.mail")
        assertEquals(config.onWindowDetected.first?.run.map { $0.args.description }, ["move-node-to-workspace 3"])
    }

    /// Same restrictions as the long form -- they are enforced by the same parser, not a copy of it.
    func testOnWindowRejectsCommandsTheLongFormRejects() {
        XCTAssertFalse(errors("[on-window]\n'com.apple.mail' = 'focus left'").isEmpty)
    }

    func testOnWindowAndOnWindowDetectedCoexist() {
        let config = parse("""
            [[on-window-detected]]
            if.app-id = 'com.apple.finder'
            run = ['layout floating']

            [on-window]
            'com.apple.mail' = 'layout floating'
            """)
        assertEquals(config.onWindowDetected.map { $0.matcher.appId }, ["com.apple.finder", "com.apple.mail"])
    }

    // MARK: - Workspace lifetime

    /// `getStubWorkspace` must not hijack a name the user has bound, and a generated binding is
    /// still a binding. (This is only the NAME set `getStubWorkspace` reads; keeping the workspaces
    /// themselves alive is `persistentWorkspaces`, pinned in `PersistentWorkspacesTest`.)
    func testGeneratedWorkspaceNamesArePreserved() {
        assertEquals(parse("mod = 'alt'\nworkspaces = '1-3'").preservedWorkspaceNames.toSet().sorted(), ["1", "2", "3"])
    }

    // MARK: - Settings GUI

    /// The view model shows ONE merged list of assignments, so a monitor edit has to remove both
    /// spellings of the section. Removing only the v1 name left `[monitors]` behind and resurrected
    /// every row the user had just deleted.
    func testEditingMonitorsInAV2ConfigDoesNotResurrectOldRows() {
        let base = "mod = 'alt'\n\n[monitors]\n1 = 'main'\n2 = 'secondary'\n"
        let vm = ConfigurationViewModel()
        vm.assignments = [.init(workspace: "1", monitor: "main"), .init(workspace: "2", monitor: "secondary")]
        vm.markLoaded()
        vm.assignments.removeLast()

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        assertEquals(errors(out), [])
        XCTAssertFalse(out.contains("secondary"), "deleted assignment came back:\n\(out)")
        XCTAssertTrue(out.contains("[monitors]"), "rewrote a v2 config into the v1 spelling:\n\(out)")
        assertEquals(parse(out).workspaceToMonitorForceAssignment.keys.sorted(), ["1"])
    }

    /// The GUI cannot see `[keys]` (it reads bindings out of `[mode.*]`), so it appends the v1
    /// spelling -- which is exactly why v2 keeps honouring it. What it must NOT do is break the file.
    func testAddingABindingToAV2ConfigStillLoads() {
        let base = "mod = 'alt'\nworkspaces = '1-3'\n\n[keys]\nalt-q = 'close'\n"
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.addBinding(mode: "main", key: "alt-shift-q", command: "focus left")

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        assertEquals(errors(out), [])
        let b = bindings(parse(out))
        assertEquals(b["alt-shift-q"], "focus left") // added
        assertEquals(b["alt-q"], "close") // [keys] survived
        assertEquals(b["alt-1"], "workspace 1") // generation survived
    }

    // MARK: - The shipped default

    func testShippedDefaultIsV2AndParses() throws {
        let text = try String(contentsOf: defaultConfigUrl, encoding: .utf8)
        XCTAssertTrue(isConfigV2(try TOMLTable(string: text)), "the shipped default is still v1")
        assertEquals(errors(text), [])
        let b = bindings(parse(text))
        assertEquals(b["alt-1"], "workspace 1")
        assertEquals(b["alt-9"], "workspace 9")
        assertEquals(b["alt-shift-semicolon"], "mode service")
        XCTAssertNotNil(parse(text).modes["service"])
    }
}
