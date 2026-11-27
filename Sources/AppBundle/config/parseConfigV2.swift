import Common
import TOMLKit

// Config v2 -- a FRONT-END that desugars into the existing `Config`.
//
// The tree, the layout engine, the commands and the `Config` struct are untouched: v2 changes the
// shape of the FILE, not of the program. That keeps the blast radius to this file plus a handful of
// lines in `parseConfig`, and it means every existing test still describes real behavior.
//
// v2 is a strict SUPERSET of v1 -- every v1 key still parses. That is not politeness, it is what
// keeps the settings GUI safe: `ConfigurationWriter` adds v2 sections beside the v1 lines it leaves
// alone, and writes `[[on-window-detected]]` for any rule the shorthand can't express, so a file that
// has been edited by the GUI can be a MIXTURE of both spellings and has to keep loading.

/// Top-level keys that exist only in v2. Their presence is what identifies the schema.
let configV2RootKeys: [String] = ["mod", "workspaces", "keys", "monitors", "on-window"]

/// Which schema a file is written in, decided by SHAPE -- nobody should have to write `version = 2`.
///
/// * any v2 key present                    => v2
/// * only `[mode.*]`                       => v1
/// * both                                  => v2. The GUI adds `[keys]` beside a `[mode.*]` it is
///                                            leaving alone, so this is a shape we CREATE. v2 keeps
///                                            honouring `[mode.*]`, so nothing is lost.
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
/// and `[mode.*]` sits on top so an older file's explicit binding keeps winning.
@MainActor func applyConfigV2(_ rawTable: TOMLTable, _ config: inout Config, _ errors: inout [TomlParseError], _ mapping: [String: Key]) {
    var modes: [String: Mode] = [:]

    // Parsed here, once, whether or not there is a `mod`. It used to be read only inside
    // `generatedModeV2`, behind its `mod` guard -- so a config without `mod`, which is every config
    // migrated from upstream, listed nine workspaces and got none of them, without a word (#40).
    let workspaceNames = rawTable["workspaces"].map { parseWorkspaceNames($0, .rootKey("workspaces"), &errors) } ?? []
    config.persistentWorkspaces.formUnion(workspaceNames)

    if let generated = generatedModeV2(rawTable, workspaceNames, mapping, &errors) {
        modes[mainModeId] = generated
    }
    let keysModes = rawTable["keys"].map { parseKeysTable($0, .rootKey("keys"), &errors, mapping) } ?? [:]
    for (name, mode) in keysModes {
        modes[name] = merging(modes[name], mode.bindings)
    }
    for (name, mode) in config.modes {
        // A warning, not an error: the file loads, but one of the two lines does nothing.
        for (code, binding) in keysModes[name]?.bindings ?? [:] where mode.bindings[code] != nil {
            let section = name == mainModeId ? TomlBacktrace.rootKey("keys") : .rootKey("keys") + .key(name)
            errors.append(.deprecation(
                section + .key(binding.descriptionWithKeyNotation),
                "Also bound in [mode.\(name).binding], which wins. Keep one.",
            ))
        }
        modes[name] = merging(modes[name], mode.bindings)
    }
    // v2 always HAS a main mode -- it is `[keys]`, plus whatever `mod` generated. Requiring the user
    // to declare it (as v1 does) would mean writing an empty section to say nothing.
    modes[mainModeId] = modes[mainModeId] ?? .zero
    config.modes = modes

    if let raw = rawTable["monitors"] {
        let monitors = parseWorkspaceToMonitorAssignment(raw, .rootKey("monitors"), &errors)
        for name in monitors.keys.sorted() where config.workspaceToMonitorForceAssignment[name] != nil {
            errors.append(.deprecation(
                .rootKey("workspace-to-monitor-force-assignment") + .key(name),
                "Also pinned in [monitors], which wins. Keep one.",
            ))
        }
        config.workspaceToMonitorForceAssignment = config.workspaceToMonitorForceAssignment + monitors
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
        errors.append(.semantic(backtrace, modifierError(unknown.joined(separator: "-"))))
        return nil
    }
    let generated = TOMLTable()
    for (notation, command) in generatedBindingsV2(mod: mod, workspaces: workspaces) {
        // Reported rather than one silently replacing the other: two workspaces whose names start with
        // the same letter generate the same key, and a workspace with no shortcut is the worst outcome.
        if generated[notation] != nil {
            errors.append(.semantic(backtrace, "'\(notation)' is generated twice. Two workspaces starting with the same character can't share a key -- rename one, or bind it in [keys]"))
        }
        generated[notation] = command
    }
    return Mode(bindings: parseBindings(generated, backtrace, &errors, mapping))
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
            result[key] = Mode(bindings: parseBindings(sub, backtrace + .key(key), &errors, mapping))
        } else {
            flat[key] = value
        }
    }
    result[mainModeId] = merging(result[mainModeId], parseBindings(flat, backtrace, &errors, mapping))
    return result
}

/// `bindings` laid over `mode`: on a key both have, `bindings` wins.
private func merging(_ mode: Mode?, _ bindings: [String: HotkeyBinding]) -> Mode {
    Mode(bindings: (mode?.bindings ?? [:]) + bindings)
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
    let names: [String]
    switch expandWorkspaceRange(token) {
        case nil: names = [token]
        case .success(let range): names = range
        case .failure(let message):
            errors.append(.semantic(backtrace, message))
            return []
    }
    return names.filter { name in
        switch WorkspaceName.parse(name) {
            case .success: return true
            case .failure(let message):
                errors.append(.semantic(backtrace, message))
                return false
        }
    }
}

/// `"1-9"` -> `["1", ..., "9"]`. nil when the token is not a range.
///
/// A failure, not nil, for a range that leaves its class: `A-z` runs through `[`, `^` and `_`, and nil
/// would quietly declare one workspace literally named `A-z`.
func expandWorkspaceRange(_ token: String) -> Parsed<[String]>? {
    let parts = token.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0].count == 1, parts[1].count == 1 else { return nil }
    guard let from = parts[0].unicodeScalars.first, let to = parts[1].unicodeScalars.first,
          let kind = rangeClass(from),
          from.value <= to.value
    else { return nil }
    let scalars = (from.value ... to.value).compactMap(Unicode.Scalar.init)
    guard scalars.allSatisfy({ rangeClass($0) == kind }) else {
        return .failure("'\(token)': a range stays within digits, lower-case or upper-case letters")
    }
    return .success(scalars.map { String(Character($0)) })
}

private func rangeClass(_ scalar: Unicode.Scalar) -> String? {
    if ("0" ... "9").contains(scalar) { return "digit" }
    if scalar.properties.isLowercase { return "lower" }
    if scalar.properties.isUppercase { return "upper" }
    if scalar.properties.isAlphabetic { return "letter" } // a script without case
    return nil
}
