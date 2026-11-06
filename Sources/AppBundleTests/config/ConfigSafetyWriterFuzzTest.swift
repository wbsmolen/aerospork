@testable import AppBundle
import Common
import TOMLKit
import XCTest

/// Property test for the line-based config writer.
///
/// TOML has many spellings for one thing, and the writer edits lines, so it can't handle them all.
/// `refusal` reads every result back rather than guessing up front which spellings are safe. This
/// generates configs from a fixed seed and asserts the one property that matters:
///
/// > for every generated config and edit, EITHER the save is refused, OR the result parses, every key
/// > the edit did not target says what it said, and every line it did not target is still there, byte
/// > for byte and in order.
///
/// Fixed seed on purpose. A fuzzer that finds a different bug on every run is a fuzzer nobody can
/// bisect, and a red build nobody can reproduce gets deleted within a month.
@MainActor
final class ConfigSafetyWriterFuzzTest: XCTestCase {
    private static let configsPerEdit = 400

    // MARK: - The property

    func testNoOpRenderIsByteIdentical() {
        forEachGeneratedConfig { text in
            let vm = ConfigurationViewModel()
            vm.load(fromText: text)
            assertEquals(ConfigurationWriter.render(baseText: text, from: vm), text)
            assertNil(ConfigurationWriter.refusal(rendered: text, base: text, from: vm))
            return true
        }
    }

    func testScalarEditPreservesEverythingElse() {
        forEachEdit(["accordion-padding"], isEdited: { section, line in section.isEmpty && line.hasPrefix("accordion-padding") }) {
            $0.settings.general.accordionPadding = 4242
        }
    }

    func testCallbackEditPreservesEverythingElse() {
        forEachEdit(["on-focus-changed"], isEdited: { section, line in section.isEmpty && line.hasPrefix("on-focus-changed") }) {
            $0.settings.callbacks.onFocusChanged = [.init(command: "focus left")]
        }
    }

    func testGapsEditPreservesEverythingElse() {
        forEachEdit(["gaps"], isEdited: { section, _ in section == "gaps" || section.hasPrefix("gaps.") }) {
            $0.settings.gaps.innerHorizontal += 7
        }
    }

    func testBindingEditPreservesEverythingElse() {
        forEachEdit(["keys", "mode"], isEdited: { _, _ in false }) {
            $0.addBinding(mode: "main", key: "alt-shift-q", command: "focus left")
        }
    }

    func testBindingRemovalPreservesEverythingElse() {
        forEachEdit(["keys", "mode"], isEdited: { _, line in line.hasPrefix("alt-h") }) { vm in
            guard let main = vm.settings.modes.first(where: { $0.mode == mainModeId }),
                  let row = main.bindings.first(where: { $0.key == "alt-h" }) else { return }
            vm.removeBinding(mode: mainModeId, id: row.id)
        }
    }

    func testMonitorEditPreservesEverythingElse() {
        forEachEdit(["monitors", "workspace-to-monitor-force-assignment"], isEdited: { _, _ in false }) {
            $0.setAssignment(workspace: "new-row", monitorToken: "main")
            $0.cancelPendingAutoSave()
        }
    }

    func testExecEditPreservesEverythingElse() {
        forEachEdit(["exec"], isEdited: { section, line in section == "exec" && line.hasPrefix("inherit-env-vars") }) { vm in
            vm.settings.exec.inheritEnvVars.toggle()
            vm.settings.exec.envVars.append(.init(name: "NEW_VAR", value: "x"))
        }
    }

    func testPresetEditPreservesEverythingElse() {
        forEachEdit(["key-mapping"], isEdited: { section, line in section == "key-mapping" && line.hasPrefix("preset") }) {
            $0.settings.keyMappingPreset = "colemak"
        }
    }

    func testRuleEditPreservesEverythingElse() {
        forEachEdit(["on-window", "on-window-detected"], isEdited: { section, _ in section.hasPrefix("on-window") }) {
            $0.settings.windowRules.append(.init(appId: "com.example.app", run: "layout floating"))
        }
    }

    private func forEachEdit(_ keys: [String], isEdited: (_ section: String, _ line: String) -> Bool, _ edit: (ConfigurationViewModel) -> Void) {
        forEachGeneratedConfig { text in
            let vm = ConfigurationViewModel()
            vm.load(fromText: text)
            edit(vm)
            let out = ConfigurationWriter.render(baseText: text, from: vm)
            // A refusal is a pass: pointing the user at the Raw TOML tab is the documented, safe outcome.
            guard ConfigurationWriter.refusal(rendered: out, base: text, from: vm) == nil else { return false }
            check(text, out, keys, isEdited)
            return true
        }
    }

    /// The invariant, for one config and one edit.
    private func check(_ before: String, _ after: String, _ keys: [String], _ isEdited: (String, String) -> Bool) {
        switch parseConfig(after) {
            case .failure(let errors):
                XCTFail("edit '\(keys)' produced an unloadable config: \(errors.descriptions)\n--- before ---\n\(before)\n--- after ---\n\(after)")
                return
            case .success: break
        }
        let lost = Self.flatten(before).filter { key, value in
            !keys.contains { key.hasPrefix($0) } && Self.flatten(after)[key] != value
        }
        XCTAssertTrue(
            lost.isEmpty,
            "edit '\(keys)' lost \(lost.keys.sorted())\n--- before ---\n\(before)\n--- after ---\n\(after)",
        )

        // The bytes, which `flatten` cannot see: comments, quoting, indentation, order, line endings.
        var remaining = Self.lines(after)[...]
        var section = ""
        for line in Self.lines(before) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") { section = t.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).components(separatedBy: "]")[0] }
            if t.isEmpty || isEdited(section, t) { continue }
            guard let at = remaining.firstIndex(of: line) else {
                XCTFail("edit '\(keys)' moved or changed the line '\(line)'\n--- before ---\n\(before)\n--- after ---\n\(after)")
                return
            }
            remaining = remaining[(at + 1)...]
        }
        if before.contains("\r\n") { XCTAssertFalse(after.contains("\n"), "edit '\(keys)' changed the line endings:\n\(after.debugDescription)") }
    }

    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    /// Runs `body` over every generated config the app itself would load: an already-broken config
    /// proves nothing about the writer. `body` says whether it got as far as checking anything.
    private func forEachGeneratedConfig(_ body: (String) -> Bool) {
        var rng = SplitMix64(seed: 0x5EED_C0FF_EE00_1234)
        var checked = 0
        for _ in 0 ..< Self.configsPerEdit {
            let text = Self.generate(&rng)
            guard case .success = parseConfig(text) else { continue }
            if body(text) { checked += 1 }
        }
        // Guards against the generator drifting into producing only refused or only broken configs,
        // which would turn every assertion above into a no-op that passes forever.
        XCTAssertGreaterThan(checked, Self.configsPerEdit / 10, "generator produced almost nothing editable")
    }

    // MARK: - Comparison

    /// `{ "gaps.inner.horizontal": "3" }`. Compared as a dictionary because TOML table order is not
    /// meaningful, and comparing rendered text would fail on formatting the writer is allowed to change.
    private static func flatten(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        if let table = try? TOMLTable(string: text) { flatten(table, "", into: &out) }
        return out
    }

    private static func flatten(_ value: TOMLValueConvertible, _ path: String, into out: inout [String: String]) {
        if let table = value.table {
            // Not for the root: "the file was empty and now isn't" is the edit, not a loss.
            if table.isEmpty, !path.isEmpty { out[path] = "{}" }
            for (key, sub) in table { flatten(sub, path.isEmpty ? key : "\(path).\(key)", into: &out) }
        } else if let array = value.array {
            if array.isEmpty { out[path] = "[]" }
            for i in 0 ..< array.count { flatten(array[i], "\(path)[\(i)]", into: &out) }
        } else {
            out[path] = value.debugDescription
        }
    }

    // MARK: - Generation

    /// Deterministic, self-contained PRNG. `SystemRandomNumberGenerator` would make every failure
    /// unreproducible, which is worse than having no test.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Fragments that must appear before any `[section]` header, or the keys after it land inside
    /// that section instead of at the top level.
    private static let preambleFragments: [String] = [
        "start-at-login = false",
        "'start-at-login' = false", // quoted key
        "\"start-at-login\" = false",
        "accordion-padding = 30",
        "accordion-padding=30", // no spaces
        "accordion-padding   =   30", // extra spaces
        "accordion-padding = 30 # keep this note", // trailing comment
        "enable-normalization-flatten-containers = false",
        "after-startup-command = 'exec-and-forget echo hi'",
        "after-startup-command = ['exec-and-forget echo hi', 'exec-and-forget echo there']",
        "after-startup-command = [\n    'exec-and-forget echo hi',\n]", // multi-line array
        "on-focus-changed = [\n  'move-mouse window-lazy-center',\n  'exec-and-forget echo x',\n]",
        "exec-on-workspace-change = []", // deprecated but loadable
        "gaps.inner.horizontal = 5", // dotted spelling of a rewritten section
        "exec = { inherit-env-vars = false }", // inline spelling of a rewritten section
        "# a comment",
        "   # an indented comment",
        "",
        "\t",
    ]

    private static let sectionFragments: [String] = [
        "[gaps]\ninner.horizontal = 3\nouter.top = 8",
        "[gaps]\n    inner.horizontal = 3\n    inner.vertical = 4", // indented
        "[gaps]", // empty section
        "[ gaps ]\ninner.horizontal = 1", // padded header
        "[gaps.inner]\nhorizontal = 6\nvertical = 6",
        "[gaps.outer]\ntop = 1\nbottom = 2\nleft = 3\nright = 4",
        "[gaps]\nouter.top = [{ monitor.\"built-in\" = 3 }, 6]", // per-monitor array the UI can't model
        "[key-mapping]\npreset = 'qwerty'",
        "[key-mapping]\npreset = 'dvorak'\nkey-notation-to-key-code.unicorn = 'u'", // unmodelled key
        "[exec]\ninherit-env-vars = true",
        "[exec]\ninherit-env-vars = false\n\n[exec.env-vars]\nPATH = '/usr/bin'",
        "[exec.env-vars]\n'MY VAR' = 'x'\n\"日本語\" = 'unicode'", // quoted + unicode keys
        "[exec]\n# a note\ninherit-env-vars = false # why\n", // comments inside a keyed section
        "[keys]\nalt-j = \"focus down\" # double-quoted, commented\n",
        "[keys.service]\nesc = 'mode main'",
        "[mode.main]\nbinding = { alt-h = 'focus left' }", // inline table
        "[ mode . main . binding ]\nalt-h = 'focus left'", // spaced header
        "[monitors]\n# a note\n1 = \"main\" # why\n'2' = ['secondary', 'built-in']",
        "[[on-window-detected]]\nrun = ['layout floating']\n    [on-window-detected.if]\n    app-id = 'com.apple.finder'", // sub-table matcher
        "[on-window]\n'com.apple.mail' = \"layout floating\"",
        "[mode.main.binding]\nalt-h = 'focus left'\nalt-l = 'focus right'",
        "[mode.main.binding]\n    alt-h = 'focus left'\n    alt-r = ['flatten-workspace-tree', 'mode main']",
        "[mode.main]\nbinding.alt-h = 'focus left'", // dotted binding
        "[mode.service.binding]\nesc = ['reload-config', 'mode main']",
        "[mode.main.binding]\nalt-1 = [\n  'workspace 1',\n]", // multi-line binding
        "[workspace-to-monitor-force-assignment]\n1 = 'main'\n2 = ['secondary', 'built-in']",
        "[workspace-to-monitor-force-assignment]\n'my workspace' = { fingerprint = { name = 'ACME Display 32 (1)' } }",
        "[workspace-to-monitor-force-assignment.2.fingerprint]\nuuid = '11111111-2222-3333-4444-555555555555'",
        "[[on-window-detected]]\nif.app-id = 'com.apple.finder'\nrun = ['layout floating']",
        "[[on-window-detected]]\nif.app-name-regex-substring = 'term'\nif.during-aerospork-startup = true\nrun = 'move-node-to-workspace 2'",
        "# documentation for the next section\n[gaps]\ninner.horizontal = 9",
    ]

    private static func generate(_ rng: inout SplitMix64) -> String {
        var parts: [String] = []
        for _ in 0 ..< Int.random(in: 0 ... 5, using: &rng) {
            parts.append(preambleFragments.randomElement(using: &rng)!)
        }
        var sections: [String] = []
        for _ in 0 ..< Int.random(in: 0 ... 4, using: &rng) {
            sections.append(sectionFragments.randomElement(using: &rng)!)
        }
        parts += sections.shuffled(using: &rng)
        let text = parts.joined(separator: Bool.random(using: &rng) ? "\n\n" : "\n")
        return Bool.random(using: &rng) ? text : text.replacingOccurrences(of: "\n", with: "\r\n")
    }
}
