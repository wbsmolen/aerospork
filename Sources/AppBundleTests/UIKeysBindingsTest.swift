@testable import AppBundle
import Common
import Foundation
import TOMLKit
import XCTest

/// The Keys tab under config v2.
///
/// v2 *generates* ~78 bindings from `mod` + `workspaces` and keeps explicit ones in `[keys]`, so a
/// tab that reads `[mode.*]` shows an empty table for a config whose keyboard is fully bound. The
/// fix has a trap in it: load those bindings into the list the writer persists and the next save
/// writes all 78 back into the file, re-materializing the boilerplate v2 exists to delete.
///
/// So the two properties, together:
///   * every active binding is VISIBLE, tagged with where it came from;
///   * only the ones written in a section the writer owns are WRITTEN back.
@MainActor
final class UIKeysBindingsTest: XCTestCase {
    /// A v2 config in the shape the migration produces: generated bindings, a `[keys]` block, and a
    /// named mode that exists only as `[keys.<name>]`.
    private static let v2 = """
        mod = 'alt'
        workspaces = '1-9'
        accordion-padding = 30

        [keys]
        alt-enter = 'exec-and-forget open -na Ghostty'
        alt-shift-semicolon = 'mode service'

        [keys.service]
        esc = [ 'reload-config', 'mode main' ]
        r = [ 'flatten-workspace-tree', 'mode main' ]
        """

    private func loaded(_ text: String = v2) -> ConfigurationViewModel {
        let vm = ConfigurationViewModel()
        vm.load(fromText: text)
        vm.markLoaded()
        return vm
    }

    private func errors(_ toml: String) -> [String] {
        switch parseConfig(toml) {
            case .success: return []
            case .failure(let e): return e.map(\.description)
        }
    }

    private func rows(_ vm: ConfigurationViewModel, _ mode: String = mainModeId) -> [String: ConfigurationViewModel.DisplayBinding] {
        Dictionary(uniqueKeysWithValues: vm.displayBindings(mode: mode).map { ($0.key, $0) })
    }

    // MARK: - What the tab shows

    /// The gap this closes: `[mode.*]` is empty in a v2 config, so the table was empty while the
    /// keyboard had 78 live bindings.
    func testGeneratedBindingsAreListed() {
        let byKey = rows(loaded())
        assertEquals(byKey["alt-1"]?.command, "workspace 1")
        assertEquals(byKey["alt-shift-9"]?.command, "move-node-to-workspace 9")
        assertEquals(byKey["alt-h"]?.command, "focus left")
        assertEquals(byKey["alt-1"]?.origin, ConfigurationViewModel.BindingOrigin.generated)
        // 13 i3 defaults + 9 workspaces x 2.
        assertEquals(byKey.values.count { $0.origin == .generated }, 31)
    }

    /// `[keys]` is where a v2 user's own bindings live. They were invisible too -- and then visible
    /// but read-only. They have a line in the file, so they are editable in place like any other.
    func testKeysSectionBindingsAreListedAndEditable() {
        let byKey = rows(loaded())
        assertEquals(byKey["alt-enter"]?.command, "exec-and-forget open -na Ghostty")
        assertEquals(byKey["alt-enter"]?.origin, ConfigurationViewModel.BindingOrigin.explicit)
        XCTAssertNotNil(byKey["alt-enter"]?.rowId, "a [keys] binding must be editable in place")
        // A multi-command binding round-trips through the separator the writer splits on.
        assertEquals(rows(loaded(), "service")["esc"]?.command, "reload-config ; mode main")
    }

    /// A mode that exists only as `[keys.<name>]` has to reach the mode picker, or it is unreachable
    /// from the GUI entirely.
    func testModePickerSeesModesThatOnlyExistInTheKeysSection() {
        assertEquals(loaded().allModeNames, ["main", "service"])
        // ...and it reaches `modes`, the writable set, so its bindings can be edited.
        assertEquals(loaded().settings.modes.map(\.mode), ["main", "service"])
        // Generated bindings stay OUT of the writable set -- they have no line to round-trip against.
        XCTAssertFalse(
            loaded().settings.modes.first { $0.mode == mainModeId }?.bindings.contains { $0.key == "alt-1" } ?? true,
            "a generated binding leaked into the writable set",
        )
    }

    /// Precedence, shown once. `parseConfigV2` layers generated -> `[keys]` -> `[mode.*]`; the table
    /// must show the same winner, and must show it ONCE rather than three rows for one key.
    func testStrongestSourceWinsAndTheKeyAppearsOnlyOnce() {
        let vm = loaded("""
            mod = 'alt'
            workspaces = '1-2'

            [keys]
            alt-1 = 'workspace one'

            [mode.main.binding]
            alt-2 = 'workspace two'
            """)
        let byKey = rows(vm)
        assertEquals(vm.displayBindings(mode: mainModeId).count { $0.key == "alt-1" }, 1)
        assertEquals(byKey["alt-1"]?.command, "workspace one") // [keys] beat the generated one
        assertEquals(byKey["alt-1"]?.origin, ConfigurationViewModel.BindingOrigin.explicit)
        assertEquals(byKey["alt-2"]?.command, "workspace two") // [mode.*] beat the generated one
        assertEquals(byKey["alt-2"]?.origin, ConfigurationViewModel.BindingOrigin.explicit)
        // Both have a line in the file, in two different sections. Both are editable.
        XCTAssertNotNil(byKey["alt-1"]?.rowId)
        XCTAssertNotNil(byKey["alt-2"]?.rowId)
    }

    // MARK: - What a save writes

    /// The trap, guarded. Opening the tab loads 33 bindings; saving must write none of them.
    func testSavingDoesNotMaterializeGeneratedOrKeysBindings() {
        let vm = loaded()
        assertEquals(ConfigurationWriter.render(baseText: Self.v2, from: vm), Self.v2, additionalMsg: "a no-op save changed the file")

        vm.settings.general.accordionPadding = 42 // an edit on a completely different tab
        let out = ConfigurationWriter.render(baseText: Self.v2, from: vm)
        assertEquals(errors(out), [])
        XCTAssertFalse(out.contains("[mode."), "a generated or keys binding was written back:\n\(out)")
        XCTAssertFalse(out.contains("workspace 1"), "the boilerplate v2 deletes came back:\n\(out)")
        // ...and nothing was duplicated out of [keys] either.
        assertEquals(out.components(separatedBy: "alt-enter").count - 1, 1, additionalMsg: out)
        assertEquals(out.components(separatedBy: "flatten-workspace-tree").count - 1, 1, additionalMsg: out)
    }

    /// Override is the affordance for a binding the tab cannot edit in place: it copies the row into
    /// the writable set, where it layers on top of both other sources.
    func testOverridingAGeneratedBindingWritesOneExplicitLine() {
        let vm = loaded()
        XCTAssertTrue(vm.addBinding(mode: mainModeId, key: "alt-1", command: "workspace scratch"))

        let out = ConfigurationWriter.render(baseText: Self.v2, from: vm)
        assertEquals(errors(out), [])
        assertEquals(out.components(separatedBy: "alt-1").count - 1, 1, additionalMsg: "override wrote more than one line:\n\(out)")
        XCTAssertFalse(out.contains("alt-2"), "overriding one binding dragged its 30 siblings along:\n\(out)")

        switch parseConfig(out) {
            case .failure(let e): XCTFail("\(e.descriptions)")
            case .success(let config):
                let byNotation = Dictionary(
                    uniqueKeysWithValues: (config.modes[mainModeId]?.bindings ?? [:]).values
                        .map { ($0.descriptionWithKeyNotation, $0.commands.map { $0.args.description }.joined()) },
                )
                assertEquals(byNotation["alt-1"], "workspace scratch") // the override took
                assertEquals(byNotation["alt-2"], "workspace 2") // generation still intact
        }
    }

    // MARK: - Editing a [keys] binding in place

    /// The writer used to know only `[mode.<name>.binding]`, so the only way to change a `[keys]`
    /// entry was Override -- which left the original line in place and added a v1-spelled
    /// `[mode.main.binding]` block on top of it. Two syntaxes for one thing, in one file.
    private func rowId(_ vm: ConfigurationViewModel, _ mode: String, _ key: String) -> ConfigurationViewModel.BindingRow.ID {
        rows(vm, mode)[key]!.rowId!
    }

    func testEditingAKeysBindingRewritesTheKeysLineInPlace() {
        let vm = loaded()
        vm.updateBinding(mode: mainModeId, id: rowId(vm, mainModeId, "alt-enter"), command: "exec-and-forget open -na Alacritty")

        let out = ConfigurationWriter.render(baseText: Self.v2, from: vm)
        assertEquals(errors(out), [])
        XCTAssertTrue(out.contains("alt-enter = 'exec-and-forget open -na Alacritty'"), out)
        XCTAssertFalse(out.contains("Ghostty"), "the old command survived:\n\(out)")
        XCTAssertFalse(out.contains("[mode."), "the v1 spelling leaked into a v2 file:\n\(out)")
        assertEquals(out.components(separatedBy: "alt-enter").count - 1, 1, additionalMsg: out)
    }

    /// A named mode lives in `[keys.<name>]`, and its rows must land there rather than in `[keys]`.
    func testAddingToANamedModeWritesUnderThatModesKeysSubTable() {
        let vm = loaded()
        XCTAssertTrue(vm.addBinding(mode: "service", key: "q", command: "close"))

        let out = ConfigurationWriter.render(baseText: Self.v2, from: vm)
        assertEquals(errors(out), [])
        switch parseConfig(out) {
            case .failure(let e): XCTFail("\(e.descriptions)")
            case .success(let config):
                let service = (config.modes["service"]?.bindings ?? [:]).values.map(\.descriptionWithKeyNotation)
                XCTAssertTrue(service.contains("q"), "\(service)")
                XCTAssertTrue(service.contains("esc"), "the existing entries were dropped: \(service)")
        }
    }

    func testRemovingAKeysBindingDeletesItsLine() {
        let vm = loaded()
        vm.removeBinding(mode: mainModeId, id: rowId(vm, mainModeId, "alt-enter"))

        let out = ConfigurationWriter.render(baseText: Self.v2, from: vm)
        assertEquals(errors(out), [])
        XCTAssertFalse(out.contains("alt-enter"), out)
        XCTAssertTrue(out.contains("alt-shift-semicolon"), "the sibling binding went with it:\n\(out)")
    }

    /// The formatting-churn trap. `formatCommand` normalizes quoting, so re-emitting an untouched
    /// line turns `key = "cmd"` into `key = 'cmd'` -- a no-op save that modifies the file. Only
    /// caught by a base text whose quoting differs from what the writer would emit.
    func testNoOpSaveDoesNotRequoteUntouchedBindings() {
        let base = """
            mod = 'alt'
            workspaces = '1-2'

            [keys]
            alt-enter = "exec-and-forget open -na Ghostty"
            """
        let vm = loaded(base)
        assertEquals(ConfigurationWriter.render(baseText: base, from: vm), base)
        vm.settings.general.accordionPadding = 42 // force every section through the writer
        XCTAssertTrue(
            ConfigurationWriter.render(baseText: base, from: vm).contains("alt-enter = \"exec-and-forget open -na Ghostty\""),
            "an untouched binding was requoted",
        )
    }

    // MARK: - Edit in place

    /// Changing a binding used to be remove-then-re-add, which gave the row a NEW identity: the
    /// SwiftUI row was torn down and rebuilt under the cursor, so a 600ms autosave landing mid-edit
    /// dropped focus and the rest of what was being typed.
    func testEditingABindingKeepsTheRowIdentity() {
        let vm = loaded("[mode.main.binding]\nalt-h = 'focus left'\n")
        let before = rows(vm)["alt-h"].orDie("no editable row").rowId.orDie("row is not editable")

        vm.updateBinding(mode: mainModeId, id: before, command: "focus --boundaries all-monitors-outer-frame left")
        assertEquals(rows(vm)["alt-h"].orDie("row vanished").rowId, before)
        assertEquals(rows(vm)["alt-h"]?.command, "focus --boundaries all-monitors-outer-frame left")

        // Re-keying keeps the identity too, so the recorder does not lose the row it just wrote to.
        vm.updateBinding(mode: mainModeId, id: before, key: "alt-shift-h")
        assertEquals(rows(vm)["alt-shift-h"].orDie("row vanished").rowId, before)
        assertNil(rows(vm)["alt-h"])
    }

    /// The edit has to reach the file, and reach it in place rather than as a second line.
    func testEditingABindingRewritesItsLine() {
        let base = "[mode.main.binding]\nalt-h = 'focus left'\n"
        let vm = loaded(base)
        let id = rows(vm)["alt-h"].orDie("no editable row").rowId.orDie("row is not editable")
        vm.updateBinding(mode: mainModeId, id: id, command: "focus right")

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        assertEquals(errors(out), [])
        assertEquals(out.components(separatedBy: "alt-h").count - 1, 1, additionalMsg: "edit appended a duplicate:\n\(out)")
        XCTAssertTrue(out.contains("alt-h = 'focus right'"), out)
    }

    /// An empty edit must not be able to produce `'' = 'focus left'`, which does not parse.
    func testUpdateIgnoresUnknownRowsAndBlankKeys() {
        let vm = loaded("[mode.main.binding]\nalt-h = 'focus left'\n")
        vm.updateBinding(mode: mainModeId, id: UUID(), command: "boom")
        vm.updateBinding(mode: "nope", id: rows(vm)["alt-h"].orDie("no row").rowId.orDie("not editable"), command: "boom")
        assertEquals(rows(vm)["alt-h"]?.command, "focus left")
    }

    // MARK: - Conflicts

    /// Two writable rows with the same key in one mode is two lines with the same TOML key, which
    /// does not parse. So a rename that collides used to hand the user a config the app refuses to
    /// load -- and the table, which dedupes by key, showed only one of the pair.
    func testRekeyingOntoAKeyAnotherRowOwnsIsRefused() {
        let base = "[mode.main.binding]\nalt-h = 'focus left'\nalt-l = 'focus right'\n"
        let vm = loaded(base)
        let id = rowId(vm, mainModeId, "alt-h")

        XCTAssertFalse(vm.updateBinding(mode: mainModeId, id: id, key: "alt-l"))
        assertEquals(rows(vm)["alt-h"]?.command, "focus left")
        assertEquals(rows(vm)["alt-l"]?.command, "focus right")

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        assertEquals(errors(out), [])
        assertEquals(out.components(separatedBy: "alt-l").count - 1, 1, additionalMsg: out)
    }

    /// The counter-check: colliding with a *generated* binding is not a conflict, it is the whole
    /// point of overriding one. Refusing it would make ⌥1 permanently unassignable.
    func testRekeyingOntoAGeneratedKeyIsAllowed() {
        let vm = loaded()
        let id = rowId(vm, mainModeId, "alt-enter")
        XCTAssertTrue(vm.updateBinding(mode: mainModeId, id: id, key: "alt-1"))
        assertEquals(rows(vm)["alt-1"]?.command, "exec-and-forget open -na Ghostty")
        assertEquals(rows(vm)["alt-1"]?.origin, ConfigurationViewModel.BindingOrigin.explicit)
    }

    /// What the composer's "already bound to…" banner reads. It has to see generated bindings:
    /// recording ⌥1 for something new looks free, because nothing in the file mentions it.
    func testExistingBindingSeesGeneratedOwnersAndIgnoresTheRowBeingEdited() {
        let vm = loaded()
        assertEquals(vm.existingBinding(mode: mainModeId, key: "alt-1")?.command, "workspace 1")
        assertEquals(vm.existingBinding(mode: mainModeId, key: "alt-1")?.origin, ConfigurationViewModel.BindingOrigin.generated)
        assertEquals(vm.existingBinding(mode: mainModeId, key: "alt-enter")?.command, "exec-and-forget open -na Ghostty")
        assertNil(vm.existingBinding(mode: mainModeId, key: "alt-f13"))
        assertNil(vm.existingBinding(mode: mainModeId, key: "   "))

        // A row must not conflict with itself, or its own recorder would warn on every keystroke.
        assertNil(vm.existingBinding(mode: mainModeId, key: "alt-enter", ignoring: rowId(vm, mainModeId, "alt-enter")))
    }

    // MARK: - Mode picker sizing

    /// A segmented control's width is the sum of its segments and cannot shrink below that; past
    /// some mode count it overflows the window no matter what its neighbours give up, so the tab
    /// switches to a bounded-width menu instead. Not view-renderable, so pinned here as the pure
    /// decision the view defers to.
    func testModePickerDegradesToAMenuPastFiveModes() {
        XCTAssertTrue(KeyBindingsTab.modePickerIsSegmented(count: 1))
        XCTAssertTrue(KeyBindingsTab.modePickerIsSegmented(count: 5))
        XCTAssertFalse(KeyBindingsTab.modePickerIsSegmented(count: 6))
        XCTAssertFalse(KeyBindingsTab.modePickerIsSegmented(count: 9))
    }

    // MARK: - v1 is untouched

    /// v1 configs keep working exactly as before: everything is explicit, nothing is inherited.
    func testV1ConfigHasNoInheritedBindings() {
        let vm = loaded("[mode.main.binding]\nalt-h = 'focus left'\n\n[mode.resize.binding]\nesc = 'mode main'\n")
        XCTAssertTrue(vm.inheritedBindings.isEmpty)
        assertEquals(vm.allModeNames, ["main", "resize"])
        assertEquals(rows(vm)["alt-h"]?.origin, .explicit)
    }
}
