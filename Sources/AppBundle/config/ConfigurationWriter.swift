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
/// It edits the existing config text line-by-line and only rewrites the keys the user changed, so
/// comments, key order, and any sections the UI doesn't understand survive untouched. What it adds
/// is in the v2 spelling, and it only emits keys that the canonical `parseConfig` accepts.
@MainActor
enum ConfigurationWriter {
    private typealias Settings = ConfigurationViewModel.Settings

    struct ValidationDiagnostic: Equatable {
        let message: String
        let line: Int?
        let column: Int?
    }

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
        if existed { backUpOncePerSession(target) }
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

    private static let backupTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func timestamp(_ date: Date) -> String { backupTimestampFormatter.string(from: date) }

    private static var sessionHasBackup = false

    /// Called when Settings opens, and by a Raw TOML apply, which is a deliberate change of its own.
    ///
    /// Autosave writes every 600ms, so one backup per write turned five generations into the last few
    /// seconds of one slider drag, and the config from before Settings opened was gone by the time
    /// anyone wanted it.
    static func startBackupSession() { sessionHasBackup = false }

    static func backUpOncePerSession(_ target: URL, now: Date = Date()) {
        guard !sessionHasBackup else { return }
        sessionHasBackup = true
        backUp(target, now: now)
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
    /// This edits lines, and it cannot tell when the line it needed was not there. Callers check the
    /// result with `refusal` before writing it.
    static func render(baseText base: String, from vm: ConfigurationViewModel) -> String {
        // The raw TOML tab is authoritative only when Apply was actually pressed. Keying this off
        // `rawTomlEdited` meant an unapplied raw buffer hijacked unrelated structured edits.
        if vm.rawTomlApplyRequested { return vm.rawToml }
        guard vm.hasUnsavedChanges else { return base }

        // CRLF is not cosmetic here. Splitting on "\n" alone leaves a trailing "\r" on every line,
        // and `sectionHeaderName` requires a line to END with "]" -- so "[gaps]\r" was not
        // recognised as a section by the writer. The writer then appended a second [gaps] table and
        // produced a duplicate-key parse error. Found by the property fuzzer; it accounted for most
        // of its failures on its own.
        let usesCRLF = base.contains("\r\n")
        var lines = base.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Only rewrite the ones that actually changed -- rewriting in place would also normalize
        // quoting.
        for scalar in Settings.scalarKeys where scalar.literal(vm.settings) != scalar.literal(vm.loaded) {
            setKey(&lines, section: nil, key: scalar.key, value: scalar.literal(vm.settings))
        }

        let (now, before) = (vm.settings.asWritten, vm.loaded.asWritten)
        if vm.edited(\.gaps) { replaceGaps(&lines, vm) }
        if vm.edited(\.assignments) { applyAssignmentDiff(&lines, now.assignments, before.assignments) }
        if vm.edited(\.keyMappingPreset) {
            setKey(&lines, section: "key-mapping", key: "preset", value: escapedLiteral(now.keyMappingPreset))
        }
        if vm.edited(\.exec) { applyExecDiff(&lines, now.exec, before.exec) }
        if vm.edited(\.windowRules) { replaceWindowRules(&lines, vm) }
        // Guarded like every other section. It used to run on every save, so a binding the Raw TOML
        // tab had added was missing from the view model, read as deleted, and removed by the next
        // unrelated toggle.
        if vm.edited(\.modes) { applyBindingDiff(&lines, vm, now, before) }

        // Give the file back the line ending and the trailing newline it arrived with.
        //
        // Splitting on "\n" yields a final empty element for a file that ends with one, and the
        // emitted blocks were appended AFTER it -- so the newline turned into an interior blank line
        // and the file lost its terminator. Repeating that per save stacked a blank line each time:
        // measured 5, 6, 7, 8 lines over four saves of the same edit, which reads as a growing diff
        // in the user's dotfiles.
        //
        // Handled by `appendBlock`, which strips that artifact before appending and never doubles a
        // blank, rather than by collapsing blank runs globally: the fuzzer proved a global collapse
        // rewrites blank lines the user wrote themselves, which is precisely the do-no-harm
        // invariant this writer exists to keep.
        var result = lines.joined(separator: usesCRLF ? "\r\n" : "\n")
        if base.hasSuffix("\n"), !result.hasSuffix("\n") { result += usesCRLF ? "\r\n" : "\n" }
        return result
    }

    /// Why `rendered` must not be written, or nil. The proof behind "do no harm".
    ///
    /// Line surgery cannot tell when it has missed: a binding in an inline table or under a spaced
    /// header has no line to find, so the edit silently did nothing while the UI reported success. A
    /// list of spellings to refuse up front never kept up with that, and it locked whole files out
    /// over one odd line. So the result is read back instead: each section the user edited has to say
    /// what the panes say, and every other top-level key has to say what it said before. A spelling
    /// the writer can't edit is refused only when the edit actually touches it.
    static func refusal(rendered: String, base: String, from vm: ConfigurationViewModel) -> String? {
        if vm.hasUnsavedChanges, let shape = unsupportedShapeReason(base) { return shape }
        let cannotEdit = "This change can't be made to how the config file is written, so nothing was saved. Use the Raw TOML tab."
        let baseTable = try? TOMLTable(string: base)
        // Everything the writer emits is escaped, so a file that parsed before and doesn't now was
        // broken by the surgery, and the parser's complaint about a stray line would only confuse.
        guard let table = try? TOMLTable(string: rendered) else { return baseTable == nil ? validate(rendered) : cannotEdit }
        let parsed: Config
        switch parseConfig(rendered) {
            case .success(let config): parsed = config
            case .failure(let errors): return errors.map(\.description).joined(separator: "\n")
        }
        let want = vm.settings.asWritten
        if let row = firstDuplicate(want.assignments.map(\.workspace)) { return "Two rows pin workspace '\(row)'. Remove one, and this change will save." }
        if let row = firstDuplicate(want.exec.envVars.map(\.name)) { return "Two rows set '\(row)'. Remove one, and this change will save." }

        let now = Settings(config: parsed, table: table).asWritten
        var rewritten: Set<String> = []
        for scalar in Settings.scalarKeys where scalar.literal(vm.settings) != scalar.literal(vm.loaded) {
            rewritten.insert(scalar.key)
            if scalar.literal(now) != scalar.literal(want) { return cannotEdit }
        }
        func matches<T: Equatable>(_ section: KeyPath<Settings, T>, owning keys: String...) -> Bool {
            guard vm.edited(section) else { return true }
            rewritten.formUnion(keys)
            return now[keyPath: section] == want[keyPath: section]
        }
        // Rules waiting for a command were deliberately not written, so they still count as untouched.
        let rulesMatch = vm.settings.windowRules.contains(where: \.hasNoCommand) || matches(\.windowRules, owning: "on-window", "on-window-detected")
        guard rulesMatch,
              matches(\.gaps, owning: "gaps"),
              matches(\.assignments, owning: "monitors", "workspace-to-monitor-force-assignment"),
              matches(\.keyMappingPreset, owning: "key-mapping"),
              matches(\.exec, owning: "exec"),
              matches(\.modes, owning: "mode", "keys")
        else { return cannotEdit }

        // Compared on the parsed tables rather than through `Settings`, which can't see what the panes
        // don't model. No baseline to protect when the file on disk did not parse to begin with.
        guard let baseTable else { return nil }
        for key in Set(baseTable.keys + table.keys).subtracting(rewritten) where canonical(baseTable, key) != canonical(table, key) {
            return cannotEdit
        }
        return nil
    }

    private static func firstDuplicate(_ names: [String]) -> String? {
        var seen = Set<String>()
        return names.first { !seen.insert($0).inserted }
    }

    private static func canonical(_ table: TOMLTable, _ key: String) -> String {
        let one = TOMLTable()
        one[key] = table[key]
        return one.convert(to: .toml)
    }

    /// Validate before writing. A config that fails to parse used to land on disk anyway and only
    /// then pop a separate error dialog, leaving the user with a broken file and two error surfaces.
    static func validate(_ text: String) -> String? {
        switch parseConfig(text) {
            case .success: return nil
            case .failure(let errors): return errors.map(\.description).joined(separator: "\n")
        }
    }

    /// Validation shaped for an editor. TOMLKit already knows the exact source location for
    /// syntax errors; keep it structured instead of making the view scrape numbers back out of a
    /// localized error string. Semantic config errors still carry their key path in `message` and
    /// intentionally have no pretend source position.
    static func diagnostic(_ text: String) -> ValidationDiagnostic? {
        do {
            _ = try TOMLTable(string: text)
        } catch let error as TOMLParseError {
            return ValidationDiagnostic(
                message: error.debugDescription,
                line: error.source.begin.line,
                column: error.source.begin.column,
            )
        } catch {
            return ValidationDiagnostic(message: error.localizedDescription, line: nil, column: nil)
        }
        return validate(text).map { ValidationDiagnostic(message: $0, line: nil, column: nil) }
    }

    /// A file with both line endings can't be given back the way it arrived: `render` normalizes to
    /// one, which rewrites every line of every section. Nothing else is refused up front; see `refusal`.
    static func unsupportedShapeReason(_ text: String) -> String? {
        // Swift treats "\r\n" as ONE Character, so these only both hold for a bare "\n" beside a CRLF.
        guard text.contains("\r\n"), text.contains("\n") else { return nil }
        return "This config mixes Windows and Unix line endings, and editing it here would change every line. Use the Raw TOML tab."
    }

    // MARK: - Exec / assignments / window rules

    private static func applyExecDiff(_ lines: inout [String], _ now: Settings.Exec, _ before: Settings.Exec) {
        if now.inheritEnvVars != before.inheritEnvVars {
            setKey(&lines, section: "exec", key: "inherit-env-vars", value: now.inheritEnvVars ? "true" : "false")
        }
        for old in before.envVars where !now.envVars.contains(where: { $0.name == old.name }) {
            removeKey(&lines, section: "exec.env-vars", key: old.name)
        }
        for row in now.envVars where !before.envVars.contains(row) {
            setKey(&lines, section: "exec.env-vars", key: row.name, value: escapedLiteral(row.value))
        }
    }

    /// v2 spells this `[monitors]`, and a row's line can be under either name: the parser merges them
    /// into the one list the pane shows.
    private static func applyAssignmentDiff(_ lines: inout [String], _ now: [ConfigurationViewModel.WorkspaceAssignmentRow], _ before: [ConfigurationViewModel.WorkspaceAssignmentRow]) {
        let spellings = ["monitors", "workspace-to-monitor-force-assignment"]
        for old in before where !now.contains(where: { $0.workspace == old.workspace }) {
            for section in spellings { removeKey(&lines, section: section, key: old.workspace) }
        }
        for row in now where !before.contains(row) {
            setKey(&lines, section: section(for: row.workspace, among: spellings, in: lines), key: row.workspace, value: formatMonitorValue(row.monitor))
        }
    }

    private static func formatMonitorValue(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespaces)
        if UUID(uuidString: t) != nil { return "{ fingerprint = { uuid = '\(t)' } }" }
        if Int(t) != nil { return t }
        if t == "main" || t == "secondary" { return escapedLiteral(t) }
        // A bare string is parsed as a *regex*, so a literal display name containing regex
        // metacharacters never matches -- and macOS names duplicate panels exactly that way,
        // e.g. "ACME Display 32 (1)". Emit a name fingerprint instead of a booby-trapped pattern.
        return "{ fingerprint = { name = \(escapedLiteral(t)) } }"
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

    /// Rules go in the shorthand when EVERY rule fits it and no app id repeats, and long form otherwise.
    ///
    /// All-or-nothing on purpose. `parseConfigV2` appends `[on-window]` *after*
    /// `on-window-detected`, so in a mixed file the long-form rules always get first refusal
    /// regardless of where they sit in the text -- a list the user had ordered in the GUI would
    /// not run in that order. With no long-form rules there is nothing to take precedence, and
    /// app ids are unique, so order genuinely cannot matter.
    private static func fitShorthand(_ rules: [ConfigurationViewModel.WindowRuleRow]) -> Bool {
        let appIds = rules.map(\.appId)
        return !rules.isEmpty && rules.allSatisfy(isShorthandExpressible) && Set(appIds).count == appIds.count
    }

    static func ruleOrderAsWritten(_ rules: [ConfigurationViewModel.WindowRuleRow]) -> [ConfigurationViewModel.WindowRuleRow] {
        fitShorthand(rules) ? rules.sorted { $0.appId < $1.appId } : rules
    }

    private static func replaceWindowRules(_ lines: inout [String], _ vm: ConfigurationViewModel) {
        // A rule with no command yet cannot be written -- `run` is required by the parser. Leave the
        // whole section alone rather than writing the rest, because the alternative is silent
        // deletion: clearing the Command field to retype it made that rule disappear from disk on
        // the next 600ms autosave while the row stayed on screen, and every keystroke of the
        // replacement failed validation and wrote nothing. An interrupted edit lost the rule with no
        // indication. The same guard covers a value the GUI cannot read at all (`app = 42` loads as
        // an empty command), which would otherwise be quietly dropped from the user's file.
        //
        // Nothing is lost by waiting: the rules on disk keep working, and `didWrite` keeps the edit
        // pending, so it lands as soon as the command is complete.
        let rules = vm.settings.windowRules
        guard !rules.contains(where: \.hasNoCommand) else { return }

        // The shorthand table too. Removing only the long form left a v2 user's `[on-window]` rules
        // in the file alongside the long-form copy this writes, so every one of them applied twice.
        // And `[on-window-detected.if]`, the sub-table spelling of a matcher, which a removal up to
        // the next header would leave behind to clash with whatever is written next.
        removeBlocks(&lines) { $0 == "on-window" || $0 == "on-window-detected" || $0.hasPrefix("on-window-detected.") }

        if fitShorthand(rules) {
            var block = ["", "[on-window]"]
            for rule in ruleOrderAsWritten(rules) {
                block.append("\(escapedLiteral(rule.appId)) = \(tomlArray(splitCommands(rule.run)))")
            }
            appendBlock(&lines, block)
            return
        }

        for rule in rules {
            var block = ["", "[[on-window-detected]]"]
            if !rule.appId.isEmpty { block.append("if.app-id = \(escapedLiteral(rule.appId))") }
            if !rule.appNameRegex.isEmpty { block.append("if.app-name-regex-substring = \(escapedLiteral(rule.appNameRegex))") }
            if !rule.windowTitleRegex.isEmpty { block.append("if.window-title-regex-substring = \(escapedLiteral(rule.windowTitleRegex))") }
            if !rule.workspace.isEmpty { block.append("if.workspace = \(escapedLiteral(rule.workspace))") }
            // The upstream-branded spelling of this key is no longer parsed at all, so any rule the
            // GUI round-trips is written under the only name that loads.
            if let during = rule.duringStartup { block.append("if.during-aerospork-startup = \(during)") }
            if rule.checkFurtherCallbacks { block.append("check-further-callbacks = true") }
            block.append("run = \(tomlArray(splitCommands(rule.run)))")
            appendBlock(&lines, block)
        }
    }

    /// Appends an emitted block, keeping exactly one blank line before it.
    ///
    /// Two things go wrong with a bare `append(contentsOf:)`. A file ending in a newline splits to a
    /// final empty element, and appending after it turns the terminator into an interior blank line;
    /// and every block opens with its own blank while the removal walk-back keeps the one the
    /// previous save left, so the gap grew by a line on every save.
    private static func appendBlock(_ lines: inout [String], _ block: [String]) {
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        lines.append(contentsOf: lines.isEmpty ? Array(block.drop(while: { $0.isEmpty })) : block)
    }

    /// Name of an array-of-table header (`[[on-window-detected]]` -> "on-window-detected"), nil for
    /// anything else.
    ///
    /// Parsed rather than string-compared. `[[ on-window-detected ]]` is legal TOML and TOMLKit
    /// reads it, so an exact match against `"[[name]]"` left the block in the file while the writer
    /// appended a fresh one -- two copies of the rule, and since the shorthand is parsed last, the
    /// *stale* one won. The user's edit did nothing and their config grew on every save.
    private static func arrayOfTablesHeaderName(_ line: String) -> String? {
        let t = stripTrailingComment(line)
        guard t.hasPrefix("[["), t.hasSuffix("]]") else { return nil }
        let inner = String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
        // `[["on-window-detected"]]` is the same table as the bare spelling.
        if inner.count >= 2, inner.hasPrefix("\""), inner.hasSuffix("\"") {
            return String(inner.dropFirst().dropLast())
        }
        return inner
    }

    static func splitCommands(_ s: String) -> [String] {
        s.components(separatedBy: ConfigurationViewModel.commandSeparator)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func tomlArray(_ items: [String]) -> String {
        "[" + items.map { escapedLiteral($0) }.joined(separator: ", ") + "]"
    }

    // MARK: - Per-key edits

    /// The lines of `[section]`, or of the preamble above the first header when `section` is nil. Nil
    /// when the file has no such section.
    private static func body(_ lines: [String], _ section: String?) -> Range<Int>? {
        var start = 0
        if let section {
            guard let header = headerIndex(lines, section) else { return nil }
            start = header + 1
        }
        return start ..< (lines[start...].firstIndex(where: isHeaderLine) ?? lines.count)
    }

    private static func keyLine(_ lines: [String], _ section: String?, _ key: String) -> Int? {
        body(lines, section)?.first { lineKey(lines[$0]) == key }
    }

    /// Updates `key` where it stands, or adds it. Every other line of the section stays as it is, which
    /// a rewrite of the whole section could not do: it re-spelled sibling rows, dropped comments and
    /// moved the section.
    private static func setKey(_ lines: inout [String], section: String?, key: String, value: String) {
        let spelled = "\(tomlKey(key)) = \(value)"
        if let i = keyLine(lines, section, key) {
            let indent = lines[i].prefix { $0 == " " || $0 == "\t" }
            let comment = lines[i].dropFirst(indent.count + stripTrailingComment(lines[i]).count)
            lines[i] = "\(indent)\(spelled)\(comment)"
        } else if let body = body(lines, section) {
            // After the last key. Blank and comment lines before the next header document THAT header.
            var at = body.upperBound
            while at > body.lowerBound, isBlankOrComment(lines[at - 1]) { at -= 1 }
            // A section with no keys yet keeps what opens it above the new line, like a file's banner.
            if at == body.lowerBound {
                while at < body.upperBound, lines[at].trimmingCharacters(in: .whitespaces).hasPrefix("#") { at += 1 }
            }
            lines.insert(spelled, at: at)
        } else if let section {
            appendBlock(&lines, ["", "[\(section)]", spelled])
        }
    }

    private static func removeKey(_ lines: inout [String], section: String, key: String) {
        if let i = keyLine(lines, section, key) { lines.remove(at: i) }
    }

    /// Which of a table's spellings, v2 first, `key` belongs in: where its line already is, else a
    /// section the file already has, else the v2 spelling, which `setKey` creates.
    private static func section(for key: String, among spellings: [String], in lines: [String]) -> String {
        spellings.last { keyLine(lines, $0, key) != nil } ?? spellings.first { headerIndex(lines, $0) != nil } ?? spellings[0]
    }

    // MARK: - Gaps

    /// Whole-section, in place: a value the pane can't show (a per-monitor list) has no single row to
    /// edit, so this one is rewritten, and the footer in the pane says so.
    ///
    /// Internal, not private, so ConfigTest can round-trip it without touching the real config file.
    static func replaceGaps(_ lines: inout [String], _ vm: ConfigurationViewModel) {
        let isGaps = { (name: String) in name == "gaps" || name.hasPrefix("gaps.") }
        let at = lines.firstIndex { sectionHeaderName($0).map(isGaps) ?? false }
        removeBlocks(&lines, where: isGaps)
        let gaps = vm.settings.gaps
        let block = [
            "[gaps]",
            "inner.horizontal = \(gaps.innerHorizontal)",
            "inner.vertical = \(gaps.innerVertical)",
            "outer.top = \(gaps.outerTop)",
            "outer.bottom = \(gaps.outerBottom)",
            "outer.left = \(gaps.outerLeft)",
            "outer.right = \(gaps.outerRight)",
        ]
        if let at {
            lines.insert(contentsOf: block, at: at)
        } else {
            appendBlock(&lines, [""] + block)
        }
    }

    /// A bare TOML key may only contain A-Za-z0-9_- ; anything else must be quoted or the file
    /// fails to parse (an env var named `MY VAR`, a workspace named `my workspace`).
    private static func tomlKey(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        let bare = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        if !t.isEmpty, t.unicodeScalars.allSatisfy({ bare.contains($0) }) { return t }
        return escapedLiteral(t)
    }

    // MARK: - Key bindings

    /// Where a mode's bindings can live: `[keys]` / `[keys.<name>]`, the v2 spelling and the one a new
    /// section is written in, or `[mode.<name>.binding]`, which still parses and overrides it.
    private static func bindingSections(mode: String) -> [String] {
        [mode == mainModeId ? "keys" : "keys.\(tomlKey(mode))", "mode.\(tomlKey(mode)).binding"]
    }

    private static func applyBindingDiff(_ lines: inout [String], _ vm: ConfigurationViewModel, _ now: Settings, _ before: Settings) {
        // A mode the user deleted.
        let modes = vm.settings.modes.map(\.mode)
        let deleted = Set(vm.loaded.modes.map(\.mode)).subtracting(modes)
        if !deleted.isEmpty {
            removeBlocks(&lines) { name in
                deleted.contains { name == "mode.\($0)" || name.hasPrefix("mode.\($0).") || name == "keys.\($0)" }
            }
        }
        for mode in modes {
            let sections = bindingSections(mode: mode)
            let new = now.modes.first { $0.mode == mode }?.bindings ?? []
            let old = before.modes.first { $0.mode == mode }?.bindings ?? []
            for row in old where !new.contains(where: { $0.key == row.key }) {
                // From both: a `[keys]` line under a `[mode.*]` one would otherwise take over.
                for section in sections { removeKey(&lines, section: section, key: row.key) }
            }
            // Only what changed: `formatCommand` normalizes quoting, so rewriting an untouched line
            // would turn `key = "cmd"` into `key = 'cmd'`.
            for row in new where !old.contains(row) {
                setKey(&lines, section: section(for: row.key, among: sections, in: lines), key: row.key, value: formatCommand(row.command))
            }
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

    /// Quote a TOML string, *escaping* rather than deleting. The previous implementation stripped
    /// quote characters out of the value, which silently changed the user's data (a command
    /// containing an apostrophe came back different).
    static func escapedLiteral(_ s: String) -> String {
        // Prefer a literal single-quoted string; TOML literal strings have no escapes at all, so
        // fall back to a basic double-quoted string when the value contains a single quote.
        if !s.contains("'") { return "'\(s)'" }
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    private static func isHeaderLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
    }

    private static func isBlankOrComment(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasPrefix("#")
    }

    /// Name of a single-bracket table header (`[gaps]` -> "gaps"). Returns nil for array-of-table
    /// headers (`[[...]]`) and non-header lines, so those are never matched or split.
    /// A header may carry a trailing comment -- `[gaps] # tuned for the 32"` is legal TOML and
    /// TOMLKit reads it. Matching on `hasSuffix("]")` missed those, so the section was never removed
    /// and the writer appended a second copy beside it. For `[on-window]` that means every rule in
    /// the table applies twice, which is the exact bug an earlier commit set out to fix.
    private static func stripTrailingComment(_ line: String) -> String {
        var result = ""
        var quote: Character? = nil
        for character in line {
            if let open = quote {
                result.append(character)
                if character == open { quote = nil }
                continue
            }
            if character == "#" { break }
            if character == "\"" || character == "'" { quote = character }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func sectionHeaderName(_ line: String) -> String? {
        let t = stripTrailingComment(line)
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

    /// Removes each block whose header name matches, `[x]` or `[[x]]`: the header plus the lines up to
    /// (but not including) the next header.
    private static func removeBlocks(_ lines: inout [String], where match: (String) -> Bool) {
        var result: [String] = []
        var i = 0
        while i < lines.count {
            if let name = sectionHeaderName(lines[i]) ?? arrayOfTablesHeaderName(lines[i]), match(name) {
                i += 1
                var end = i
                while end < lines.count, !isHeaderLine(lines[end]) { end += 1 }
                // Trailing blank/comment lines immediately before the next header belong to THAT
                // header, not to the section being removed. Swallowing them deleted the user's
                // documentation for a section they never touched -- which broke the whole
                // "untouched sections are left alone" promise.
                var keepFrom = end
                while keepFrom > i, isBlankOrComment(lines[keepFrom - 1]) { keepFrom -= 1 }
                result.append(contentsOf: lines[keepFrom ..< end])
                i = end
            } else {
                result.append(lines[i])
                i += 1
            }
        }
        lines = result
    }
}
