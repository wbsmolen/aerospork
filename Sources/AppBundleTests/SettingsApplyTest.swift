@testable import AppBundle
import XCTest

/// "Alternate orientation neither modifies the config nor works" (#40).
///
/// The write was never the problem, and the first test here settles that on the config from the
/// issue. What was wrong: a change made less than 600ms before closing the window was dropped, and
/// a saved change did nothing on screen until an unrelated window event, because the settings save
/// reloads without refreshing. (Turning the setting OFF also never un-flips existing splits -- by
/// design, and now said in the pane.)
@MainActor
final class SettingsApplyTest: XCTestCase {
    /// Verbatim from the issue.
    private static let issueConfig = """
        start-at-login = true
        accordion-padding = 30
        default-root-container-layout = "tiles"
        default-root-container-orientation = "auto"
        after-startup-command = ["exec-and-forget sketchybar --reload"]
        exec-on-workspace-change = ['/bin/bash', '-c',
            'sketchybar --trigger aerospork_workspace_change FOCUSED_WORKSPACE=$AEROSPORK_FOCUSED_WORKSPACE'
        ]
        #on-focused-workspace-changed = ["move-mouse window-lazy-center"]
        show-menu-bar-icon = true

        workspaces = "1-9"

        [gaps]
        inner = 10
        outer = 12

        [keys]
        cmd-left = 'workspace --wrap-around prev'
        cmd-right = 'workspace --wrap-around next'

        cmd-1 = 'workspace 1'
        cmd-0 = 'workspace 10'

        cmd-alt-1 = ['move-node-to-workspace 1', 'workspace 1']
        cmd-alt-0 = ['move-node-to-workspace 10', 'workspace 10']

        [[on-window-detected]]
        run = [ 'layout floating' ]
            [on-window-detected.if]
            app-id = 'com.apple.finder'

        [[on-window-detected]]
        run = [ 'layout tiling', 'move-node-to-workspace 5' ]
            [on-window-detected.if]
            app-id = 'md.obsidian'

        """

    func testTurningOffAlternateOrientationOnTheIssueConfigIsWritten() {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.settings.general.enableNormalizationOppositeOrientation = false

        let rendered = ConfigurationWriter.render(baseText: Self.issueConfig, from: vm)

        XCTAssertNil(ConfigurationWriter.refusal(rendered: rendered, base: Self.issueConfig, from: vm), "the writer refuses the config from the issue")
        guard case .success(let parsed) = parseConfig(rendered) else { return XCTFail("the rendered file does not parse") }
        XCTAssertFalse(parsed.enableNormalizationOppositeOrientationForNestedContainers)
    }

    /// A binding added in Raw TOML is not in a view model that has not re-read the file, and the next
    /// unrelated toggle used to read that as a deletion.
    func testABindingAddedInRawTomlSurvivesTheNextUnrelatedToggle() {
        let vm = ConfigurationViewModel()
        vm.load(fromText: "[mode.main.binding]\nalt-h = 'focus left'\n")
        vm.markLoaded()
        vm.settings.general.accordionPadding = 42

        let fileAfterApply = "[mode.main.binding]\nalt-h = 'focus left'\nalt-j = 'focus down'\n"
        XCTAssertTrue(ConfigurationWriter.render(baseText: fileAfterApply, from: vm).contains("alt-j"))
    }

    /// Raw TOML replaced what every other pane is showing. Panes left on the old values would show the
    /// wrong thing, and write it back over the file the next time someone edited that section.
    func testAnAppliedRawTomlIsReadBackByTheOtherPanes() {
        let vm = ConfigurationViewModel()
        vm.load(fromText: "[mode.main.binding]\nalt-h = 'focus left'\n")
        let applied = "accordion-padding = 7\n\n[mode.main.binding]\nalt-h = 'focus left'\nalt-j = 'focus down'\n"
        vm.rawToml = applied
        vm.rawTomlApplyRequested = true
        vm.didWrite(ConfigurationWriter.render(baseText: "", from: vm))
        vm.rawTomlApplyRequested = false // `saveConfiguration` does this on its way out

        assertEquals(vm.settings.general.accordionPadding, 7)
        assertEquals(vm.settings.modes.first?.bindings.map(\.key), ["alt-h", "alt-j"])
        XCTAssertFalse(vm.hasUnsavedChanges)
        XCTAssertFalse(vm.rawTomlEdited)

        vm.settings.general.startAtLogin = true
        let out = ConfigurationWriter.render(baseText: applied, from: vm)
        XCTAssertNil(ConfigurationWriter.refusal(rendered: out, base: applied, from: vm))
        XCTAssertTrue(out.contains("alt-j = 'focus down'"), out)
        XCTAssertTrue(out.contains("accordion-padding = 7"), out)
    }

    /// A refused Apply must not leave the buffer armed for the next toggle's autosave.
    func testARefusedApplyDoesNotStayRequested() async {
        let vm = ConfigurationViewModel()
        vm.rawToml = "totally-unknown-key = 1\n"
        vm.rawTomlApplyRequested = true
        await vm.saveConfiguration()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.rawTomlApplyRequested)
    }

    /// A half-filled rule holds every rule back, and recording that as saved lost the other edit: the
    /// view model believed the file had it, so nothing ever wrote it.
    func testARuleEditHeldBackByAHalfFilledRuleStaysPending() {
        let base = "mod = 'alt'\n\n[on-window]\n\"com.apple.finder\" = 'move-node-to-workspace 3'\n"
        let vm = ConfigurationViewModel()
        vm.load(fromText: base)
        vm.markLoaded()
        vm.settings.windowRules[0].run = "move-node-to-workspace 4"
        vm.settings.windowRules.append(.init(appId: "com.apple.mail", run: ""))

        let held = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertFalse(held.contains("workspace 4"), "the writer holds the whole section back")
        XCTAssertNil(ConfigurationWriter.refusal(rendered: held, base: base, from: vm), "waiting for a command is not an error")
        vm.didWrite(held)
        XCTAssertTrue(vm.edited(\.windowRules), "the edit was recorded as saved")
        XCTAssertTrue(vm.hasUnsavedChanges)

        vm.settings.windowRules[1].run = "layout floating"
        let out = ConfigurationWriter.render(baseText: held, from: vm)
        XCTAssertTrue(out.contains("workspace 4"), out)
        XCTAssertTrue(out.contains("layout floating"), out)
        XCTAssertNil(ConfigurationWriter.refusal(rendered: out, base: held, from: vm))
        vm.didWrite(out)
        XCTAssertFalse(vm.edited(\.windowRules))
        XCTAssertFalse(vm.hasUnsavedChanges)
    }

    /// A matcher can be written as its own `[on-window-detected.if]` table, as the issue config does.
    /// Leaving that behind when the rule was rewritten produced a clash, and no rule could be edited.
    func testEditingARuleSpelledWithASubTableIsWritten() {
        let vm = ConfigurationViewModel()
        vm.load(fromText: Self.issueConfig)
        assertEquals(vm.settings.windowRules.map(\.appId), ["com.apple.finder", "md.obsidian"])
        vm.settings.windowRules[0].run = "layout tiling"

        let out = ConfigurationWriter.render(baseText: Self.issueConfig, from: vm)
        XCTAssertNil(ConfigurationWriter.refusal(rendered: out, base: Self.issueConfig, from: vm))
        guard case .success(let parsed) = parseConfig(out) else { return XCTFail(out) }
        assertEquals(parsed.onWindowDetected.count, 2)
        XCTAssertFalse(out.contains("on-window-detected.if"), out)
    }

    /// The pending save is attempted rather than dropped. The view model is put in a state that its
    /// guards refuse before writing anything -- this test must never touch the real config file.
    func testClosingTheWindowAttemptsAPendingSaveInsteadOfDroppingIt() async {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.rawToml = "unapplied raw edit" // refused before render, so nothing can be written
        vm.scheduleAutoSave()

        await vm.flushPendingAutoSave()

        XCTAssertNotNil(vm.errorMessage, "the pending save was dropped instead of attempted")
    }

    func testClosingTheWindowWithNothingPendingSavesNothing() async {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.rawToml = "unapplied raw edit"

        await vm.flushPendingAutoSave()

        XCTAssertNil(vm.errorMessage, "a close with no pending edit attempted a save")
    }

    func testTheWindowFlushesOnClose() throws {
        let source = try String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/ConfigurationWindow.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(".onDisappear { Task { await viewModel.flushPendingAutoSave() } }"))
    }

    /// A save cannot run headlessly without writing a real file, so the refresh is checked in the source.
    func testASavedChangeIsAppliedOnScreenWithoutWaitingForAWindowEvent() throws {
        let source = try String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/ConfigurationViewModel.swift"), encoding: .utf8)
        let save = try XCTUnwrap(source.range(of: "func saveConfiguration()"))
        let body = source[save.lowerBound...].prefix(4000)
        let write = try XCTUnwrap(body.range(of: "try ConfigurationWriter.write(rendered)"))
        let refresh = try XCTUnwrap(body.range(of: "runRefreshSession("), "a GUI save no longer refreshes")
        XCTAssertLessThan(write.lowerBound, refresh.lowerBound)
    }
}
