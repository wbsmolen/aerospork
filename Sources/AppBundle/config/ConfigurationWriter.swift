import Common
import Foundation
import TOMLKit

/// Resolved path we write the user config to. Uses the existing user config if there is one,
/// otherwise the conventional dotfile in the home directory (which we create on first save).
/// Where the GUI should write.
///
/// `findCustomConfigUrl()` only reports files that already EXIST, so falling back to the home
/// dotfile whenever it returns non-`.file` was wrong in two ways:
///   * with `--config-path /new/file.toml` (not yet created) the GUI wrote `~/.aerospork.toml`,
///     which the server never reads — the save "succeeded" and changed nothing;
///   * under `.ambiguousConfigError` the base text fell back to the *bundled default*, so a save
///     would overwrite a real user config with defaults-plus-edits.
@MainActor func userConfigTargetUrl() -> Result<URL, String> {
    // An explicit --config-path is the only file the server reads; honour it even if absent.
    if let explicit = serverArgs.configLocation { return .success(URL(filePath: explicit)) }
    switch findCustomConfigUrl() {
        case .file(let url): return .success(url)
        case .noCustomConfigExists:
            return .success(FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName))
        case .ambiguousConfigError(let candidates):
            return .failure(
                "Several config files exist, so it is not safe to guess which one to write:\n" +
                    candidates.map(\.path).joined(separator: "\n") +
                    "\nRemove one, or start with --config-path.",
            )
    }
}

/// The text we edit in place. The user config if present, else the shipped default config so a
/// first save produces a full, commented config seeded from the defaults.
@MainActor func configBaseText() -> String {
    let url = findCustomConfigUrl().urlOrNil ?? defaultConfigUrl
    return (try? String(contentsOf: url)) ?? ""
}

/// The one and only config writer.
///
/// It edits the existing config text line-by-line and only rewrites the keys the UI manages, so
/// user comments, key order, and any sections the UI doesn't understand survive untouched. It only
/// emits keys that the canonical `parseConfig` accepts.
@MainActor
enum ConfigurationWriter {
    /// Writes text that has ALREADY been rendered and validated. Taking the final string rather
    /// than re-rendering means the bytes that were validated are exactly the bytes that land on
    /// disk -- previously `validate` and `write` rendered separately from a re-read base file.
    struct WriteRefused: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    static func write(_ result: String) throws {
        let target: URL
        switch userConfigTargetUrl() {
            case .success(let url): target = url
            case .failure(let reason): throw WriteRefused(reason: reason)
        }

        let existed = FileManager.default.fileExists(atPath: target.path)
        if existed { backUp(target) }
        ConfigFileWatcher.suppressNextSelfWrite()
        try result.write(to: target, atomically: true, encoding: .utf8)
        // The watcher bails when the file doesn't exist, and only re-arms from its own event
        // handler -- so the first-ever GUI save left hot-reload dead until an app restart.
        if !existed { ConfigFileWatcher.start() }
    }

    // MARK: - Backups

    /// How many generations to keep. A single `.backup` was worse than useless: the save that made
    /// the user notice the damage was also the save that overwrote the last good copy. Five covers
    /// "I broke it a few edits ago" without turning the home directory into a version control
    /// system -- anything older belongs in the user's own VCS.
    static let backupsToKeep = 5

    /// `<config>.toml.<yyyyMMdd-HHmmss>.backup`. Timestamp before the extension so the names sort
    /// chronologically as plain strings, and `.backup` last so nothing mistakes one for a config.
    private static let backupSuffix = ".backup"

    private static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// Copies `target` aside and prunes to `backupsToKeep`. Best-effort: a config we could not back
    /// up is not a reason to refuse the user's edit, and the pre-write validation already ran.
    static func backUp(_ target: URL, now: Date = Date()) {
        let backup = target.appendingPathExtension("\(timestamp(now))\(backupSuffix)")
        // Same second as an existing backup (a debounced save burst): keep the older copy, which is
        // further from whatever went wrong.
        if !FileManager.default.fileExists(atPath: backup.path) {
            try? FileManager.default.copyItem(at: target, to: backup)
        }
        for stale in backups(of: target).dropFirst(backupsToKeep) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// Existing backups of `target`, newest first.
    static func backups(of target: URL) -> [URL] {
        let dir = target.deletingLastPathComponent()
        let prefix = target.lastPathComponent + "."
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(backupSuffix) }
            .sorted(by: >) // name sorts chronologically, so this is newest-first
            .map { dir.appending(path: $0) }
    }

    /// Backups of the config the GUI writes to, newest first. Empty when the target is ambiguous.
    static func backupsOfUserConfig() -> [URL] {
        guard case .success(let target) = userConfigTargetUrl() else { return [] }
        return backups(of: target)
    }

    /// Pure text transform, separated from file I/O so it can be tested directly.
    ///
    /// The governing rule is **do no harm**: a section the user did not edit is left exactly as it
    /// was, byte for byte. This is not an optimization -- the view model models a lossy projection
    /// of the config (per-monitor gap arrays collapse to their default, monitor fingerprints
    /// collapse to a single string, multi-monitor fallback lists collapse to `.first`), so
    /// unconditionally re-serializing a section *destroys* anything the UI can't express. Guarding
    /// on "did this actually change" is what makes an untouched save a no-op.
    ///
    /// **That rule only holds inside the TOML subset this writer understands.** Nine legal TOML
    /// spellings defeat line surgery, silently deleting data or producing duplicate keys.
    /// `unsupportedShapeReason` is what keeps the promise honest: callers must consult it
    /// first and refuse the edit, because `render` itself cannot detect that it is doing damage.
    static func render(baseText base: String, from vm: ConfigurationViewModel) -> String {
        // The raw TOML tab is authoritative only when Apply was actually pressed. Keying this off
        // `rawTomlEdited` meant an unapplied raw buffer hijacked unrelated structured edits.
        if vm.rawTomlApplyRequested { return vm.rawToml }

        // CRLF is not cosmetic here. Splitting on "\n" alone leaves a trailing "\r" on every line,
        // and `sectionHeaderName` requires a line to END with "]" -- so "[gaps]\r" was not
        // recognised as a section by the writer OR by `unsupportedShapeReason`. The writer then
        // appended a second [gaps] table and produced a duplicate-key parse error. Found by the
        // property fuzzer; it accounted for most of its failures on its own.
        let usesCRLF = base.contains("\r\n")
        var lines = base.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // General settings (top-level scalars). Only rewrite the ones that actually changed --
        // rewriting in place would also normalize quoting and could duplicate a quoted key.
        for (key, value) in vm.changedScalars() {
            setScalar(&lines, key, value)
        }
        for (key, commands) in vm.changedCallbacks() {
            setScalar(&lines, key, tomlArray(commands))
        }

        if vm.gapsEdited { replaceGaps(&lines, vm) }
        if vm.assignmentsEdited { replaceAssignments(&lines, vm, isV2: isV2(base)) }
        if vm.keyMappingEdited { replaceKeyMapping(&lines, vm) }
        if vm.execEdited { replaceExec(&lines, vm) }
        if vm.windowRulesEdited { replaceWindowRules(&lines, vm, isV2: isV2(base)) }
        applyBindingDiff(&lines, vm, base: base)

        // Give the file back the line ending it arrived with. Silently converting a CRLF config to
        // LF would show up as a whole-file diff in the user's dotfiles repo.
        return lines.joined(separator: usesCRLF ? "\r\n" : "\n")
    }

    /// Validate before writing. A config that fails to parse used to land on disk anyway and only
    /// then pop a separate error dialog, leaving the user with a broken file and two error surfaces.
    static func validate(_ text: String) -> String? {
        switch parseConfig(text) {
            case .success: return nil
            case .failure(let errors): return errors.map(\.description).joined(separator: "\n")
        }
    }

    /// TOML has many equivalent spellings for the same data. This writer edits *lines*, so it only
    /// understands one of them: single-line values, bare keys, and `[section]` headers.
    ///
    /// Given a file that uses any other legal spelling, line surgery previously produced either a
    /// duplicate-key parse error or -- worse -- clean-parsing TOML with the user's data quietly
    /// removed. Nine such shapes are known. Rather than pretend to handle them,
    /// detect them and refuse: the Raw TOML tab can edit anything, and a refusal the user can read
    /// beats silent corruption.
    ///
    /// Returns nil when structured editing is safe, or a human-readable reason when it is not.
    /// Whether the base text is written in the v2 schema. Only the sections the writer REWRITES
    /// need to know: everything else is either identical in both schemas or invisible to the view
    /// model, and what the view model cannot see, the writer cannot delete.
    private static func isV2(_ base: String) -> Bool {
        (try? TOMLTable(string: base)).map(isConfigV2) ?? false
    }

    static func unsupportedShapeReason(_ text: String) -> String? {
        let managedSections = ["gaps", "exec", "key-mapping", "workspace-to-monitor-force-assignment", "monitors", "on-window"]
        let managedScalars = [
            "start-at-login", "automatically-unhide-macos-hidden-apps",
            "auto-move-workspaces-on-monitor-connect", "enable-normalization-flatten-containers",
            "enable-normalization-opposite-orientation-for-nested-containers",
            "default-root-container-layout", "default-root-container-orientation",
            "accordion-padding", "after-startup-command", "on-focus-changed",
            "on-focused-workspace-changed", "on-focused-monitor-changed",
        ]

        // Sub-tables this writer re-emits itself are fine; any other sub-table of a
        // wholesale-rewritten section would be silently dropped.
        let emittedSubTables: Set<String> = ["gaps.inner", "gaps.outer", "exec.env-vars"]
        // First path segment of the keys we re-emit inside a rewritten section. Anything else
        // there is lost. Segment-wise, because `inner.horizontal` inside [gaps] is a form we do
        // emit, while `key-notation-to-key-code.unicorn` inside [key-mapping] is not.
        let emittedKeysBySection: [String: Set<String>] = [
            "key-mapping": ["preset"],
            "exec": ["inherit-env-vars", "env-vars"],
            "gaps": ["inner", "outer"],
        ]

        // Swift treats "\r\n" as ONE Character, so `split(separator: "\n")` does not split a CRLF
        // file at all: every walker in this type then sees the entire config as a single line,
        // finds no section headers, and appends duplicate `[mode.main.binding]` / `[gaps]` blocks
        // that make the file stop parsing. A lone `\r` (classic Mac) breaks it the same way.
        // Found by `ConfigSafetyWriterFuzzTest`, which the denylist had no entry for.
        if text.contains("\r") {
            return "This config uses Windows or classic-Mac line endings, which this editor cannot rewrite safely. Use the Raw TOML tab."
        }

        var section = "" // "" == top level
        var openBracketDepth = 0

        // Same CRLF normalization as `render` -- the guard must see exactly what the writer sees, or
        // it will bless a file the writer then mangles.
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        {
            let line = raw.trimmingCharacters(in: .whitespaces)

            // Inside a multi-line value: consume until the brackets balance.
            if openBracketDepth > 0 {
                openBracketDepth += line.count(where: { $0 == "[" }) - line.count(where: { $0 == "]" })
                continue
            }
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") {
                if line.hasPrefix("[[") { section = ""; continue } // array-of-tables: handled wholesale
                guard let name = sectionHeaderName(line) else { continue }
                section = name
                for managed in managedSections
                    where name.hasPrefix("\(managed).") && !emittedSubTables.contains(name)
                {
                    return "[\(name)] is a sub-table of a section this editor rewrites, so editing here would delete it. Use the Raw TOML tab."
                }
                continue
            }

            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            // Multi-line array: `setScalar`/`removeBindingLine` rewrite line 1 and orphan the rest.
            let opens = value.count(where: { $0 == "[" }) - value.count(where: { $0 == "]" })
            if opens > 0 {
                if section.isEmpty, managedScalars.contains(key) {
                    return "'\(key)' is written as a multi-line array, which this editor cannot rewrite safely. Use the Raw TOML tab."
                }
                if section.hasPrefix("mode.") || section == "keys" || section.hasPrefix("keys.") {
                    return "Binding '\(key)' is written as a multi-line array. Use the Raw TOML tab."
                }
                openBracketDepth = opens
                continue
            }

            let unquoted = key.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))

            if section.isEmpty {
                if key != unquoted, managedScalars.contains(unquoted) {
                    return "'\(key)' uses a quoted key, which this editor would duplicate rather than replace. Use the Raw TOML tab."
                }
                // Dotted / inline spelling of a section rewritten wholesale, e.g.
                // `gaps.inner.horizontal = 5` or `exec = { inherit-env-vars = false }`.
                for managed in managedSections where unquoted == managed || unquoted.hasPrefix("\(managed).") {
                    return "'\(key)' uses a dotted or inline form of [\(managed)], which this editor would duplicate. Use the Raw TOML tab."
                }
            }

            // `[mode.main]` + `binding.alt-h = …`: add/remove both target `[mode.main.binding]`.
            if section.hasPrefix("mode."), unquoted.hasPrefix("binding.") {
                return "Bindings are written as dotted keys ('\(key)'), which this editor cannot add to or remove from. Use the Raw TOML tab."
            }

            // v2 analogues. Bindings are edited by locating a `[keys]` / `[keys.<mode>]` HEADER, so
            // any spelling that defines those tables without one -- `keys = { … }`, `keys.alt-h = …`
            // at top level, or a dotted named mode inside `[keys]` -- makes the writer append a
            // second, conflicting definition instead of editing the existing entries.
            if section.isEmpty, unquoted == "keys" || unquoted.hasPrefix("keys.") {
                return "'\(key)' uses a dotted or inline form of [keys], which this editor would duplicate. Use the Raw TOML tab."
            }
            if section == "keys", unquoted.contains(".") {
                return "[keys] contains a dotted key ('\(key)'), which this editor cannot add to or remove from. Use the Raw TOML tab."
            }

            // A monitor assignment carrying more than this editor can express.
            //
            // The view model collapses a whole `MonitorDescription` to one token, and
            // `formatMonitorValue` can only re-emit a `uuid`, a monitor index, or a `name`. So
            // rewriting `[monitors]` turns
            //     2 = { fingerprint = { display_name = 'ACME Display 32 (1)', width = 3840, height = 2160 } }
            // into
            //     2 = { fingerprint = { name = 'ACME Display 32 (1)' } }
            // -- silently dropping exactly the fields that tell two identical panels apart.
            //
            // This shipped, and it damaged a real config: a save rewrote both DELL entries down to
            // bare names. The existing guard only refused the *sub-table* spelling
            // (`[workspace-to-monitor-force-assignment.2.fingerprint]`), which is the form nobody
            // writes; the inline form above is the one the docs show and the migration emits.
            //
            // Anything richer than a single `name`/`uuid` is refused rather than degraded.
            if section == "monitors" || section == "workspace-to-monitor-force-assignment",
               value.contains("fingerprint")
            {
                let fields = ["display_name", "display-name", "width", "height", "vendor", "model", "serial"]
                if let extra = fields.first(where: { value.contains($0) }) {
                    return "Monitor assignment '\(key)' pins a display by '\(extra)', which this editor cannot represent and would replace with just a name. Use the Raw TOML tab."
                }
            }

            // A key inside a rewritten section that we do not re-emit would simply vanish.
            if let emitted = emittedKeysBySection[section] {
                let firstSegment = unquoted.split(separator: ".").first.map(String.init) ?? unquoted
                if !emitted.contains(firstSegment) {
                    return "[\(section)] contains '\(key)', which this editor does not model and would delete. Use the Raw TOML tab."
                }
            }
        }
        return nil
    }

    // MARK: - Key mapping / exec / window rules

    private static func replaceKeyMapping(_ lines: inout [String], _ vm: ConfigurationViewModel) {
        removeSections(&lines) { $0 == "key-mapping" }
        lines.append(contentsOf: ["", "[key-mapping]", "preset = \(quoted(vm.keyMappingPreset))"])
    }

    private static func replaceExec(_ lines: inout [String], _ vm: ConfigurationViewModel) {
        removeSections(&lines) { $0 == "exec" || $0.hasPrefix("exec.") }
        var block = ["", "[exec]", "inherit-env-vars = \(bool(vm.execInheritEnvVars))"]
        let vars = vm.execEnvVars.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if !vars.isEmpty {
            block.append("[exec.env-vars]")
            for v in vars.sorted(by: { $0.name < $1.name }) {
                block.append("\(tomlKey(v.name)) = \(quoted(v.value))")
            }
        }
        lines.append(contentsOf: block)
    }

    /// A rule the `[on-window]` shorthand can express: an app id and a command, nothing else.
    /// `parseOnWindow` builds exactly `if.app-id` + `run` from each entry, so any other matcher or
    /// flag has to be written long form.
    private static func isShorthandExpressible(_ rule: ConfigurationViewModel.WindowRuleRow) -> Bool {
        !rule.appId.isEmpty
            && rule.appNameRegex.isEmpty
            && rule.windowTitleRegex.isEmpty
            && rule.workspace.isEmpty
            && !rule.checkFurtherCallbacks
            && rule.duringStartup == nil
    }

    private static func replaceWindowRules(_ lines: inout [String], _ vm: ConfigurationViewModel, isV2: Bool) {
        // A rule with no command yet cannot be written -- `run` is required by the parser. Leave the
        // whole section alone rather than writing the rest, because the alternative is silent
        // deletion: clearing the Command field to retype it made that rule disappear from disk on
        // the next 600ms autosave while the row stayed on screen, and every keystroke of the
        // replacement failed validation and wrote nothing. An interrupted edit lost the rule with no
        // indication. The same guard covers a value the GUI cannot read at all (`app = 42` loads as
        // an empty command), which would otherwise be quietly dropped from the user's file.
        //
        // Nothing is lost by waiting: the rules on disk keep working, and the edit lands as soon as
        // the command is complete.
        guard vm.windowRules.allSatisfy({ !$0.run.trimmingCharacters(in: .whitespaces).isEmpty }) else { return }

        removeArrayOfTables(&lines, named: "on-window-detected")
        // The shorthand table too. Removing only the long form left a v2 user's `[on-window]` rules
        // in the file alongside the long-form copy this writes, so every one of them applied twice.
        removeSections(&lines) { $0 == "on-window" }
        // A rule with no `run` yet is one the user is still filling in (the natural order is
        // matcher first, command second). It is skipped here because `run` is required by the
        // parser -- but the row is NOT dropped from the view model, so it stays on screen.
        let rules = vm.windowRules.filter { !$0.run.trimmingCharacters(in: .whitespaces).isEmpty }

        // Keep a config that was written in the v2 shorthand in the v2 shorthand, but only when
        // EVERY rule fits it and no app id repeats. Anything else is written long form.
        //
        // All-or-nothing on purpose. `parseConfigV2` appends `[on-window]` *after*
        // `on-window-detected`, so in a mixed file the long-form rules always get first refusal
        // regardless of where they sit in the text -- a list the user had ordered in the GUI would
        // not run in that order. With no long-form rules there is nothing to take precedence, and
        // app ids are unique, so order genuinely cannot matter.
        let appIds = rules.map(\.appId)
        if isV2, !rules.isEmpty, rules.allSatisfy(isShorthandExpressible), Set(appIds).count == appIds.count {
            var block = ["", "[on-window]"]
            for rule in rules.sorted(by: { $0.appId < $1.appId }) {
                block.append("\(quoted(rule.appId)) = \(tomlArray(splitCommands(rule.run)))")
            }
            lines.append(contentsOf: block)
            return
        }

        for rule in rules {
            var block = ["", "[[on-window-detected]]"]
            if !rule.appId.isEmpty { block.append("if.app-id = \(quoted(rule.appId))") }
            if !rule.appNameRegex.isEmpty { block.append("if.app-name-regex-substring = \(quoted(rule.appNameRegex))") }
            if !rule.windowTitleRegex.isEmpty { block.append("if.window-title-regex-substring = \(quoted(rule.windowTitleRegex))") }
            if !rule.workspace.isEmpty { block.append("if.workspace = \(quoted(rule.workspace))") }
            // The upstream-branded spelling of this key is no longer parsed at all, so any rule the
            // GUI round-trips is written under the only name that loads.
            if let during = rule.duringStartup { block.append("if.during-aerospork-startup = \(bool(during))") }
            if rule.checkFurtherCallbacks { block.append("check-further-callbacks = true") }
            block.append("run = \(tomlArray(splitCommands(rule.run)))")
            lines.append(contentsOf: block)
        }
    }

    /// Name of an array-of-table header (`[[on-window-detected]]` -> "on-window-detected"), nil for
    /// anything else.
    ///
    /// Parsed rather than string-compared. `[[ on-window-detected ]]` is legal TOML and TOMLKit
    /// reads it, so an exact match against `"[[name]]"` left the block in the file while the writer
    /// appended a fresh one -- two copies of the rule, and since the shorthand is parsed last, the
    /// *stale* one won. The user's edit did nothing and their config grew on every save.
    private static func arrayOfTablesHeaderName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("[["), t.hasSuffix("]]") else { return nil }
        return String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
    }

    /// Removes every `[[name]]` block. `removeSections` deliberately ignores array-of-table headers,
    /// so this is a separate walker.
    private static func removeArrayOfTables(_ lines: inout [String], named name: String) {
        var result: [String] = []
        var i = 0
        while i < lines.count {
            if arrayOfTablesHeaderName(lines[i]) == name {
                i += 1
                var end = i
                while end < lines.count, !isHeaderLine(lines[end]) { end += 1 }
                // The same rule `removeSections` follows: blank and comment lines immediately before
                // the next header document THAT header, not the block being removed. Without this,
                // editing a window rule deleted the banner comment above whatever section came next
                // -- a section the user never opened, which is exactly what the writer exists to
                // leave alone.
                var keepFrom = end
                while keepFrom > i {
                    let prev = lines[keepFrom - 1].trimmingCharacters(in: .whitespaces)
                    if prev.isEmpty || prev.hasPrefix("#") { keepFrom -= 1 } else { break }
                }
                result.append(contentsOf: lines[keepFrom ..< end])
                i = end
            } else {
                result.append(lines[i])
                i += 1
            }
        }
        lines = result
    }

    private static func splitCommands(_ s: String) -> [String] {
        s.components(separatedBy: ConfigurationViewModel.commandSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func tomlArray(_ items: [String]) -> String {
        "[" + items.map { escapedLiteral($0) }.joined(separator: ", ") + "]"
    }

    // MARK: - Scalars

    private static func setScalar(_ lines: inout [String], _ key: String, _ value: String) {
        let firstHeader = lines.firstIndex(where: isHeaderLine) ?? lines.count
        for i in 0 ..< firstHeader {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") { continue }
            if t.hasPrefix("\(key) ") || t.hasPrefix("\(key)="), t.contains("=") {
                lines[i] = "\(key) = \(value)"
                return
            }
        }
        lines.insert("\(key) = \(value)", at: firstHeader)
    }

    // MARK: - Gaps

    // Internal, not private, so ConfigTest can round-trip it without touching the real config file.
    static func replaceGaps(_ lines: inout [String], _ vm: ConfigurationViewModel) {
        removeSections(&lines) { $0 == "gaps" || $0.hasPrefix("gaps.") }
        insertAfterPreamble(&lines, [
            "",
            "[gaps]",
            "inner.horizontal = \(vm.innerGapsHorizontal)",
            "inner.vertical = \(vm.innerGapsVertical)",
            "outer.top = \(vm.outerGapsTop)",
            "outer.bottom = \(vm.outerGapsBottom)",
            "outer.left = \(vm.outerGapsLeft)",
            "outer.right = \(vm.outerGapsRight)",
        ])
    }

    // MARK: - Workspace to monitor assignments

    /// v2 spells this `[monitors]`. BOTH names have to be removed regardless of which one we then
    /// emit: the view model shows one merged list, so leaving the other section behind would
    /// resurrect the rows the user just deleted.
    private static func replaceAssignments(_ lines: inout [String], _ vm: ConfigurationViewModel, isV2: Bool) {
        removeSections(&lines) { $0 == "workspace-to-monitor-force-assignment" || $0 == "monitors" }
        let rows = vm.assignments
            .filter { !$0.workspace.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { !$0.monitor.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rows.isEmpty else { return }
        var block = ["", isV2 ? "[monitors]" : "[workspace-to-monitor-force-assignment]"]
        for r in rows.sorted(by: { $0.workspace < $1.workspace }) {
            block.append("\(tomlKey(r.workspace)) = \(formatMonitorValue(r.monitor))")
        }
        lines.append(contentsOf: block)
    }

    private static func formatMonitorValue(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespaces)
        if UUID(uuidString: t) != nil { return "{ fingerprint = { uuid = '\(t)' } }" }
        if Int(t) != nil { return t }
        if t == "main" || t == "secondary" { return quoted(t) }
        // A bare string is parsed as a *regex*, so a literal display name containing regex
        // metacharacters never matches -- and macOS names duplicate panels exactly that way,
        // e.g. "ACME Display 32 (1)". Emit a name fingerprint instead of a booby-trapped pattern.
        return "{ fingerprint = { name = \(quoted(t)) } }"
    }

    /// A bare TOML key may only contain A-Za-z0-9_- ; anything else must be quoted or the file
    /// fails to parse (an env var named `MY VAR`, a workspace named `my workspace`).
    private static func tomlKey(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        let bare = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        if !t.isEmpty, t.unicodeScalars.allSatisfy({ bare.contains($0) }) { return t }
        return escapedLiteral(t)
    }

    // MARK: - Key bindings (add / remove only)

    /// Section header a mode's bindings live under, in whichever schema the file is written in.
    /// v1 spells it `[mode.<name>.binding]`; v2 spells the main mode `[keys]` and a named mode
    /// `[keys.<name>]`. Writing the v1 spelling into a v2 file works -- the v1 parser still runs
    /// first -- but it leaves the user with two different syntaxes for the same thing in one file.
    private static func bindingSection(mode: String, isV2: Bool) -> String {
        if !isV2 { return "mode.\(mode).binding" }
        return mode == mainModeId ? "keys" : "keys.\(mode)"
    }

    private static func applyBindingDiff(_ lines: inout [String], _ vm: ConfigurationViewModel, base: String) {
        let v2 = isV2(base)
        // mode -> key -> the section header that key's line actually lives under. Tracked per KEY,
        // not per mode, because a v2 file can bind some of the main mode in `[keys]` and the rest in
        // `[mode.main.binding]`; editing a row has to rewrite the line it came from. `[keys]` is
        // filled first so `[mode.*]` overwrites it -- the same layering the parser applies, so an
        // edit lands in the section the parser actually reads.
        var original: [String: [String: (section: String, command: String)]] = [:]
        let table = try? TOMLTable(string: base)
        if v2, let keysTable = table?["keys"]?.table {
            for (k, val) in keysTable {
                if let sub = val.table {
                    for (bindKey, v) in sub {
                        original[k, default: [:]][bindKey] = ("keys.\(k)", ConfigurationViewModel.commandString(v))
                    }
                } else {
                    original[mainModeId, default: [:]][k] = ("keys", ConfigurationViewModel.commandString(val))
                }
            }
        }
        if let modeTable = table?["mode"]?.table {
            for (mode, val) in modeTable {
                guard let binding = val.table?["binding"]?.table else { continue }
                for (k, v) in binding {
                    original[mode, default: [:]][k] = ("mode.\(mode).binding", ConfigurationViewModel.commandString(v))
                }
            }
        }
        // A mode the user deleted. Scoped to modes the view model actually LOADED, so a view model
        // that never loaded any (tests, a fresh instance) cannot wipe every mode in the file.
        let deleted = vm.loadedModeNames.subtracting(vm.modes.map(\.mode))
        if !deleted.isEmpty {
            removeSections(&lines) { name in
                deleted.contains { name == "mode.\($0)" || name.hasPrefix("mode.\($0).") || (v2 && name == "keys.\($0)") }
            }
        }
        for md in vm.modes {
            let desired = Set(md.bindings.map(\.key))
            let orig = original[md.mode] ?? [:]
            // Removals are scoped to modes the view model actually LOADED, for the same reason the
            // whole-mode deletion above is: a view model that never read this file (a fresh
            // instance, a test) has an empty `modes`, and every binding in the file would look
            // deleted. Harmless while the writer only knew `[mode.*]` -- a v2 file has none -- but
            // once `[keys]` is in the diff it would silently wipe the user's bindings.
            if vm.loadedModeNames.contains(md.mode) {
                for (key, o) in orig where !desired.contains(key) {
                    removeBindingLine(&lines, section: o.section, key: key)
                }
            }
            for row in md.bindings {
                if let o = orig[row.key] {
                    // Re-binding an existing key used to be a silent no-op: the diff only added
                    // keys absent from the original and removed keys absent from the desired set,
                    // so changing a key's *command* wrote nothing and the UI reported success.
                    //
                    // Compared on the COMMAND, not just re-emitted: `formatCommand` normalizes
                    // quoting, so rewriting an untouched line would turn `key = "cmd"` into
                    // `key = 'cmd'` and make a no-op save modify the file.
                    guard row.command != o.command else { continue }
                    updateBindingLine(&lines, section: o.section, key: row.key, command: row.command)
                } else {
                    addBindingLine(&lines, section: bindingSection(mode: md.mode, isV2: v2), key: row.key, command: row.command)
                }
            }
        }
    }

    private static func updateBindingLine(_ lines: inout [String], section: String, key: String, command: String) {
        guard let h = headerIndex(lines, section) else { return }
        var i = h + 1
        while i < lines.count, !isHeaderLine(lines[i]) {
            if lineKey(lines[i]) == key {
                let indent = lines[i].prefix { $0 == " " || $0 == "\t" }
                let replacement = "\(indent)\(key) = \(formatCommand(command))"
                if lines[i] != replacement { lines[i] = replacement }
                return
            }
            i += 1
        }
    }

    private static func removeBindingLine(_ lines: inout [String], section: String, key: String) {
        guard let h = headerIndex(lines, section) else { return }
        var i = h + 1
        while i < lines.count, !isHeaderLine(lines[i]) {
            if lineKey(lines[i]) == key {
                lines.remove(at: i)
                return
            }
            i += 1
        }
    }

    private static func addBindingLine(_ lines: inout [String], section: String, key: String, command: String) {
        let line = "\(key) = \(formatCommand(command))"
        if let h = headerIndex(lines, section) {
            lines.insert(line, at: h + 1)
        } else {
            lines.append(contentsOf: ["", "[\(section)]", line])
        }
    }

    /// A binding value may hold several commands. They round-trip through the view model joined by
    /// `commandSeparator`, so split them back into a TOML array -- emitting `key = 'a ; b'` would be
    /// one bogus command. (The old code joined with ", " and re-emitted `key = 'a, b'`, silently
    /// corrupting every multi-command binding that was re-added.)
    private static func formatCommand(_ command: String) -> String {
        let parts = splitCommands(command)
        if parts.count <= 1 { return escapedLiteral(command.trimmingCharacters(in: .whitespaces)) }
        return tomlArray(parts)
    }

    // MARK: - Line helpers

    private static func bool(_ v: Bool) -> String { v ? "true" : "false" }

    /// Quote a TOML string, *escaping* rather than deleting. The previous implementation stripped
    /// quote characters out of the value, which silently changed the user's data (a command
    /// containing an apostrophe came back different).
    private static func escapedLiteral(_ s: String) -> String {
        // Prefer a literal single-quoted string; TOML literal strings have no escapes at all, so
        // fall back to a basic double-quoted string when the value contains a single quote.
        if !s.contains("'") { return "'\(s)'" }
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func quoted(_ s: String) -> String { escapedLiteral(s) }

    private static func isHeaderLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
    }

    /// Name of a single-bracket table header (`[gaps]` -> "gaps"). Returns nil for array-of-table
    /// headers (`[[...]]`) and non-header lines, so those are never matched or split.
    private static func sectionHeaderName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), t.hasSuffix("]"), !t.hasPrefix("[[") else { return nil }
        return String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func headerIndex(_ lines: [String], _ name: String) -> Int? {
        lines.firstIndex { sectionHeaderName($0) == name }
    }

    private static func lineKey(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("["), let eq = t.firstIndex(of: "=") else { return nil }
        var k = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
        if k.count >= 2, (k.hasPrefix("\"") && k.hasSuffix("\"")) || (k.hasPrefix("'") && k.hasSuffix("'")) {
            k = String(k.dropFirst().dropLast())
        }
        return k
    }

    /// Removes each matching single-bracket section: its header plus following lines up to (but not
    /// including) the next header line.
    private static func removeSections(_ lines: inout [String], where match: (String) -> Bool) {
        var result: [String] = []
        var i = 0
        while i < lines.count {
            if let name = sectionHeaderName(lines[i]), match(name) {
                i += 1
                var end = i
                while end < lines.count, !isHeaderLine(lines[end]) { end += 1 }
                // Trailing blank/comment lines immediately before the next header belong to THAT
                // header, not to the section being removed. Swallowing them deleted the user's
                // documentation for a section they never touched -- which broke the whole
                // "untouched sections are left alone" promise.
                var keepFrom = end
                while keepFrom > i {
                    let prev = lines[keepFrom - 1].trimmingCharacters(in: .whitespaces)
                    if prev.isEmpty || prev.hasPrefix("#") { keepFrom -= 1 } else { break }
                }
                result.append(contentsOf: lines[keepFrom ..< end])
                i = end
            } else {
                result.append(lines[i])
                i += 1
            }
        }
        lines = result
    }

    private static func insertAfterPreamble(_ lines: inout [String], _ block: [String]) {
        let idx = lines.firstIndex(where: isHeaderLine) ?? lines.count
        lines.insert(contentsOf: block, at: idx)
    }
}
