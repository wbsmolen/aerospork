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

    /// Set by `testMultilineValuesAreRefusedOrPreserved`, which runs every property below again over
    /// configs that also hold values spanning lines.
    private var multiline = false

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

    /// The writer reads a file line by line and does not lex TOML: any line that starts with `[` is a
    /// header to it, and any line with `=` a key, even inside a `'''` string. A value that spans lines
    /// is the one shape where that guess is wrong, so every property above must still hold for it,
    /// through `refusal` when the line surgery goes astray. Half the configs, so the suite stays fast.
    func testMultilineValuesAreRefusedOrPreserved() {
        multiline = true
        testNoOpRenderIsByteIdentical()
        testScalarEditPreservesEverythingElse()
        testCallbackEditPreservesEverythingElse()
        testGapsEditPreservesEverythingElse()
        testBindingEditPreservesEverythingElse()
        testBindingRemovalPreservesEverythingElse()
        testMonitorEditPreservesEverythingElse()
        testExecEditPreservesEverythingElse()
        testPresetEditPreservesEverythingElse()
        testRuleEditPreservesEverythingElse()
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
        // A line inside a value that spans lines is neither a header nor a key, whatever it starts
        // with, and belongs to the key that opened the value.
        var remaining = Self.lines(after)[...]
        var section = ""
        var edited = false
        let beforeLines = Self.lines(before)
        for (line, continues) in zip(beforeLines, Self.continuesValue(beforeLines)) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !continues {
                if t.hasPrefix("[") { section = t.trimmingCharacters(in: CharacterSet(charactersIn: "[] ")).components(separatedBy: "]")[0] }
                edited = isEdited(section, t)
                if t.isEmpty { continue }
            }
            if edited { continue }
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

    /// For each line, whether it starts inside a value an earlier line opened: a multi-line string, or
    /// an array or inline table not yet closed. Just enough TOML lexing for the generated fragments.
    private static func continuesValue(_ lines: [String]) -> [Bool] {
        var open: Substring? = nil // the delimiter of the multi-line string we are in
        var depth = 0
        return lines.map { line in
            let continues = open != nil || depth > 0
            var rest = Substring(line)
            while let c = rest.first {
                if let delimiter = open {
                    if rest.hasPrefix(delimiter) {
                        open = nil
                        rest = rest.dropFirst(3)
                    } else {
                        rest = rest.dropFirst(delimiter == "\"\"\"" && c == "\\" ? 2 : 1)
                    }
                    continue
                }
                if rest.hasPrefix("'''") || rest.hasPrefix("\"\"\"") {
                    open = rest.prefix(3)
                    rest = rest.dropFirst(3)
                    continue
                }
                rest = rest.dropFirst()
                switch c {
                    case "#": rest = ""
                    case "'", "\"":
                        while let d = rest.first, d != c { rest = rest.dropFirst(c == "\"" && d == "\\" ? 2 : 1) }
                        rest = rest.dropFirst()
                    case "[", "{": depth += 1
                    case "]", "}": depth -= 1
                    default: break
                }
            }
            return continues
        }
    }

    /// Runs `body` over every generated config the app itself would load: an already-broken config
    /// proves nothing about the writer. `body` says whether it got as far as checking anything.
    private func forEachGeneratedConfig(_ body: (String) -> Bool) {
        var rng = SplitMix64(seed: 0x5EED_C0FF_EE00_1234)
        var checked = 0
        let count = multiline ? Self.configsPerEdit / 2 : Self.configsPerEdit
        for _ in 0 ..< count {
            let text = Self.generate(&rng, multiline: multiline)
            guard case .success = parseConfig(text) else { continue }
            if body(text) { checked += 1 }
        }
        // Guards against the generator drifting into producing only refused or only broken configs,
        // which would turn every assertion above into a no-op that passes forever.
        XCTAssertGreaterThan(checked, count / 10, "generator produced almost nothing editable")
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

    /// Values that span lines, and lines inside them that look like a header or a key. Several
    /// close a `'''` string behind a `#`, so the line a writer leaves behind is still valid TOML.
    private static let multilinePreambleFragments: [String] = [
        "after-startup-command = '''exec-and-forget echo\n[gaps]\ninner = 99\n'''",
        "after-startup-command = \"\"\"exec-and-forget printf '\n[keys]\naccordion-padding = 1\n'\"\"\"",
        "after-startup-command = '''exec-and-forget echo\naccordion-padding = 7 # '''",
        "on-focus-changed = '''exec-and-forget echo\n[mode.main.binding]\nalt-h = 'focus right'\n'''",
        "on-focus-changed = [\n  'move-mouse window-lazy-center',\n  '''exec-and-forget echo\n[exec]\n''',\n]",
        "on-focus-changed = \"\"\"move-mouse window-lazy-center\"\"\"", // one line, triple-quoted
        "exec = { inherit-env-vars = false, env-vars = { NOTE = '''\n[exec.env-vars]\nPATH = 'x'\n''' } }",
        "accordion-padding = 30 # ''' a delimiter in a comment",
    ]

    private static let multilineSectionFragments: [String] = [
        "[keys]\nalt-enter = '''exec-and-forget osascript -e '\ntell application \"Terminal\"\n    do script\nend tell'\n'''",
        "[keys]\nalt-x = '''exec-and-forget echo\n[gaps]\ninner = 99\n'''",
        "[mode.main.binding]\nalt-h = '''exec-and-forget echo\n[keys]\nalt-j = 'focus down' # '''",
        "[mode.main.binding]\nalt-1 = [\n  'workspace 1',\n  '''exec-and-forget echo\n[monitors]\n''',\n]",
        "[mode.main]\nbinding = { alt-h = [\n  'focus left',\n] }", // inline table holding a multi-line array
        "[exec.env-vars]\nNOTE = \"\"\"\n[exec]\ninherit-env-vars = true\n\"\"\"",
        "[exec]\ninherit-env-vars = true\n\n[exec.env-vars]\nNOTE = '''\nPATH = '/tmp' # '''",
        "[monitors]\n1 = [\n  'secondary',\n  'built-in',\n]",
        "[monitors]\n2 = ['secondary', '''\nbuilt-in\n# x''']",
        "[workspace-to-monitor-force-assignment]\n3 = \"\"\"\n[monitors]\n4 = 'main'\"\"\"",
        // A workspace name may hold brackets, which is how a rule's command gets a line that opens with one.
        "[[on-window-detected]]\nif.app-id = 'com.example.ml'\nrun = '''move-node-to-workspace\n[gaps]#'''",
        "[[on-window-detected]]\nif.app-id = 'com.example.basic'\nrun = \"\"\"move-node-to-workspace\n[on-window]#\"\"\"",
        "[on-window]\n'com.apple.mail' = '''move-node-to-workspace\n[[on-window-detected]]#'''",
        "[key-mapping]\npreset = '''dvorak'''",
        "[gaps]\nouter.top = [\n  { monitor.\"built-in\" = 3 },\n  6,\n]",
    ]

    /// `multiline` adds the fragments above and at least one of them. Without it the draws are the
    /// ones every other case has always made, so their configs stay the same.
    private static func generate(_ rng: inout SplitMix64, multiline: Bool = false) -> String {
        let preamble = multiline ? preambleFragments + multilinePreambleFragments : preambleFragments
        let sectionPool = multiline ? sectionFragments + multilineSectionFragments : sectionFragments
        var parts: [String] = []
        for _ in 0 ..< Int.random(in: 0 ... 5, using: &rng) {
            parts.append(preamble.randomElement(using: &rng)!)
        }
        var sections: [String] = []
        for _ in 0 ..< Int.random(in: 0 ... 4, using: &rng) {
            sections.append(sectionPool.randomElement(using: &rng)!)
        }
        if multiline { sections.append(multilineSectionFragments.randomElement(using: &rng)!) }
        parts += sections.shuffled(using: &rng)
        let text = parts.joined(separator: Bool.random(using: &rng) ? "\n\n" : "\n")
        return Bool.random(using: &rng) ? text : text.replacingOccurrences(of: "\n", with: "\r\n")
    }
}
