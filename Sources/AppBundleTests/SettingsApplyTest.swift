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
        XCTAssertNil(ConfigurationWriter.unsupportedShapeReason(Self.issueConfig), "the writer refuses the config from the issue")
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.enableNormalizationOppositeOrientation = false

        let rendered = ConfigurationWriter.render(baseText: Self.issueConfig, from: vm)

        XCTAssertNil(ConfigurationWriter.validate(rendered))
        guard case .success(let parsed) = parseConfig(rendered) else { return XCTFail("the rendered file does not parse") }
        XCTAssertFalse(parsed.enableNormalizationOppositeOrientationForNestedContainers)
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
