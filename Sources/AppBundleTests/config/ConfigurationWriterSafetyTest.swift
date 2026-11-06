@testable import AppBundle
import Common
import XCTest

/// Regression tests for the settings writer.
///
/// Every case here was a CONFIRMED defect: the writer either produced clean-parsing TOML with the
/// user's data quietly removed, or produced a duplicate-key parse error that blocked all future
/// saves. They are grouped by the guarantee they defend.
@MainActor
final class ConfigurationWriterSafetyTest: XCTestCase {
    private func errors(_ toml: String) -> [String] {
        switch parseConfig(toml) {
            case .success: return []
            case .failure(let e): return e.map(\.description)
        }
    }

    /// A view model that believes `base` is what it loaded.
    private func loadedVM() -> ConfigurationViewModel {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        return vm
    }

    /// `base` loaded, `edit` applied, and what a save would do with the result.
    private func save(_ base: String, _ edit: (ConfigurationViewModel) -> Void) -> (refusal: String?, out: String) {
        let vm = ConfigurationViewModel()
        defer { vm.cancelPendingAutoSave() }
        vm.load(fromText: base)
        edit(vm)
        let out = ConfigurationWriter.render(baseText: base, from: vm)
        return (ConfigurationWriter.refusal(rendered: out, base: base, from: vm), out)
    }

    private func editGaps(_ vm: ConfigurationViewModel) { vm.settings.gaps.innerHorizontal += 1 }
    private func editPadding(_ vm: ConfigurationViewModel) { vm.settings.general.accordionPadding = 4242 }

    // MARK: - A spelling the writer can't edit is refused when the edit touches it, and only then

    func testEditingAMultiLineArrayIsRefused() {
        let base = """
            after-startup-command = [
                'exec-and-forget echo one',
            ]
            """
        XCTAssertNotNil(save(base) { $0.settings.callbacks.afterStartup = [.init(command: "exec-and-forget echo two")] }.refusal)
    }

    /// The up-front refusal this replaced locked the whole file out over one multi-line value.
    func testAnUnrelatedEditLeavesAMultiLineArrayAlone() {
        let base = """
            after-startup-command = [
                'exec-and-forget echo one',
            ]
            accordion-padding = 30
            """
        let (refusal, out) = save(base, editPadding)
        assertNil(refusal)
        XCTAssertTrue(out.contains("after-startup-command = [\n    'exec-and-forget echo one',\n]"), out)
        XCTAssertTrue(out.contains("accordion-padding = 4242"), out)
    }

    func testAQuotedTopLevelKeyIsReplacedNotDuplicated() {
        let (refusal, out) = save("'start-at-login' = false") { $0.settings.general.startAtLogin = true }
        assertNil(refusal)
        assertEquals(out, "start-at-login = true")
    }

    func testDottedAndInlineSpellingsAreRefusedOnlyWhenEdited() {
        XCTAssertNotNil(save("gaps.inner.horizontal = 5", editGaps).refusal)
        assertNil(save("gaps.inner.horizontal = 5", editPadding).refusal)
        XCTAssertNotNil(save("exec = { inherit-env-vars = false }") { $0.settings.exec.inheritEnvVars = true }.refusal)
        assertNil(save("exec = { inherit-env-vars = false }", editPadding).refusal)
    }

    /// These all load, and the shape guard waved the inline table and the spaced header through. The
    /// writer finds no line for them, so the edit used to do nothing while the UI reported success.
    func testABindingWithNoLineToEditIsRefusedRatherThanSilentlyIgnored() {
        for base in [
            "[mode.main]\nbinding.alt-h = 'focus left'",
            "[mode.main]\nbinding = { alt-h = 'focus left' }",
            "[ mode . main . binding ]\nalt-h = 'focus left'",
            "mod = 'alt'\nkeys = { alt-h = 'focus left' }",
        ] {
            func row(_ vm: ConfigurationViewModel) -> ConfigurationViewModel.BindingRow.ID { vm.settings.modes[0].bindings[0].id }
            XCTAssertNotNil(save(base) { vm in vm.updateBinding(mode: mainModeId, id: row(vm), command: "focus right") }.refusal, base)
            XCTAssertNotNil(save(base) { vm in vm.removeBinding(mode: mainModeId, id: row(vm)) }.refusal, base)
            assertEquals(save(base, editPadding).refusal, nil, additionalMsg: base)
        }
    }

    func testAFingerprintSubTableIsRefusedOnlyForItsOwnRow() {
        let base = """
            [monitors.2.fingerprint]
            uuid = '11111111-2222-3333-4444-555555555555'
            """
        XCTAssertNotNil(save(base) { $0.setAssignment(workspace: "2", monitorToken: "main") }.refusal)
        XCTAssertNotNil(save(base) { vm in vm.removeAssignment(id: vm.settings.assignments[0].id) }.refusal)
        let (refusal, out) = save(base) { $0.setAssignment(workspace: "3", monitorToken: "main") }
        assertNil(refusal)
        XCTAssertTrue(out.hasPrefix(base), out)
    }

    /// Saved whole, `[key-mapping]` lost everything but `preset`.
    func testAPresetEditKeepsWhatThePaneDoesNotModel() {
        let base = """
            [key-mapping]
            # my keyboard
            preset = 'qwerty'
            key-notation-to-key-code.unicorn = 'u'
            """
        let (refusal, out) = save(base) { $0.settings.keyMappingPreset = "dvorak" }
        assertNil(refusal)
        assertEquals(out, base.replacingOccurrences(of: "qwerty", with: "dvorak"))
    }

    /// `render` is not trusted to have done what it was asked: an edit that did not reach the file...
    func testAnEditThatDidNotReachTheFileIsRefused() {
        let base = "accordion-padding = 30\n"
        let vm = ConfigurationViewModel()
        vm.load(fromText: base)
        vm.settings.general.accordionPadding = 42
        XCTAssertNotNil(ConfigurationWriter.refusal(rendered: base, base: base, from: vm))
    }

    /// ...and a change to anything else, including keys no pane models and so no snapshot can see.
    func testAChangeOutsideTheEditedSectionIsRefused() {
        let base = "accordion-padding = 30\npersistent-workspaces = ['web']\n"
        let vm = ConfigurationViewModel()
        vm.load(fromText: base)
        vm.settings.general.accordionPadding = 42
        let good = ConfigurationWriter.render(baseText: base, from: vm)
        assertNil(ConfigurationWriter.refusal(rendered: good, base: base, from: vm))
        let damaged = good.replacingOccurrences(of: "['web']", with: "['mail']")
        XCTAssertNotNil(ConfigurationWriter.refusal(rendered: damaged, base: base, from: vm))
    }

    /// A surgery failure must not surface as a parser complaint about a line the user never wrote, but
    /// a bad command is the user's to fix, and has to be named.
    func testABadCommandIsReportedAsItself() {
        let (refusal, _) = save("") { $0.settings.callbacks.afterStartup = [.init(command: "no-such-command")] }
        XCTAssertTrue(refusal?.contains("no-such-command") == true, refusal ?? "nil")
    }

    /// Per-key edits take the last row with a name, so a duplicate would silently lose one.
    func testTwoRowsWithOneNameAreReportedByName() {
        let (monitors, _) = save("") {
            $0.settings.assignments = [.init(workspace: "1", monitor: "main"), .init(workspace: "1", monitor: "secondary")]
        }
        XCTAssertTrue(monitors?.contains("workspace '1'") == true, monitors ?? "nil")
        let (env, _) = save("") { $0.settings.exec.envVars = [.init(name: "A", value: "1"), .init(name: "A", value: "2")] }
        XCTAssertTrue(env?.contains("'A'") == true, env ?? "nil")
    }

    /// A file with both line endings can't be given back as it arrived once it has been split, so an
    /// edit is refused. Nothing edited is the file as it was, whatever its line endings.
    func testMixedLineEndingsAreLeftAloneAndNotEdited() {
        let base = "accordion-padding = 30\r\nstart-at-login = false\n"
        let (noOpRefusal, noOp) = save(base) { _ in }
        assertNil(noOpRefusal)
        assertEquals(noOp, base)
        XCTAssertNotNil(save(base, editPadding).refusal)
    }

    /// The shipped default must stay inside what the writer can edit, or new users hit refusals.
    func testShippedDefaultConfigIsEditable() throws {
        let text = try String(contentsOf: defaultConfigUrl, encoding: .utf8)
        assertEquals(errors(text), [])
        let edits: [(String, (ConfigurationViewModel) -> Void)] = [
            ("nothing", { _ in }),
            ("a scalar", editPadding),
            ("a callback", { $0.settings.callbacks.onFocusChanged = [.init(command: "move-mouse window-lazy-center")] }),
            ("gaps", editGaps),
            ("a pin", { $0.setAssignment(workspace: "1", monitorToken: "main") }),
            ("the preset", { $0.settings.keyMappingPreset = "dvorak" }),
            ("exec", { $0.settings.exec.inheritEnvVars.toggle() }),
            ("an env var", { $0.settings.exec.envVars.append(.init(name: "FOO", value: "bar")) }),
            ("a rule", { $0.settings.windowRules.append(.init(appId: "com.example.app", run: "layout floating")) }),
            ("a binding", { $0.addBinding(mode: mainModeId, key: "alt-f13", command: "focus left") }),
            ("a named mode", { $0.addBinding(mode: "resize", key: "esc", command: "mode main") }),
        ]
        for (name, edit) in edits {
            let (refusal, out) = save(text, edit)
            assertEquals(refusal, nil, additionalMsg: "the shipped default refuses an edit to \(name)")
            assertEquals(errors(out), [])
        }
    }

    /// Ordinary configs must NOT be refused -- the guard has to be narrow to be useful.
    func testOrdinaryConfigIsNotRefused() {
        let base = """
            start-at-login = false

            [gaps]
            inner.horizontal = 3

            [gaps.outer]
            top = 8

            [mode.main.binding]
            alt-h = 'focus left'

            [[on-window-detected]]
            if.app-id = 'com.apple.finder'
            run = ['layout floating']
            """
        assertEquals(save(base, editGaps).refusal, nil, additionalMsg: "false positive on a normal config")
        assertEquals(save(base, editPadding).refusal, nil, additionalMsg: "false positive on a normal config")
    }

    // MARK: - Per-key edits leave the rest of the section alone

    func testAMonitorEditChangesOneLineOfTheSection() {
        let base = """
            [monitors] # my desk
            # the big one
            1 = "main" # left
            2 = { fingerprint = { display_name = 'ACME Display 32 (1)', height = 2160, width = 3840 } }
            '3' = ['secondary', 'built-in']

            # banner for the next section
            [gaps]
            inner = 8
            """
        let (refusal, out) = save(base) { $0.setAssignment(workspace: "1", monitorToken: "secondary") }
        assertNil(refusal)
        assertEquals(out, base.replacingOccurrences(of: "1 = \"main\" # left", with: "1 = 'secondary' # left"))
    }

    func testAddingAndRemovingARowLeavesItsSiblingsAlone() {
        let base = """
            [workspace-to-monitor-force-assignment]
            1 = "main"
            2 = 'secondary'

            [gaps]
            inner = 8
            """
        let (added, withRow) = save(base) { $0.setAssignment(workspace: "3", monitorToken: "2") }
        assertNil(added)
        assertEquals(withRow, base.replacingOccurrences(of: "2 = 'secondary'", with: "2 = 'secondary'\n3 = 2"))

        let (removed, withoutRow) = save(base) { vm in vm.removeAssignment(id: vm.settings.assignments[0].id) }
        assertNil(removed)
        assertEquals(withoutRow, base.replacingOccurrences(of: "1 = \"main\"\n", with: ""))
    }

    func testRenamingAWorkspaceMovesItsPin() {
        let base = "[monitors]\n1 = 'main'\n"
        let (refusal, out) = save(base) { $0.settings.assignments[0].workspace = "web" }
        assertNil(refusal)
        assertEquals(out, "[monitors]\nweb = 'main'\n".replacingOccurrences(of: "'main'", with: "'main'"))
    }

    func testAnExecEditChangesOneLineOfTheSection() {
        let base = """
            [exec]
            # keep this
            inherit-env-vars = true

            [exec.env-vars]
            # and this
            PATH = "/usr/bin:${PATH}"
            'MY VAR' = "x" # and this
            """
        let (inherit, offOut) = save(base) { $0.settings.exec.inheritEnvVars = false }
        assertNil(inherit)
        assertEquals(offOut, base.replacingOccurrences(of: "inherit-env-vars = true", with: "inherit-env-vars = false"))

        let (value, valueOut) = save(base) { vm in vm.settings.exec.envVars[0].value = "y" }
        assertNil(value)
        assertEquals(valueOut, base.replacingOccurrences(of: "'MY VAR' = \"x\" # and this", with: "'MY VAR' = 'y' # and this"))

        let (added, addedOut) = save(base) { $0.settings.exec.envVars.append(.init(name: "FOO", value: "bar")) }
        assertNil(added)
        assertEquals(addedOut, base + "\nFOO = 'bar'")
    }

    /// Half-typed rows stay on screen and off the file, and do not count as a change to it.
    func testBlankRowsAreHeldBack() {
        let base = "accordion-padding = 30\n"
        let (refusal, out) = save(base) {
            $0.addAssignment()
            $0.settings.exec.envVars.append(.init(name: " ", value: "x"))
            $0.settings.callbacks.onFocusChanged.append(.init(command: ""))
            $0.addMode("empty")
        }
        assertNil(refusal)
        assertEquals(out, base)
    }

    func testGapsStayWhereTheyAre() {
        let base = """
            accordion-padding = 30

            [mode.main.binding]
            alt-h = 'focus left'

            # tuned for the big panel
            [gaps]
            inner = 8

            # banner for the rules
            [[on-window-detected]]
            run = 'layout floating'
            """
        let (refusal, out) = save(base, editGaps)
        assertNil(refusal)
        let order = ["alt-h", "# tuned for the big panel", "[gaps]", "inner.horizontal = 9", "# banner for the rules", "[[on-window-detected]]"]
        let positions = order.map { out.range(of: $0)?.lowerBound }
        XCTAssertFalse(positions.contains(nil), out)
        assertEquals(positions.compactMap { $0 }, positions.compactMap { $0 }.sorted(), additionalMsg: out)
    }

    // MARK: - The writer emits one spelling

    func testNewSectionsUseTheV2Spelling() {
        let (refusal, out) = save("accordion-padding = 30\n") {
            $0.addBinding(mode: mainModeId, key: "alt-h", command: "focus left")
            $0.addBinding(mode: "resize", key: "esc", command: "mode main")
            $0.setAssignment(workspace: "1", monitorToken: "main")
            $0.settings.windowRules = [.init(appId: "com.apple.finder", run: "layout floating")]
        }
        assertNil(refusal)
        for header in ["[keys]", "[keys.resize]", "[monitors]", "[on-window]"] { XCTAssertTrue(out.contains(header), out) }
        for header in ["[mode.", "[workspace-to-monitor-force-assignment]", "[[on-window-detected]]"] { XCTAssertFalse(out.contains(header), out) }
        assertEquals(errors(out), [])
    }

    /// Editing a v1 section stays in it. The whole-file conversion belongs to the migration, which
    /// keeps a copy of the original; a GUI edit must not spread a schema change across untouched rows.
    func testAnExistingV1SectionIsEditedInPlace() {
        let base = """
            [mode.main.binding]
            alt-h = 'focus left'

            [workspace-to-monitor-force-assignment]
            1 = 'main'
            """
        let (refusal, out) = save(base) {
            $0.addBinding(mode: mainModeId, key: "alt-j", command: "focus down")
            $0.setAssignment(workspace: "2", monitorToken: "main")
        }
        assertNil(refusal)
        assertEquals(out, base
            .replacingOccurrences(of: "alt-h = 'focus left'", with: "alt-h = 'focus left'\nalt-j = 'focus down'")
            .replacingOccurrences(of: "1 = 'main'", with: "1 = 'main'\n2 = 'main'"))
    }

    /// `[mode.*]` overrides `[keys]`, so the line to change is the one that wins, and removing only that
    /// one would bring the other back.
    func testABindingInBothSpellingsEditsTheWinnerAndRemovesBoth() {
        let base = """
            mod = 'alt'

            [keys]
            alt-h = 'focus left'

            [mode.main.binding]
            alt-h = 'focus right'
            """
        func row(_ vm: ConfigurationViewModel) -> ConfigurationViewModel.BindingRow.ID { vm.settings.modes[0].bindings[0].id }
        let (edit, edited) = save(base) { vm in vm.updateBinding(mode: mainModeId, id: row(vm), command: "focus up") }
        assertNil(edit)
        assertEquals(edited, base.replacingOccurrences(of: "focus right", with: "focus up"))

        let (remove, removed) = save(base) { vm in vm.removeBinding(mode: mainModeId, id: row(vm)) }
        assertNil(remove)
        XCTAssertFalse(removed.contains("alt-h"), removed)
    }

    /// One table drives load, diff and the parse-back check, so it has to name real keys, and each of
    /// them has to survive being written and read back.
    func testEveryScalarKeyRoundTrips() {
        let table = ConfigurationViewModel.Settings.scalarKeys
        assertEquals(table.count, 14)
        assertEquals(Set(table.map(\.key)).count, table.count)
        XCTAssertTrue(Set(table.map(\.key)).isSubset(of: configParserKeys))

        var edited = ConfigurationViewModel.Settings()
        edited.general.startAtLogin = true
        edited.general.automaticallyUnhideMacosHiddenApps = true
        edited.general.defaultRootContainerLayout = "accordion"
        edited.general.defaultRootContainerOrientation = "vertical"
        edited.general.accordionPadding = 12
        edited.general.enableNormalizationFlattenContainers = false
        edited.general.enableNormalizationOppositeOrientation = false
        edited.general.autoMoveWorkspacesOnMonitorConnect = false
        edited.general.showMenuBarIcon = false
        edited.general.showDockIcon = true
        edited.callbacks.afterStartup = [.init(command: "focus left")]
        edited.callbacks.onFocusChanged = [.init(command: "focus right")]
        edited.callbacks.onFocusedWorkspaceChanged = [.init(command: "focus up")]
        edited.callbacks.onFocusedMonitorChanged = [.init(command: "focus down")]

        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.settings = edited
        for key in table { XCTAssertNotEqual(key.literal(edited), key.literal(vm.loaded), "\(key.key) didn't change, so this test proves nothing") }
        let out = ConfigurationWriter.render(baseText: "", from: vm)
        assertEquals(errors(out), [])
        assertNil(ConfigurationWriter.refusal(rendered: out, base: "", from: vm))
        vm.load(fromText: out)
        for key in table { assertEquals(key.literal(vm.settings), key.literal(edited), additionalMsg: key.key) }
    }

    // MARK: - Silent data loss

    /// Re-binding a key used to write nothing while the UI reported success.
    func testRebindingExistingKeyIsWritten() {
        let base = """
            [mode.main.binding]
            alt-h = 'focus left'
            """
        let vm = ConfigurationViewModel()
        vm.settings.modes = [.init(mode: "main", bindings: [.init(key: "alt-h", command: "focus left")])]
        vm.markLoaded()
        vm.addBinding(mode: "main", key: "alt-h", command: "focus right")

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertTrue(out.contains("focus right"), "rebind was silently dropped:\n\(out)")
        XCTAssertFalse(out.contains("focus left"), "old command survived:\n\(out)")
        assertEquals(errors(out), [])
    }

    /// Removing one section must not swallow the comments documenting the NEXT one.
    func testCommentsBeforeAnUntouchedSectionSurvive() {
        let base = """
            [exec]
            inherit-env-vars = true

            # my carefully documented gaps
            [gaps]
            inner.horizontal = 3
            """
        let vm = ConfigurationViewModel()
        vm.settings.exec.inheritEnvVars = true
        vm.markLoaded()
        vm.settings.exec.inheritEnvVars = false

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertTrue(out.contains("# my carefully documented gaps"), "comment was eaten:\n\(out)")
    }

    /// `if.during-aerospork-startup` had no field in the row model, so any edit deleted it --
    /// turning a startup-only rule into one that fires for every matching window forever.
    func testWindowRuleDuringStartupSurvivesAnEdit() {
        let base = """
            [[on-window-detected]]
            if.app-id = 'com.apple.finder'
            if.during-aerospork-startup = true
            run = ['layout floating']
            """
        let vm = ConfigurationViewModel()
        vm.settings.windowRules = [.init(
            appId: "com.apple.finder",
            run: "layout floating",
            duringStartup: true,
        )]
        vm.markLoaded()
        vm.settings.windowRules[0].workspace = "5"

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        // What must never happen is the matcher disappearing.
        XCTAssertTrue(out.contains("during-aerospork-startup"), "startup matcher dropped:\n\(out)")
        assertEquals(errors(out), [])

        // ...and it round-trips: reading `out` back must still see a startup-only rule.
        let reloaded = ConfigurationViewModel()
        reloaded.load(fromText: out)
        assertEquals(reloaded.settings.windowRules.first?.duringStartup, true)
    }

    // MARK: - Output must be valid TOML

    func testKeysNeedingQuotesAreQuoted() {
        let vm = loadedVM()
        vm.settings.exec.envVars = [.init(name: "MY VAR", value: "x")]
        vm.settings.assignments = [.init(workspace: "my workspace", monitor: "main")]

        let out = ConfigurationWriter.render(baseText: "", from: vm)
        assertEquals(errors(out), [])
    }

    /// A bare monitor string is parsed as a REGEX, so a literal display name containing regex
    /// metacharacters never matched. macOS names duplicate panels exactly that way.
    func testMonitorNameIsNotEmittedAsABareRegex() {
        let vm = loadedVM()
        vm.settings.assignments = [.init(workspace: "1", monitor: "ACME Display 32 (1)")]

        let out = ConfigurationWriter.render(baseText: "", from: vm)
        assertEquals(errors(out), [])
        XCTAssertFalse(
            out.contains("1 = 'ACME Display 32 (1)'"),
            "emitted as a regex that cannot match its own display:\n\(out)",
        )
    }

    // MARK: - Line endings

    /// A CRLF config used to be corrupted on every structured edit. `sectionHeaderName` requires a
    /// line to END with "]", and splitting on "\n" alone leaves "[gaps]\r" -- so neither the writer
    /// nor the shape guard recognised the section, and the writer appended a SECOND [gaps] table.
    /// The property fuzzer attributed the majority of its findings to this one cause.
    func testCrlfConfigIsNotCorrupted() {
        let base = "accordion-padding = 30\r\n\r\n[gaps]\r\ninner.horizontal = 3\r\n"
        let vm = ConfigurationViewModel()
        vm.settings.general.accordionPadding = 30
        vm.settings.gaps.innerHorizontal = 3
        vm.markLoaded()
        vm.settings.gaps.innerHorizontal = 9

        XCTAssertNil(ConfigurationWriter.unsupportedShapeReason(base))
        let out = ConfigurationWriter.render(baseText: base, from: vm)
        assertEquals(errors(out), [])
        XCTAssertEqual(out.components(separatedBy: "[gaps]").count - 1, 1, "duplicated the section:\n\(out)")
        XCTAssertTrue(out.contains("\r\n"), "silently rewrote the file's line endings:\n\(out.debugDescription)")
    }

    // MARK: - Raw TOML must not act without Apply

    /// An unapplied raw buffer used to hijack an unrelated structured edit: the toggle was
    /// discarded and the half-finished raw text was committed without Apply ever being pressed.
    func testUnappliedRawTomlDoesNotHijackStructuredEdit() {
        let base = "accordion-padding = 30\nstart-at-login = false\n"
        let vm = ConfigurationViewModel()
        vm.rawToml = base
        vm.settings.general.accordionPadding = 30
        vm.settings.general.startAtLogin = false
        vm.markLoaded()

        vm.rawToml = "accordion-padding = 30\n" // edited, NOT applied
        vm.settings.general.startAtLogin = true // unrelated structured edit

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertTrue(out.contains("start-at-login = true"), "structured edit was discarded:\n\(out)")
    }

    func testRawTomlWinsOnlyWhenApplyRequested() {
        let vm = loadedVM()
        vm.rawToml = "accordion-padding = 7\n"
        vm.settings.general.accordionPadding = 999
        vm.rawTomlApplyRequested = true

        assertEquals(ConfigurationWriter.render(baseText: "accordion-padding = 30", from: vm), "accordion-padding = 7\n")
    }
}

/// The damage this guard exists to prevent, taken verbatim from a real config it destroyed.
@MainActor
final class MonitorFingerprintNotDegradedTest: XCTestCase {
    private func errors(_ toml: String) -> [String] {
        switch parseConfig(toml) {
            case .success: return []
            case .failure(let e): return e.map(\.description)
        }
    }

    /// Two physically identical panels. `display_name` alone cannot tell them apart on reconnect --
    /// the `(1)`/`(2)` suffixes are assigned by connection order -- so the config pins them by
    /// resolution as well. The view model can only hold one token per assignment, and
    /// `formatMonitorValue` can only emit a name, so a rewrite replaced both lines with bare names
    /// and threw the disambiguation away.
    private static let realConfig = """
        [monitors]
        2 = { fingerprint = { display_name = 'ACME Display 32 (1)', height = 2160, width = 3840 } }
        3 = { fingerprint = { display_name = 'ACME Display 32 (2)', height = 2160, width = 3840 } }
        """

    /// This config used to be refused outright, and then re-spelled from what each row remembered.
    /// Now a save simply leaves the rows it isn't editing alone -- the resolution fields that tell the
    /// two identical panels apart must survive an edit to a *different* row.
    func testARicherFingerprintIsPreservedNotRefused() {
        let vm = ConfigurationViewModel()
        defer { vm.cancelPendingAutoSave() }
        vm.load(fromText: Self.realConfig)
        vm.markLoaded()
        vm.setAssignment(workspace: "9", monitorToken: "AAAAAAAA-0000-4000-8000-000000000001")

        let out = ConfigurationWriter.render(baseText: Self.realConfig, from: vm)
        assertNil(ConfigurationWriter.refusal(rendered: out, base: Self.realConfig, from: vm))
        assertEquals(errors(out), [])
        XCTAssertTrue(out.hasPrefix(Self.realConfig), "a sibling row was re-spelled:\n\(out)")
    }
}
