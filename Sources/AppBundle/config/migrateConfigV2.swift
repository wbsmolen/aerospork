import Common
import Foundation
import TOMLKit

// Migration from the v1 schema to v2, run once on startup.
//
// The whole thing rests on one invariant: **the migrated config must parse to a `Config` equal to
// the original**. That is checked at runtime, not just in a test -- `migrateToConfigV2` refuses to
// return anything it cannot prove equivalent, so a config whose shape the collapser does not
// understand is simply left alone instead of being guessed at.

/// The v2 text for a v1 config, or nil when there is nothing safe to do.
///
/// nil means: already v2, has no bindings to collapse, does not currently parse, or the conversion
/// came out different. Every one of those is a reason to leave the user's file exactly as it is.
@MainActor func migrateToConfigV2(_ text: String) -> String? {
    guard let v1 = try? TOMLTable(string: text), !isConfigV2(v1), v1[modeConfigRootKey] != nil else { return nil }
    guard case .success(let before) = parseConfig(text) else { return nil }
    let migrated = renderConfigV2(v1)
    guard case .success(let after) = parseConfig(migrated), configsAreEquivalent(before, after) else { return nil }
    return migrated
}

/// Converts the user's config in place, once, keeping the original as `<name>.pre-v2`.
///
/// Called from `readConfig` rather than a dedicated startup hook: that covers `reload-config` and
/// the hot-reload path for free, and it is a no-op from the second call onwards because the file is
/// v2 by then.
@MainActor func migrateUserConfigToV2IfNeeded() {
    // A test suite that rewrites the config of the machine it runs on is a bug report waiting to
    // happen -- and under `swift test` this resolves to the DEVELOPER'S own ~/.aerospork-debug.toml.
    guard !isUnitTest else { return }
    guard case .file(let url) = findCustomConfigUrl() else { return }
    let backup = url.appendingPathExtension("pre-v2")
    // Already migrated, or the user deliberately went back to v1. Either way, migrating a second
    // time would overwrite the only copy of what they originally wrote.
    guard !FileManager.default.fileExists(atPath: backup.path) else { return }
    guard let original = try? String(contentsOf: url, encoding: .utf8),
          let migrated = migrateToConfigV2(original) else { return }
    // Back up FIRST. If this fails there is no safe copy, so there is no migration either.
    guard (try? original.write(to: backup, atomically: true, encoding: .utf8)) != nil else { return }
    ConfigFileWatcher.suppressNextSelfWrite()
    try? migrated.write(to: url, atomically: true, encoding: .utf8)
}

// MARK: - Rendering

private let assignmentRootKey = "workspace-to-monitor-force-assignment"

/// Everything except the bindings is copied across untouched (`[monitors]` is the same data under a
/// name you can type). Comments and formatting are lost -- which is exactly why the original is kept
/// as `<name>.pre-v2`.
@MainActor private func renderConfigV2(_ v1: TOMLTable) -> String {
    let out = TOMLTable()
    for key in v1.keys where key != modeConfigRootKey && key != assignmentRootKey {
        out[key] = v1[key]
    }
    if let assignments = v1[assignmentRootKey] { out["monitors"] = assignments }
    if let gaps = v1["gaps"]?.table { out["gaps"] = collapseGaps(gaps) }

    let keys = TOMLTable()
    var main: [String: TOMLValueConvertible] = [:]
    for (modeName, modeValue) in v1[modeConfigRootKey]?.table ?? TOMLTable() {
        guard let bindings = modeValue.table?["binding"]?.table else { continue }
        if modeName == mainModeId {
            for (key, value) in bindings { main[key] = value }
        } else {
            let mode = TOMLTable()
            for (key, value) in bindings { mode[key] = value }
            keys[modeName] = mode
        }
    }

    if let (mod, workspaces, consumed) = collapseGeneratedBindings(main) {
        out["mod"] = mod
        if !workspaces.isEmpty { out["workspaces"] = TOMLArray(compactRanges(workspaces)) }
        main = main.filter { !consumed.contains($0.key) }
    }
    for (key, value) in main { keys[key] = value }
    if !keys.keys.isEmpty { out["keys"] = keys }

    return "# AeroSpork config (v2). Your previous config is next to this file as *.pre-v2.\n" +
        "# `mod` generates the i3 defaults and one binding per workspace; anything in [keys] wins.\n\n" +
        out.convert(to: .toml)
}

/// `inner.horizontal = 8` + `inner.vertical = 8` -> `inner = 8` (see `parseGaps`).
///
/// Collapses only when EVERY edge of a group is present and identical. A group with an edge missing
/// is NOT equal to the scalar -- the missing edge parses as 0, the scalar broadcasts to all of them
/// -- and that is the aliasing this used to be skipped over. A per-monitor value is an array rather
/// than an int, so it never qualifies. `configsAreEquivalent` compares `gaps` field by field, so a
/// mistake here refuses the migration rather than shipping it.
private func collapseGaps(_ gaps: TOMLTable) -> TOMLTable {
    let groups = ["inner": ["horizontal", "vertical"], "outer": ["left", "right", "top", "bottom"]]
    let out = TOMLTable()
    for (key, value) in gaps {
        guard let edges = groups[key], let table = value.table, Set(table.keys) == Set(edges),
              let scalar = table[edges[0]]?.int, edges.allSatisfy({ table[$0]?.int == scalar })
        else {
            out[key] = value
            continue
        }
        out[key] = scalar
    }
    return out
}

/// Finds the `mod` that explains the file's bindings, and which of them it accounts for.
///
/// Conservative on purpose: `mod` is only used when EVERY i3 default is present with exactly the
/// generated command, and a workspace is only folded into `workspaces` when both halves of its pair
/// are there. Anything else stays an explicit `[keys]` entry -- a weird binding survives verbatim
/// rather than being guessed at.
private func collapseGeneratedBindings(_ main: [String: TOMLValueConvertible]) -> (mod: String, workspaces: [String], consumed: Set<String>)? {
    let commands: [String: String] = main.compactMapValues(\.string)
    // Shortest first: if both `alt` and `alt-shift` explain the defaults, `alt` is the one meant.
    let candidates = Set(main.keys.flatMap(modifierPrefixes(of:))).sorted { ($0.count, $0) < ($1.count, $1) }
    guard let mod = candidates.first(where: { mod in
        generatedBindingsV2(mod: mod, workspaces: []).allSatisfy { commands[$0.notation] == $0.command }
    }) else { return nil }

    var consumed = Set(generatedBindingsV2(mod: mod, workspaces: []).map(\.notation))
    var workspaces: [String] = []
    for (notation, command) in commands {
        guard let key = notation.removePrefixOrNil("\(mod)-"), !key.contains("-") else { continue }
        guard let name = command.removePrefixOrNil("workspace "), workspaceKeyNotation(name) == key else { continue }
        guard commands["\(mod)-shift-\(key)"] == "move-node-to-workspace \(name)" else { continue }
        workspaces.append(name)
        consumed.insert(notation)
        consumed.insert("\(mod)-shift-\(key)")
    }
    return (mod, workspaces.sorted(), consumed)
}

/// Every all-modifier prefix of a binding: `alt-shift-1` -> `["alt", "alt-shift"]`.
private func modifierPrefixes(of notation: String) -> [String] {
    var result: [String] = []
    var segments: [String] = []
    for segment in notation.split(separator: "-").dropLast().map(String.init) {
        guard modifiersMap[segment] != nil else { return result }
        segments.append(segment)
        result.append(segments.joined(separator: "-"))
    }
    return result
}

/// `["1","2","3","5"]` -> `["1-3", "5"]`. Only runs of three or more are worth a range; below that
/// the range notation is longer than the names it replaces.
private func compactRanges(_ names: [String]) -> [String] {
    var result: [String] = []
    var run: [Unicode.Scalar] = []
    func flush() {
        guard !run.isEmpty else { return }
        result += run.count >= 3
            ? ["\(Character(run.first.orDie()))-\(Character(run.last.orDie()))"]
            : run.map { String(Character($0)) }
        run = []
    }
    for name in names {
        guard name.unicodeScalars.count == 1, let scalar = name.unicodeScalars.first else { flush(); result.append(name); continue }
        if let last = run.last, scalar.value != last.value + 1 { flush() }
        run.append(scalar)
    }
    flush()
    return result
}

// MARK: - Equivalence

/// The oracle behind the migration: two `Config`s describe the same window manager.
///
/// Compared field by field rather than with `==` because `Config` cannot be `Equatable` (commands
/// and regexes are not), and because the comparison has to be deterministic -- dictionaries are
/// flattened to sorted lines before anything is compared.
///
/// Regex matchers in `on-window-detected` are NOT compared: `Regex` has no equality, and migration
/// copies those tables across byte for byte, so there is nothing there to get wrong.
@MainActor func configsAreEquivalent(_ a: Config, _ b: Config) -> Bool {
    func cmds(_ commands: [any Command]) -> [String] { commands.map { $0.args.description } }
    func bindings(_ modes: [String: Mode]) -> [String] {
        modes.flatMap { name, mode in
            mode.bindings.map { id, binding in "\(name)\t\(id)\t\(cmds(binding.commands).joined(separator: " ; "))" }
        }.sorted()
    }
    func monitors(_ assignment: [String: [MonitorDescription]]) -> [String] {
        assignment.map { "\($0.key)\t\($0.value.map(\.humanDescription).joined(separator: ","))" }.sorted()
    }
    func windows(_ callbacks: [WindowDetectedCallback]) -> [String] {
        callbacks.map { "\($0.matcher.appId ?? "")\t\($0.matcher.workspace ?? "")\t\($0.matcher.duringAeroSporkStartup?.description ?? "")\t\($0.checkFurtherCallbacks)\t\(cmds($0.run).joined(separator: " ; "))" }
    }

    return a.enableNormalizationFlattenContainers == b.enableNormalizationFlattenContainers &&
        a.enableNormalizationOppositeOrientationForNestedContainers == b.enableNormalizationOppositeOrientationForNestedContainers &&
        a.defaultRootContainerLayout == b.defaultRootContainerLayout &&
        a.defaultRootContainerOrientation == b.defaultRootContainerOrientation &&
        a.startAtLogin == b.startAtLogin &&
        a.automaticallyUnhideMacosHiddenApps == b.automaticallyUnhideMacosHiddenApps &&
        a.accordionPadding == b.accordionPadding &&
        a.autoMoveWorkspacesOnMonitorConnect == b.autoMoveWorkspacesOnMonitorConnect &&
        a.gaps == b.gaps &&
        a.keyMapping == b.keyMapping &&
        a.execConfig == b.execConfig &&
        a.execOnWorkspaceChange == b.execOnWorkspaceChange &&
        cmds(a.afterStartupCommand) == cmds(b.afterStartupCommand) &&
        cmds(a.onFocusChanged) == cmds(b.onFocusChanged) &&
        cmds(a.onFocusedWorkspaceChanged) == cmds(b.onFocusedWorkspaceChanged) &&
        cmds(a.onFocusedMonitorChanged) == cmds(b.onFocusedMonitorChanged) &&
        a.preservedWorkspaceNames.sorted() == b.preservedWorkspaceNames.sorted() &&
        // `persistentWorkspaces` is deliberately NOT compared. Folding a v1 keymap's `alt-1..9` pairs
        // into `workspaces` makes those workspaces persistent, which is a change -- but the one that
        // matches what upstream's v1 did with bound names, and so what a migrating user expects.
        bindings(a.modes) == bindings(b.modes) &&
        monitors(a.workspaceToMonitorForceAssignment) == monitors(b.workspaceToMonitorForceAssignment) &&
        windows(a.onWindowDetected) == windows(b.onWindowDetected)
}

extension String {
    fileprivate func removePrefixOrNil(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
