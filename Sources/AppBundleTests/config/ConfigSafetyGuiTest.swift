@testable import AppBundle
import Common
import XCTest

/// Settings-GUI gaps where the UI reported success and nothing happened.
@MainActor
final class ConfigSafetyGuiTest: XCTestCase {
    private func errors(_ toml: String) -> [String] {
        switch parseConfig(toml) {
            case .success: return []
            case .failure(let e): return e.map(\.description)
        }
    }

    /// A config with no `[mode.*]` section is perfectly valid. `addBinding` used to return silently
    /// for it while the tab cleared the fields anyway, so the binding the user typed just vanished.
    func testAddBindingCreatesTheModeWhenThereIsNone() {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        XCTAssertTrue(vm.addBinding(mode: "main", key: "alt-h", command: "focus left"))

        let out = ConfigurationWriter.render(baseText: "start-at-login = false\n", from: vm)
        XCTAssertTrue(out.contains("[keys]"), out)
        XCTAssertTrue(out.contains("alt-h = 'focus left'"), out)
        assertEquals(errors(out), [])
    }

    /// The caller has to be able to tell "taken" from "ignored", or it clears the fields regardless.
    func testAddBindingReportsFailureForEmptyInput() {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        XCTAssertFalse(vm.addBinding(mode: "main", key: "  ", command: "focus left"))
        XCTAssertFalse(vm.addBinding(mode: "main", key: "alt-h", command: ""))
        XCTAssertTrue(vm.settings.modes.isEmpty)
    }

    func testAddModeRejectsDuplicatesAndBlanks() {
        let vm = ConfigurationViewModel()
        XCTAssertTrue(vm.addMode("resize"))
        XCTAssertFalse(vm.addMode("resize"))
        XCTAssertFalse(vm.addMode("   "))
        assertEquals(vm.settings.modes.map(\.mode), ["resize"])
    }

    func testDeletingAModeRemovesItsSection() {
        let base = """
            [mode.main.binding]
            alt-h = 'focus left'

            [mode.resize.binding]
            esc = 'mode main'
            """
        let vm = ConfigurationViewModel()
        vm.settings.modes = [
            .init(mode: "main", bindings: [.init(key: "alt-h", command: "focus left")]),
            .init(mode: "resize", bindings: [.init(key: "esc", command: "mode main")]),
        ]
        vm.markLoaded()
        vm.removeMode("resize")

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertFalse(out.contains("mode.resize"), "deleted mode survived:\n\(out)")
        XCTAssertTrue(out.contains("alt-h = 'focus left'"), "took the wrong mode with it:\n\(out)")
        assertEquals(errors(out), [])
    }

    /// `main` is the mode the app starts in; deleting it leaves nothing to fall back to.
    func testMainModeCannotBeDeleted() {
        let vm = ConfigurationViewModel()
        vm.settings.modes = [.init(mode: "main", bindings: [])]
        vm.markLoaded()
        XCTAssertFalse(vm.canRemoveMode(mainModeId))
        vm.removeMode(mainModeId)
        assertEquals(vm.settings.modes.map(\.mode), ["main"])
    }

    /// Mode deletion is scoped to modes the view model actually LOADED. Without that scope, any
    /// view model that never loaded any modes -- every fresh one -- would delete every mode in the
    /// file on the next unrelated save.
    func testFreshViewModelDoesNotDeleteExistingModes() {
        let base = "[mode.main.binding]\nalt-h = 'focus left'\n"
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.settings.general.accordionPadding = 42 // an unrelated edit
        XCTAssertTrue(ConfigurationWriter.render(baseText: base, from: vm).contains("alt-h = 'focus left'"))
    }
}
