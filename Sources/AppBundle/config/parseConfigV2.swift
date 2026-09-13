import Common
import TOMLKit

// Config v2 -- a FRONT-END that desugars into the existing `Config`.
//
// The tree, the layout engine, the commands and the `Config` struct are untouched: v2 changes the
// shape of the FILE, not of the program. That keeps the blast radius to this file plus a handful of
// lines in `parseConfig`, and it means every existing test still describes real behavior.
//
// v2 is a strict SUPERSET of v1 -- every v1 key still parses. That is not politeness, it is what
// keeps the settings GUI safe: `ConfigurationWriter` emits `[mode.<name>.binding]` and
// `[[on-window-detected]]`, so a v2 file that has been edited by the GUI is a MIXTURE of both
// spellings and has to keep loading.

/// Top-level keys that exist only in v2. Their presence is what identifies the schema.
let configV2RootKeys: [String] = ["mod", "workspaces", "keys", "monitors", "on-window"]

/// Which schema a file is written in, decided by SHAPE -- nobody should have to write `version = 2`.
///
/// * any v2 key present                    => v2
/// * only `[mode.*]`                       => v1
/// * both                                  => v2. The GUI appends `[mode.main.binding]` to whatever
///                                            file it is handed, so this is a shape we CREATE. v2
///                                            keeps honouring `[mode.*]`, so nothing is lost.
/// * neither (empty file, or scalars only) => v1. Binding generation is opt-in: silence must not
///                                            invent thirty bindings for a config that never asked.
func isConfigV2(_ table: TOMLTable) -> Bool { configV2RootKeys.contains { table[$0] != nil } }

/// The i3 defaults `mod` generates, as (key notation suffix, command).
///
/// Deliberately NOT including `mod-shift-semicolon = 'mode service'`: a `mode` command pointing at a
/// mode that does not exist strands the user in a mode with no bindings, and whether a `service`
/// mode exists is up to the file. The shipped default binds it explicitly in `[keys]` instead.
private let i3DefaultBindings: [(String, String)] = [
    ("h", "focus left"),
    ("j", "focus down"),
    ("k", "focus up"),
    ("l", "focus right"),

    ("shift-h", "move left"),
    ("shift-j", "move down"),
    ("shift-k", "move up"),
    ("shift-l", "move right"),

    ("minus", "resize smart -50"),
    ("equal", "resize smart +50"),

    ("slash", "layout tiles horizontal vertical"),
    ("comma", "layout accordion horizontal vertical"),

    ("tab", "workspace-back-and-forth"),
]

/// Every binding `mod` + `workspaces` generate, as (key notation, command).
///
/// Shared with the migration collapser, which recognises exactly this set and folds it back into
/// `mod` + `workspaces`. One list, so the two directions cannot drift apart.
func generatedBindingsV2(mod: String, workspaces: [String]) -> [(notation: String, command: String)] {
    var result: [(notation: String, command: String)] = i3DefaultBindings.map { ("\(mod)-\($0.0)", $0.1) }
    for name in workspaces {
        guard let key = workspaceKeyNotation(name) else { continue }
        result.append(("\(mod)-\(key)", "workspace \(name)"))
        result.append(("\(mod)-shift-\(key)", "move-node-to-workspace \(name)"))
    }
    return result
}

/// The key a workspace is reached by: its first character, lower-cased. `1` -> `1`, `A` -> `a`,
/// `dev` -> `d`. A whole word has no key of its own, and its initial is the one a user reaches for;
/// anything else needs an explicit `[keys]` entry.
func workspaceKeyNotation(_ name: String) -> String? {
    name.first.map { String($0).lowercased() }
}

/// Desugars the v2 keys of `rawTable` into `config`, which has already been through the v1 parser.
///
/// Layering, weakest first: generated -> `[keys]` -> `[mode.*]`. "Anything in `[keys]` overrides a
/// generated binding with the same key" is the rule that keeps the defaults from trapping anyone,
/// and `[mode.*]` sits on top because that is what the settings GUI writes.
@MainActor func applyConfigV2(_ rawTable: TOMLTable, _ config: inout Config, _ errors: inout [TomlParseError]) {
    let mapping = config.keyMapping.resolve()
    var modes: [String: Mode] = [:]

    // Parsed here, once, whether or not there is a `mod`. It used to be read only inside
    // `generatedModeV2`, behind its `mod` guard -- so a config without `mod`, which is every config
    // migrated from upstream, listed nine workspaces and got none of them, without a word (#40).
    let workspaceNames = rawTable["workspaces"].map { parseWorkspaceNames($0, .rootKey("workspaces"), &errors) } ?? []
    config.persistentWorkspaces.formUnion(workspaceNames)

    if let generated = generatedModeV2(rawTable, workspaceNames, mapping, &errors) {
        modes[mainModeId] = generated
    }
    for (name, mode) in rawTable["keys"].map({ parseKeysTable($0, .rootKey("keys"), &errors, mapping) }) ?? [:] {
        modes[name] = Mode(name: nil, bindings: (modes[name]?.bindings ?? [:]) + mode.bindings)
    }
    for (name, mode) in config.modes {
        modes[name] = Mode(name: mode.name, bindings: (modes[name]?.bindings ?? [:]) + mode.bindings)
    }
    // v2 always HAS a main mode -- it is `[keys]`, plus whatever `mod` generated. Requiring the user
    // to declare it (as v1 does) would mean writing an empty section to say nothing.
    modes[mainModeId] = modes[mainModeId] ?? .zero
    config.modes = modes

    if let raw = rawTable["monitors"] {
        config.workspaceToMonitorForceAssignment = config.workspaceToMonitorForceAssignment
            + parseWorkspaceToMonitorAssignment(raw, .rootKey("monitors"), &errors)
    }

    if let raw = rawTable["on-window"] {
        // Appended, so an explicit `[[on-window-detected]]` rule still gets first refusal. Matching
        // is by app id here, which is unique per app, so the order WITHIN this block cannot matter.
        config.onWindowDetected += parseOnWindow(raw, .rootKey("on-window"), &errors)
    }
}

/// The main mode as generated by `mod`, or nil when the file has no `mod`.
///
/// Generation keys off `mod` and nothing else -- there is no default modifier. A default would make
/// migration dishonest: a v1 config whose bindings do NOT match the generated set is migrated to a
/// bare `[keys]` block, and if `mod` defaulted to something, that file would silently grow thirteen
/// bindings the user never had.
@MainActor private func generatedModeV2(_ rawTable: TOMLTable, _ workspaces: [String], _ mapping: [String: Key], _ errors: inout [TomlParseError]) -> Mode? {
    let backtrace: TomlBacktrace = .rootKey("mod")
    guard let rawMod = rawTable["mod"] else { return nil }
    guard let mod = parseString(rawMod, backtrace).getOrNil(appendErrorTo: &errors) else { return nil }
    let unknown = mod.split(separator: "-").filter { modifiersMap[String($0)] == nil }
    if !unknown.isEmpty {
        errors.append(.semantic(backtrace, "'\(unknown.joined(separator: "-"))' is not a modifier. Use cmd, alt, ctrl or shift"))
        return nil
    }
    return Mode(name: nil, bindings: bindingsFrom(generatedBindingsV2(mod: mod, workspaces: workspaces), backtrace, &errors, mapping))
}

/// `[keys]` is the main mode's bindings; a sub-table `[keys.<name>]` is a named mode. A binding
/// value is a string or an array of strings, never a table, so the two can't be confused.
@MainActor private func parseKeysTable(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError], _ mapping: [String: Key]) -> [String: Mode] {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, backtrace))
        return [:]
    }
    var result: [String: Mode] = [:]
    let flat = TOMLTable()
    for (key, value) in table {
        if let sub = value.table {
            result[key] = Mode(name: nil, bindings: parseBindings(sub, backtrace + .key(key), &errors, mapping))
        } else {
            flat[key] = value
        }
    }
    result[mainModeId] = Mode(name: nil, bindings: (result[mainModeId]?.bindings ?? [:]) + parseBindings(flat, backtrace, &errors, mapping))
    return result
}

/// `[on-window]` is `[[on-window-detected]]` for its common case: one app id, one command.
///
/// It is desugared into a real `[[on-window-detected]]` table and handed to the same parser, so the
/// restrictions on what a window callback may run are enforced in exactly one place.
@MainActor private func parseOnWindow(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> [WindowDetectedCallback] {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, backtrace))
        return []
    }
    return table.keys.sorted().compactMap { appId in
        let matcher = TOMLTable()
        matcher["app-id"] = appId
        let callback = TOMLTable()
        callback["if"] = matcher
        callback["run"] = table[appId]
        return parseWindowDetectedCallback(callback, backtrace + .key(appId), &errors)
    }
}

/// `workspaces = "1-9"`, `["dev", "web"]`, or both: `["1-9", "dev"]`.
///
/// A token is a range only when it is `<char>-<char>` -- so `my-workspace` stays the literal name
/// it obviously is.
///
/// Shared by `workspaces` and `persistent-workspaces`. Every name must be one a command can reach:
/// `next` or `focused` would be declared, kept alive, and impossible to switch to.
func parseWorkspaceNames(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> [String] {
    if let array = raw.array {
        return array.enumerated().flatMap { index, item in parseWorkspaceNames(item, backtrace + .index(index), &errors) }
    }
    guard let token: String = raw.string ?? raw.int.map(String.init) else {
        errors.append(expectedActualTypeError(expected: [.string, .int, .array], actual: raw.type, backtrace))
        return []
    }
    return (expandWorkspaceRange(token) ?? [token]).filter { name in
        switch WorkspaceName.parse(name) {
            case .success: return true
            case .failure(let message):
                errors.append(.semantic(backtrace, message))
                return false
        }
    }
}

/// `"1-9"` -> `["1", ..., "9"]`. nil when the token is not a range.
func expandWorkspaceRange(_ token: String) -> [String]? {
    let parts = token.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].count == 1, parts[1].count == 1 else { return nil }
    guard let from = parts[0].unicodeScalars.first, let to = parts[1].unicodeScalars.first,
          from.properties.isAlphabetic || ("0" ... "9").contains(from),
          from.value <= to.value
    else { return nil }
    return (from.value ... to.value).compactMap { Unicode.Scalar($0).map { String(Character($0)) } }
}

/// Turns (notation, command) pairs into real bindings, reporting a redeclaration rather than
/// silently dropping one -- two workspaces whose names start with the same letter generate the same
/// key, and a workspace that silently has no shortcut is the worst possible outcome.
@MainActor private func bindingsFrom(
    _ pairs: [(notation: String, command: String)],
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
    _ mapping: [String: Key],
) -> [String: HotkeyBinding] {
    var result: [String: HotkeyBinding] = [:]
    for (notation, command) in pairs {
        let binding = parseBinding(notation, backtrace, mapping)
            .flatMap { modifiers, key -> ParsedToml<HotkeyBinding> in
                parseCommand(command).toEither().toParsedToml(backtrace).map {
                    HotkeyBinding(modifiers, key, [$0], descriptionWithKeyNotation: notation)
                }
            }
            .getOrNil(appendErrorTo: &errors)
        guard let binding else { continue }
        if result[binding.descriptionWithKeyCode] != nil {
            errors.append(.semantic(backtrace, "'\(notation)' is generated twice. Two workspaces starting with the same character can't share a key -- rename one, or bind it in [keys]"))
        }
        result[binding.descriptionWithKeyCode] = binding
    }
    return result
}
