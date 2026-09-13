@testable import AppBundle
import Common
import TOMLKit
import XCTest

/// Declared workspaces always exist (#40).
///
/// A config migrated from AeroSpace listed `workspaces = "1-9"` and watched every empty one vanish:
/// `workspaces` was read only behind `mod`, which a migrated config does not have, and collection
/// released any empty invisible workspace whatever the config said. The rule now is AeroSpace's
/// `persistent-workspaces`: what the config declares -- `workspaces`, `persistent-workspaces`, a
/// force-assignment -- always exists; a name that only a keybinding mentions is still released.
@MainActor
final class PersistentWorkspacesTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    private func parsed(_ toml: String, file: StaticString = #filePath, line: UInt = #line) -> Config {
        switch parseConfig(toml) {
            case .success(let config): return config
            case .failure(let errors):
                XCTFail("did not parse: \(errors.map(\.description))", file: file, line: line)
                return Config()
        }
    }

    // MARK: - What counts as declared

    func testWorkspacesDeclaresEvenWithoutMod() {
        let config = parsed("workspaces = '1-3'")
        assertEquals(config.persistentWorkspaces, ["1", "2", "3"])
        XCTAssertTrue(config.modes[mainModeId]?.bindings.isEmpty ?? true, "without mod nothing is generated")
    }

    /// The config from the issue, abridged to what bears on this: no `mod`, nine workspaces, and a
    /// tenth reached only through a binding.
    func testTheIssueConfigKeepsItsNineWorkspacesAndOnlyThose() {
        let config = parsed("""
            workspaces = "1-9"
            [keys]
            cmd-1 = 'workspace 1'
            cmd-0 = 'workspace 10'
            cmd-alt-0 = ['move-node-to-workspace 10', 'workspace 10']
            """)
        assertEquals(config.persistentWorkspaces, Set((1 ... 9).map(String.init)))
        XCTAssertTrue(config.preservedWorkspaceNames.contains("10"), "a bound name still steers the stub picker")
    }

    /// AeroSpace's own key, in an AeroSpace-shaped (v1) file. It must neither be a fatal unknown key
    /// -- which replaced the whole config with the default -- nor make the file look like v2, which
    /// would skip its migration.
    func testPersistentWorkspacesIsAcceptedWithoutChangingTheSchema() throws {
        let toml = """
            persistent-workspaces = ["1", "2", "dev"]
            [mode.main.binding]
            alt-1 = 'workspace 1'
            """
        XCTAssertFalse(isConfigV2(try TOMLTable(string: toml)))
        assertEquals(parsed(toml).persistentWorkspaces, ["1", "2", "dev"])
    }

    func testPinningAWorkspaceToAMonitorDeclaresIt() {
        let config = parsed("""
            [workspace-to-monitor-force-assignment]
            web = 'main'
            """)
        XCTAssertTrue(config.persistentWorkspaces.contains("web"))
    }

    /// Declared, kept alive, and impossible to switch to.
    func testAReservedNameCannotBeDeclared() {
        guard case .failure(let errors) = parseConfig("persistent-workspaces = ['next']") else {
            return XCTFail("a workspace named `next` was accepted")
        }
        XCTAssertTrue(errors.contains { $0.description.contains("reserved") }, "\(errors)")
    }

    /// Same rule for the bundled default as for a file of your own, so copying the default changes
    /// nothing.
    func testTheBundledDefaultDeclaresOneToNine() {
        assertEquals(defaultConfig.persistentWorkspaces, Set((1 ... 9).map(String.init)))
    }

    // MARK: - What collection does with it

    func testDeclaredWorkspacesSurviveEmptyWhileBindingOnlyOnesAreReleased() {
        config.persistentWorkspaces = ["1", "2"]
        config.preservedWorkspaceNames = ["1", "2", "A"]
        _ = Workspace.get(byName: "A")

        Workspace.garbageCollectUnusedWorkspaces()

        let names = Workspace.all.map(\.name)
        XCTAssertTrue(names.contains("1") && names.contains("2"), "declared workspaces were released: \(names)")
        XCTAssertFalse(names.contains("A"), "a workspace named only by a binding was kept alive: \(names)")
    }

    /// They exist before anyone switches to them -- which is what the menu bar, `list-workspaces --all`
    /// and a status bar listing workspaces at launch read.
    func testDeclaredWorkspacesExistWithoutEverBeingVisited() {
        config.persistentWorkspaces = ["7"]
        Workspace.garbageCollectUnusedWorkspaces()
        XCTAssertNotNil(Workspace.existing(byName: "7"))
    }

    /// Created on every collection rather than once at startup, so a reload that drops the
    /// declaration simply stops keeping it.
    func testRemovingTheDeclarationLetsTheWorkspaceGo() {
        config.persistentWorkspaces = ["gone"]
        Workspace.garbageCollectUnusedWorkspaces()
        XCTAssertNotNil(Workspace.existing(byName: "gone"))

        config.persistentWorkspaces = []
        Workspace.garbageCollectUnusedWorkspaces()
        XCTAssertNil(Workspace.existing(byName: "gone"))
    }

    /// The issue's `cmd-left`/`cmd-right = 'workspace --wrap-around prev/next'` walked only the
    /// workspaces that happened to hold windows.
    func testNextAndPrevWalkThroughEmptyDeclaredWorkspaces() {
        config.persistentWorkspaces = ["1", "2", "3"]
        Workspace.garbageCollectUnusedWorkspaces()
        XCTAssertTrue(Workspace.get(byName: "1").focusWorkspace())

        let next = getNextPrevWorkspace(current: focus.workspace, isNext: true, wrapAround: true, stdin: "", target: focus)

        assertEquals(next?.name, "2")
    }

    /// The Monitors pane's "Pin a workspace here" menu lists defined workspaces. It must read both
    /// spellings, or a config written with AeroSpace's key offers nothing to pin. `loadConfiguration`
    /// reads the user's real file, so this is checked in the source.
    func testSettingsTreatsBothSpellingsAsDefined() throws {
        let source = try String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/ConfigurationViewModel.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains(#"definedWorkspaces = workspaceNames(table?["workspaces"]) + workspaceNames(table?["persistent-workspaces"])"#))
    }
}
