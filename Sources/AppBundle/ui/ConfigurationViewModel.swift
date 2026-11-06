import AppKit
import Common
import SwiftUI
import TOMLKit

/// Backs the settings window. The panes edit `settings`; on save `ConfigurationWriter` turns the
/// difference from `loaded` into line edits on the file, then the config reloads.
@MainActor
final class ConfigurationViewModel: ObservableObject {
    /// DisplayLink docks connect in stages, and Settings can be open while they do. Without this
    /// the schematic, the pin menu's token, and every chip resolve against the monitor list from
    /// the last config reload. Refreshes only `liveMonitors` — no edit state, so no writer risk.
    /// Never removed, like `externalReloadObserver`: the view model lives as long as the app.
    private var screenObserver: NSObjectProtocol?

    init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in self?.liveMonitors = self?.loadMonitors() ?? [] }
        }
    }

    /// What the panes edit. Everything a save can write lives here.
    @Published var settings = Settings()

    /// Snapshot of what was loaded, so the writer can tell a real edit from an untouched section.
    /// `settings` is a lossy projection of the config (per-monitor gaps collapse to their default,
    /// fingerprints to a string, monitor fallback lists to `.first`), so re-serializing an untouched
    /// section silently destroys whatever the UI couldn't represent.
    private(set) var loaded = Settings()

    func edited<T: Equatable>(_ section: KeyPath<Settings, T>) -> Bool {
        settings[keyPath: section] != loaded[keyPath: section]
    }

    var hasUnsavedChanges: Bool { settings != loaded }

    /// What the two visibility toggles will actually produce, including the forced Dock icon. The
    /// General tab shows the rule rather than letting the user find out after they close Settings.
    var appVisibility: AppVisibility {
        AppVisibility(showMenuBarIcon: settings.general.showMenuBarIcon, showDockIcon: settings.general.showDockIcon)
    }

    @Published private(set) var gapsHavePerMonitorOverrides = false

    /// Bindings that are active but have no line in the file: the ~78 that `mod` + `workspaces`
    /// generate out of thin air.
    ///
    /// They are kept OUT of `settings.modes` on purpose. Putting them there would make the very next
    /// save write all of them back as lines -- re-materializing exactly the boilerplate config v2
    /// exists to delete. The tab still shows them, because a Keys tab that hides 78 live bindings is
    /// lying about what the keyboard does.
    @Published private(set) var inheritedBindings: [InheritedBinding] = []

    /// Every workspace name `workspaces` defines, ranges expanded, in config order.
    @Published var definedWorkspaces: [String] = []
    @Published var liveMonitors: [MonitorRow] = []

    // Raw TOML editor -- the guarantee that nothing in the config is unreachable from the GUI.
    @Published var rawToml = ""
    private var loadedRawToml = ""
    var rawTomlEdited: Bool { rawToml != loadedRawToml }

    /// Set ONLY by the Raw TOML pane's Apply button.
    ///
    /// `rawTomlEdited` must never authorize a write on its own: an unapplied raw buffer used to
    /// hijack unrelated structured edits, so flipping a toggle on another pane would commit the
    /// half-finished raw text and silently discard the toggle.
    @Published var rawTomlApplyRequested = false

    @Published var errorMessage: String?
    private var isSaving = false
    /// Changes only after a complete reload. Views with non-persisted presentation state use this
    /// to seed themselves once without recomputing while the user is typing.
    @Published private(set) var loadGeneration = 0

    struct ModeBindings: Identifiable, Equatable {
        let id = UUID()
        var mode: String
        var bindings: [BindingRow]
        static func == (a: ModeBindings, b: ModeBindings) -> Bool { a.mode == b.mode && a.bindings == b.bindings }
    }

    struct BindingRow: Identifiable, Equatable {
        let id = UUID()
        var key: String
        var command: String
        static func == (a: BindingRow, b: BindingRow) -> Bool { a.key == b.key && a.command == b.command }
    }

    /// Where a displayed binding comes from, ordered by the layering `parseConfigV2` applies:
    /// generated -> `[keys]` -> `[mode.*]`, later wins. Encoding it as the raw value means the
    /// tab's dedupe and the parser's precedence cannot drift apart.
    enum BindingOrigin: Int, Comparable {
        case generated = 0
        /// Anything with a line in the file, `[keys]` or `[mode.*.binding]`. Both are editable in
        /// place and the writer rewrites whichever section the key came from, so the tab has no
        /// reason to distinguish them. Only `generated` -- which has no line anywhere -- is special.
        case explicit = 2

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// A binding the UI shows but does not own. Read-only until the user overrides it.
    struct InheritedBinding: Identifiable {
        let id = UUID()
        var mode: String
        var key: String
        var command: String
        var origin: BindingOrigin
    }

    /// One row of the Keys table: the *effective* binding for a key, plus where it came from.
    /// `rowId` is non-nil exactly when the row is editable, i.e. when it is backed by `settings.modes`.
    struct DisplayBinding: Identifiable {
        var key: String
        var command: String
        var origin: BindingOrigin
        var rowId: BindingRow.ID?
        var id: String { key }
    }

    struct WorkspaceAssignmentRow: Identifiable, Equatable {
        let id = UUID()
        var workspace: String
        var monitor: String
        var isComplex = false
        static func == (a: WorkspaceAssignmentRow, b: WorkspaceAssignmentRow) -> Bool {
            a.workspace == b.workspace && a.monitor == b.monitor
        }
    }

    struct MonitorRow: Identifiable {
        let id = UUID()
        var name: String
        var resolution: String
        var uuid: String?
        var position = 1
        var isMain = false
        var rect = CGRect.zero
    }

    struct CommandRow: Identifiable, Equatable {
        let id = UUID()
        var command: String
        static func == (a: CommandRow, b: CommandRow) -> Bool { a.command == b.command }
    }

    struct EnvVarRow: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var value: String
        static func == (a: EnvVarRow, b: EnvVarRow) -> Bool { a.name == b.name && a.value == b.value }
    }

    /// One `[[on-window-detected]]` entry. `if` matchers on the left, `run` commands on the right.
    struct WindowRuleRow: Identifiable, Equatable {
        let id = UUID()
        var appId = ""
        var appNameRegex = ""
        var windowTitleRegex = ""
        var workspace = ""
        var run = ""
        var checkFurtherCallbacks = false
        /// Modelled even though the UI has no control for it: without this field, loading and
        /// re-emitting a rule silently dropped the matcher, turning a startup-only rule into one
        /// that fires for every window forever.
        var duringStartup: Bool?

        var hasNoCommand: Bool { run.trimmingCharacters(in: .whitespaces).isEmpty }

        static func == (a: WindowRuleRow, b: WindowRuleRow) -> Bool {
            a.appId == b.appId && a.appNameRegex == b.appNameRegex &&
                a.windowTitleRegex == b.windowTitleRegex && a.workspace == b.workspace &&
                a.run == b.run && a.checkFurtherCallbacks == b.checkFurtherCallbacks &&
                a.duringStartup == b.duringStartup
        }
    }

    // MARK: - Loading

    private var externalReloadObserver: NSObjectProtocol?

    func loadConfiguration() async {
        ConfigurationWriter.startBackupSession()
        reloadFromConfig()
        guard externalReloadObserver == nil else { return }
        // Someone edited the config in an editor while this window is open. Our `loaded` snapshot is
        // now stale, and editing any section would write that stale text back over their change.
        externalReloadObserver = NotificationCenter.default.addObserver(
            forName: .aerosporkConfigReloadedExternally,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.hasUnsavedChanges || self.rawTomlEdited {
                    // Don't clobber what the user is in the middle of typing -- tell them instead.
                    self.errorMessage = "The config file changed on disk. Revert to load it, or apply your changes to overwrite it."
                } else {
                    self.reloadFromConfig()
                }
            }
        }
    }

    func revertChanges() {
        reloadFromConfig()
    }

    /// Binding for a structured control. macOS settings apply live rather than behind a Save
    /// button, so every edit schedules a debounced write. The debounce matters because a save
    /// reloads the whole config and triggers a refresh -- doing that per keystroke would thrash.
    /// The raw TOML tab deliberately does NOT use this; hand-edited text applies explicitly.
    func binding<T>(_ keyPath: ReferenceWritableKeyPath<ConfigurationViewModel, T>) -> Binding<T> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { newValue in
                self[keyPath: keyPath] = newValue
                self.scheduleAutoSave()
            },
        )
    }

    private var autoSaveTask: Task<Void, Never>?

    /// Drops a pending autosave without writing it.
    func cancelPendingAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
    }

    /// Called when the settings window goes away: a pending edit is written now, not dropped.
    ///
    /// It used to be cancelled, so a change made less than 600ms before closing the window was
    /// discarded without a word -- the toggle had moved, the file had not. The save runs the same guards
    /// as any other, and with the window gone a refusal has nowhere to be shown, so it is logged.
    func flushPendingAutoSave() async {
        guard autoSaveTask != nil else { return }
        cancelPendingAutoSave()
        await saveConfiguration()
        if let errorMessage {
            AppLog.config.notice("Settings closed with an edit that could not be saved: \(errorMessage, privacy: .public)")
        }
    }

    func scheduleAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await saveConfiguration()
        }
    }

    private func reloadFromConfig() {
        liveMonitors = loadMonitors()
        adopt(configBaseText(), config)
    }

    /// Load from config text instead of the real config file. A Raw TOML apply goes through here,
    /// because what it wrote is what every other pane has to show now, and so does the test suite,
    /// which must not depend on `~/.aerospork.toml`.
    func load(fromText text: String) {
        if case .success(let parsed) = parseConfig(text) { adopt(text, parsed) } else { adopt(text, Config()) }
    }

    private func adopt(_ text: String, _ config: Config) {
        errorMessage = nil
        let table = try? TOMLTable(string: text)
        settings = Settings(config: config, table: table)
        gapsHavePerMonitorOverrides = [
            config.gaps.inner.horizontal,
            config.gaps.inner.vertical,
            config.gaps.outer.top,
            config.gaps.outer.bottom,
            config.gaps.outer.left,
            config.gaps.outer.right,
        ].contains { value in
            if case .perMonitor = value { true } else { false }
        }
        rawToml = text
        // Both spellings declare workspaces the runtime keeps alive; see `Config.persistentWorkspaces`.
        definedWorkspaces = workspaceNames(table, "workspaces") + workspaceNames(table, "persistent-workspaces")
        inheritedBindings = loadInheritedBindings(table)
        markLoaded()
        loadGeneration &+= 1
    }

    /// Record the current field values as the "loaded" baseline that edit detection compares
    /// against. Called at the end of a load; also used by tests that build a view model directly.
    func markLoaded() {
        loaded = settings
        loadedRawToml = rawToml
    }

    private func loadMonitors() -> [MonitorRow] {
        sortedMonitors.enumerated().map { offset, monitor in
            // `fingerprint` is part of the protocol. Downcasting discarded fingerprints from test
            // and alternate monitor implementations and also performed a needless runtime cast per
            // display whenever Settings reloaded.
            let fingerprint = monitor.fingerprint
            let width = fingerprint?.widthPixels ?? Int(monitor.width)
            let height = fingerprint?.heightPixels ?? Int(monitor.height)
            return MonitorRow(
                name: monitor.name,
                resolution: "\(width)×\(height)",
                uuid: fingerprint?.displayUUID,
                position: offset + 1,
                isMain: monitor.rect.topLeftCorner == .zero,
                rect: CGRect(x: monitor.rect.minX, y: monitor.rect.minY, width: monitor.rect.width, height: monitor.rect.height),
            )
        }
    }

    /// Everything bound that the writer does NOT manage: the bindings `mod` + `workspaces` generate,
    /// which exist nowhere in the file and so have no lines to round-trip against. Empty for a v1
    /// config. (`[keys]` used to be listed here too, back when the writer only understood
    /// `[mode.*.binding]`; it is editable in place now and belongs to `loadBindings`.)
    private func loadInheritedBindings(_ table: TOMLTable?) -> [InheritedBinding] {
        guard let table, isConfigV2(table), let mod = table["mod"]?.string else { return [] }
        // Same function the parser and the migration collapser use, so the tab cannot show a set of
        // generated bindings that differs from the set actually registered.
        return generatedBindingsV2(mod: mod, workspaces: workspaceNames(table, "workspaces"))
            .map { InheritedBinding(mode: mainModeId, key: $0.notation, command: $0.command, origin: .generated) }
    }

    /// The parser's own reading, so the tab and the keyboard cannot disagree about which workspace keys
    /// exist. Its errors were already reported when the config loaded.
    private func workspaceNames(_ table: TOMLTable?, _ key: String) -> [String] {
        var ignored: [TomlParseError] = []
        return table?[key].map { parseWorkspaceNames($0, .rootKey(key), &ignored) } ?? []
    }

    /// A binding value is either a single command string or an array of them. Multi-command
    /// bindings are joined with " ; " -- NOT ", " -- because the writer splits on the same
    /// separator to re-emit a TOML array. Joining with ", " used to produce `key = 'a, b'`, a
    /// single bogus command, whenever such a row was re-added.
    static let commandSeparator = " ; "

    static func commandString(_ value: TOMLValueConvertible) -> String {
        if let string = value.string { return string }
        if let array = value.array { return array.compactMap { $0.string }.joined(separator: Self.commandSeparator) }
        return ""
    }

    // MARK: - Displaying

    /// Every mode that has bindings from any source, `main` first. The picker cannot read
    /// `settings.modes` alone: a v2 config's `main` can exist purely as generated bindings.
    var allModeNames: [String] {
        Set(settings.modes.map(\.mode)).union(inheritedBindings.map(\.mode))
            .sorted { ($0 == mainModeId ? 0 : 1, $0) < ($1 == mainModeId ? 0 : 1, $1) }
    }

    /// The rows the Keys tab shows for `mode`: one per key, strongest source winning, exactly as
    /// `parseConfigV2` layers them. Deduplicating here is what stops a key that `[keys]` overrides
    /// from appearing twice with two different commands.
    func displayBindings(mode: String) -> [DisplayBinding] {
        var byKey: [String: DisplayBinding] = [:]
        for b in inheritedBindings.filter({ $0.mode == mode }).sorted(by: { $0.origin < $1.origin }) {
            byKey[b.key] = DisplayBinding(key: b.key, command: b.command, origin: b.origin, rowId: nil)
        }
        for row in settings.modes.first(where: { $0.mode == mode })?.bindings ?? [] {
            byKey[row.key] = DisplayBinding(key: row.key, command: row.command, origin: .explicit, rowId: row.id)
        }
        return byKey.values.sorted { $0.key < $1.key }
    }

    // MARK: - Editing

    /// The binding `key` already has in `mode`, or nil. `ignoring` is the row currently being
    /// edited, so a row never reports a conflict with itself.
    ///
    /// Reads the *effective* list, so it also catches the ~78 generated bindings -- which is the
    /// case that actually bites: recording ⌥1 for something new looks free, because nothing in the
    /// config file mentions it, and silently shadows "workspace 1".
    func existingBinding(mode: String, key: String, ignoring: BindingRow.ID? = nil) -> DisplayBinding? {
        let key = key.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        // `ignoring == nil ||` is load-bearing: without it the predicate reads `rowId != nil`, which
        // silently excludes every generated binding -- the exact set this exists to find.
        return displayBindings(mode: mode).first { $0.key == key && (ignoring == nil || $0.rowId != ignoring) }
    }

    /// Edit a row in place. Add/remove was the only way to change a binding, which gave the row a
    /// new identity on every change -- so the selection and any in-flight text field were yanked
    /// out from under the user mid-edit, and a rename lost the row's position in the table.
    ///
    /// Deliberately does NOT re-sort: `displayBindings` sorts for display, and re-sorting the
    /// backing array on each keystroke would make the row being typed into jump away.
    ///
    /// Returns false when the edit was refused, so the tab can say why instead of looking dead.
    @discardableResult
    func updateBinding(mode: String, id: BindingRow.ID, key: String? = nil, command: String? = nil) -> Bool {
        guard let m = settings.modes.firstIndex(where: { $0.mode == mode }),
              let r = settings.modes[m].bindings.firstIndex(where: { $0.id == id }) else { return false }
        if let key {
            let key = key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return false }
            // Two writable rows with the same key in one mode is not a cosmetic problem: the writer
            // emits a line for each, and duplicate keys in one TOML table do not parse -- so the
            // save that follows would leave the user with a config the app refuses to load. The
            // table would show only one of them too, making the other invisible as well as fatal.
            guard !settings.modes[m].bindings.contains(where: { $0.id != id && $0.key == key }) else { return false }
            settings.modes[m].bindings[r].key = key
        }
        if let command { settings.modes[m].bindings[r].command = command }
        return true
    }

    /// Returns false when there was nothing to add, so the caller can keep what the user typed.
    ///
    /// This used to return silently when `modes` was empty -- a config with no `[mode.*]` section is
    /// perfectly valid -- while the tab cleared the fields anyway, so the binding just vanished.
    @discardableResult
    func addBinding(mode: String, key: String, command: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespaces)
        let command = command.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !command.isEmpty else { return false }
        let i = settings.modes.firstIndex { $0.mode == mode } ?? { addMode(mode); return settings.modes.count - 1 }()
        settings.modes[i].bindings.removeAll { $0.key == key }
        settings.modes[i].bindings.append(BindingRow(key: key, command: command))
        settings.modes[i].bindings.sort { $0.key < $1.key }
        return true
    }

    func removeBinding(mode: String, id: BindingRow.ID) {
        guard let i = settings.modes.firstIndex(where: { $0.mode == mode }) else { return }
        settings.modes[i].bindings.removeAll { $0.id == id }
    }

    /// Returns false if the name is empty or already taken.
    @discardableResult
    func addMode(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !settings.modes.contains(where: { $0.mode == name }) else { return false }
        settings.modes.append(ModeBindings(mode: name, bindings: []))
        return true
    }

    /// `main` is the mode the app starts in; deleting it would leave nothing to fall back to.
    func canRemoveMode(_ name: String) -> Bool { name != mainModeId && settings.modes.contains { $0.mode == name } }

    func removeMode(_ name: String) {
        guard canRemoveMode(name) else { return }
        settings.modes.removeAll { $0.mode == name }
    }

    // MARK: - Backups

    /// Timestamped copies the writer keeps before each save, newest first.
    func configBackups() -> [URL] { ConfigurationWriter.backupsOfUserConfig() }

    /// Loads a backup into the raw TOML editor rather than writing it straight to disk: the user
    /// sees what they are about to restore, and Apply is the one path that validates and (itself)
    /// backs up the current file first -- so restoring is undoable too.
    func loadBackup(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "Could not read \(url.lastPathComponent)"
            return
        }
        rawToml = text
    }

    /// Deliberately no autosave: an empty workspace name must not hit disk until typed.
    @discardableResult
    func addAssignment(monitorToken: String = "main") -> WorkspaceAssignmentRow.ID {
        let row = WorkspaceAssignmentRow(workspace: "", monitor: monitorToken)
        settings.assignments.append(row)
        return row.id
    }

    func removeAssignment(id: WorkspaceAssignmentRow.ID) {
        settings.assignments.removeAll { $0.id == id }
    }

    /// Pin `workspace` to `monitorToken`, updating the existing assignment if there is one.
    /// Returns the affected row's id so the pane can surface it in the table.
    @discardableResult
    func setAssignment(workspace: String, monitorToken: String) -> WorkspaceAssignmentRow.ID {
        if let i = settings.assignments.firstIndex(where: { $0.workspace == workspace }) {
            guard settings.assignments[i].monitor != monitorToken else { return settings.assignments[i].id }
            settings.assignments[i].monitor = monitorToken
            scheduleAutoSave()
            return settings.assignments[i].id
        }
        let row = WorkspaceAssignmentRow(workspace: workspace, monitor: monitorToken)
        settings.assignments.append(row)
        scheduleAutoSave()
        return row.id
    }

    /// Defined workspaces with no force-assignment — the pin menu's contents. Config order, deduped.
    var unpinnedDefinedWorkspaces: [String] {
        var seen = Set<String>()
        let assigned = Set(settings.assignments.map(\.workspace))
        return definedWorkspaces.filter { seen.insert($0).inserted && !assigned.contains($0) }
    }

    /// Resolves an assignment token to a connected monitor for the detail strip's chips. Mirrors
    /// the runtime's reading (`parseMonitorDescription` precedence, then resolution): a name is
    /// matched exact-or-contains because at runtime both a bare pattern and a fingerprint name
    /// are case-insensitive substring matches — exact equality would show "no workspaces pinned
    /// here" for `monitor = 'dell'` on a DELL panel the runtime happily resolves.
    /// A metacharacter regex or rich fingerprint resolves to nil; the `complex` badge owns those.
    func monitorRow(forToken token: String) -> MonitorRow? {
        if let n = Int(token) { return liveMonitors.first { $0.position == n } }
        // Runtime falls back to the first monitor when none reports a zero origin (mirrored and
        // transient arrangements) -- mirror that or the "main" chip vanishes in states the
        // runtime handles.
        if token == "main" { return liveMonitors.first(where: \.isMain) ?? liveMonitors.first }
        if token == "secondary" {
            return liveMonitors.count == 2 ? liveMonitors.first { !$0.isMain } : nil
        }
        if let exact = liveMonitors.first(where: { $0.uuid == token }) { return exact }
        return liveMonitors.first {
            $0.name == token || $0.name.localizedCaseInsensitiveContains(token)
        }
    }

    /// The detail strip's chips: every assignment whose token resolves to this monitor.
    func assignments(pinnedTo row: MonitorRow) -> [WorkspaceAssignmentRow] {
        settings.assignments.filter { monitorRow(forToken: $0.monitor)?.id == row.id }
    }

    func setInnerGaps(_ value: Int) {
        guard settings.gaps.innerHorizontal != value || settings.gaps.innerVertical != value else { return }
        settings.gaps.innerHorizontal = value
        settings.gaps.innerVertical = value
        scheduleAutoSave()
    }

    func setOuterGaps(_ value: Int) {
        let gaps = settings.gaps
        guard gaps.outerTop != value || gaps.outerBottom != value || gaps.outerLeft != value || gaps.outerRight != value else {
            return
        }
        settings.gaps.outerTop = value
        settings.gaps.outerBottom = value
        settings.gaps.outerLeft = value
        settings.gaps.outerRight = value
        scheduleAutoSave()
    }

    // MARK: - Saving

    func saveConfiguration() async {
        guard !isSaving else { return }
        isSaving = true
        // Whatever happens. A refused Apply left this set, so the next toggle's autosave wrote the
        // raw buffer as if Apply had been pressed again.
        defer {
            isSaving = false
            rawTomlApplyRequested = false
        }
        errorMessage = nil

        let base = configBaseText()

        // An unapplied raw buffer must not be silently committed by an unrelated structured edit,
        // and the structured edit must not silently overwrite what the user typed in the raw tab.
        if !rawTomlApplyRequested, rawTomlEdited {
            errorMessage = "You have unapplied Raw TOML edits. Apply or revert them first."
            return
        }

        // Checked BEFORE touching the file. Previously an invalid config was written to disk and
        // only then failed to reload, leaving a broken file plus two separate error surfaces. Raw
        // TOML replaces the whole file, so all it has to be is valid.
        let rendered = ConfigurationWriter.render(baseText: base, from: self)
        let refusal = rawTomlApplyRequested
            ? ConfigurationWriter.validate(rendered)
            : ConfigurationWriter.refusal(rendered: rendered, base: base, from: self)
        if let refusal {
            errorMessage = refusal
            return
        }

        do {
            if rawTomlApplyRequested { ConfigurationWriter.startBackupSession() }
            try ConfigurationWriter.write(rendered)
            // The file watcher refreshes after its reload; this save suppresses the watcher for its own
            // write and did not, so a gap, layout or normalization change did nothing on screen until
            // some unrelated window event. Not under XCTest, where a refresh enumerates the machine's apps.
            if reloadConfig(), !isUnitTest {
                runRefreshSession(.globalObserver("settingsSaved"), screenIsDefinitelyUnlocked: false)
            }
            // A GUI save reloads the config WITHOUT running a refresh session, so the `updateTrayText`
            // hook does not fire. Without this, flipping "Show Dock icon" did nothing until the next
            // window event -- which, with the settings window in front, may be a long time.
            syncAppVisibility()
            didWrite(rendered)
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
        }
    }

    /// `rendered` reached the file.
    ///
    /// A structured save deliberately does NOT reload. That rebuilds every row as a fresh struct with
    /// a new UUID, which invalidates Table selections and in-flight text-field bindings -- so a 600ms
    /// autosave would yank the row out from under someone mid-edit. The view model is already the
    /// source of that write; re-reading it gains nothing. Raw TOML is the opposite: it replaced what
    /// every other pane is showing, and panes left on the old values would write them back.
    func didWrite(_ rendered: String) {
        if rawTomlApplyRequested { return load(fromText: rendered) }
        rawToml = rendered
        let rulesOnDisk = loaded.windowRules
        markLoaded()
        // A rule with no command yet held every rule back (see `replaceWindowRules`), so they are not
        // saved, and calling them saved lost any other rule edit made alongside it.
        if settings.windowRules.contains(where: \.hasNoCommand) { loaded.windowRules = rulesOnDisk }
    }
}

// MARK: - The snapshot

extension ConfigurationViewModel {
    /// Everything the panes edit, one struct per section. `edited(section)` is `current != loaded`, and
    /// the writer touches a section only when that says so -- which is the writer invariant.
    struct Settings: Equatable {
        struct General: Equatable {
            var startAtLogin = false
            var automaticallyUnhideMacosHiddenApps = false
            var defaultRootContainerLayout = "tiles"
            var defaultRootContainerOrientation = "auto"
            var accordionPadding = 30
            var enableNormalizationFlattenContainers = true
            var enableNormalizationOppositeOrientation = true
            var autoMoveWorkspacesOnMonitorConnect = true
            var showMenuBarIcon = true
            var showDockIcon = false
        }

        struct Gaps: Equatable {
            var innerHorizontal = 8
            var innerVertical = 8
            var outerTop = 8
            var outerBottom = 8
            var outerLeft = 8
            var outerRight = 8
        }

        /// Read from the raw TOML rather than the parsed `config`, for the same reason as key bindings:
        /// a parsed `Command` cannot be turned back into its exact source string.
        struct Callbacks: Equatable {
            var afterStartup: [CommandRow] = []
            var onFocusChanged: [CommandRow] = []
            var onFocusedWorkspaceChanged: [CommandRow] = []
            var onFocusedMonitorChanged: [CommandRow] = []
        }

        struct Exec: Equatable {
            var inheritEnvVars = true
            var envVars: [EnvVarRow] = []
        }

        var general = General()
        var gaps = Gaps()
        var modes: [ModeBindings] = []
        var assignments: [WorkspaceAssignmentRow] = []
        var keyMappingPreset = "qwerty"
        var callbacks = Callbacks()
        var exec = Exec()
        var windowRules: [WindowRuleRow] = []
    }

    /// One top-level key the panes edit. Load, diff and the parse-back check all read this one table;
    /// the 14 keys used to be spelled out three times over, and adding a key meant finding all three.
    struct ScalarKey {
        let key: String
        let load: @MainActor (inout Settings, Config, TOMLTable?) -> Void
        /// The value as TOML. This is what gets compared, rather than the value, so a blank command
        /// row someone has only just added does not count as an edit of that key.
        let literal: @MainActor (Settings) -> String

        @MainActor init<T>(_ key: String, _ path: WritableKeyPath<Settings, T>, _ read: @escaping (Config, TOMLTable?) -> T, _ literal: @escaping @MainActor (T) -> String) {
            self.key = key
            load = { $0[keyPath: path] = read($1, $2) }
            self.literal = { literal($0[keyPath: path]) }
        }

        @MainActor static func bool(_ key: String, _ path: WritableKeyPath<Settings, Bool>, _ config: KeyPath<Config, Bool>) -> ScalarKey {
            ScalarKey(key, path, { c, _ in c[keyPath: config] }, { $0 ? "true" : "false" })
        }

        private static func commandRows(_ value: TOMLValueConvertible?) -> [CommandRow] {
            guard let value else { return [] }
            if let string = value.string { return [CommandRow(command: string)] }
            if let array = value.array { return array.compactMap { $0.string }.map { CommandRow(command: $0) } }
            return []
        }

        @MainActor static func commands(_ key: String, _ path: WritableKeyPath<Settings, [CommandRow]>) -> ScalarKey {
            ScalarKey(key, path, { _, table in commandRows(table?[key]) }) { ConfigurationWriter.tomlArray($0.map(\.command).filter { !$0.isEmpty }) }
        }
    }
}

extension ConfigurationViewModel.Settings {
    @MainActor static let scalarKeys: [ConfigurationViewModel.ScalarKey] = [
        .bool("start-at-login", \.general.startAtLogin, \.startAtLogin),
        .bool("automatically-unhide-macos-hidden-apps", \.general.automaticallyUnhideMacosHiddenApps, \.automaticallyUnhideMacosHiddenApps),
        .bool("auto-move-workspaces-on-monitor-connect", \.general.autoMoveWorkspacesOnMonitorConnect, \.autoMoveWorkspacesOnMonitorConnect),
        .bool("show-menu-bar-icon", \.general.showMenuBarIcon, \.showMenuBarIcon),
        .bool("show-dock-icon", \.general.showDockIcon, \.showDockIcon),
        .bool("enable-normalization-flatten-containers", \.general.enableNormalizationFlattenContainers, \.enableNormalizationFlattenContainers),
        .bool("enable-normalization-opposite-orientation-for-nested-containers", \.general.enableNormalizationOppositeOrientation, \.enableNormalizationOppositeOrientationForNestedContainers),
        .init("default-root-container-layout", \.general.defaultRootContainerLayout, { c, _ in c.defaultRootContainerLayout.rawValue }, ConfigurationWriter.escapedLiteral),
        .init("default-root-container-orientation", \.general.defaultRootContainerOrientation, { c, _ in c.defaultRootContainerOrientation.rawValue }, ConfigurationWriter.escapedLiteral),
        .init("accordion-padding", \.general.accordionPadding, { c, _ in c.accordionPadding }, { String($0) }),
        .commands("after-startup-command", \.callbacks.afterStartup),
        .commands("on-focus-changed", \.callbacks.onFocusChanged),
        .commands("on-focused-workspace-changed", \.callbacks.onFocusedWorkspaceChanged),
        .commands("on-focused-monitor-changed", \.callbacks.onFocusedMonitorChanged),
    ]

    /// The one loader, used for the file the panes show and for reading a rendered save back. Key
    /// bindings, callbacks, exec and rules come from the raw table: parsed commands can't be turned
    /// back into their source strings, and `KeyMapping.preset` and `RawExecConfig` aren't reachable
    /// from `config`. Missing keys fall back to the parser's own defaults.
    @MainActor init(config: Config, table: TOMLTable?) {
        for key in Self.scalarKeys { key.load(&self, config, table) }
        func gap(_ value: DynamicConfigValue<Int>) -> Int {
            switch value {
                case .constant(let v): v
                case .perMonitor(_, let def): def
            }
        }
        gaps = Gaps(
            innerHorizontal: gap(config.gaps.inner.horizontal),
            innerVertical: gap(config.gaps.inner.vertical),
            outerTop: gap(config.gaps.outer.top),
            outerBottom: gap(config.gaps.outer.bottom),
            outerLeft: gap(config.gaps.outer.left),
            outerRight: gap(config.gaps.outer.right),
        )
        assignments = Self.assignmentRows(from: config.workspaceToMonitorForceAssignment)
        modes = Self.loadBindings(table)
        keyMappingPreset = table?["key-mapping"]?.table?["preset"]?.string ?? "qwerty"
        let rawExec = table?["exec"]?.table
        exec.inheritEnvVars = rawExec?["inherit-env-vars"]?.bool ?? true
        exec.envVars = (rawExec?["env-vars"]?.table.map { Array($0) } ?? [])
            .map { name, value in ConfigurationViewModel.EnvVarRow(name: name, value: value.string ?? "") }
            .sorted { $0.name < $1.name }
        windowRules = Self.loadWindowRules(table)
    }

    /// This state as the file reads back once written: a blank row is held back until it is typed,
    /// surrounding whitespace is gone, and order means nothing where TOML tables are unordered or the
    /// writer sorts. The writer diffs these, so whitespace alone is not an edit, and the parse-back
    /// check compares them.
    @MainActor var asWritten: Self {
        var out = self
        let separator = ConfigurationViewModel.commandSeparator
        out.modes = modes.filter { !$0.bindings.isEmpty }.sorted { $0.mode < $1.mode }.map { mode in
            let rows = mode.bindings.map {
                ConfigurationViewModel.BindingRow(key: $0.key, command: ConfigurationWriter.splitCommands($0.command).joined(separator: separator))
            }
            return ConfigurationViewModel.ModeBindings(mode: mode.mode, bindings: rows.sorted { $0.key < $1.key })
        }
        out.assignments = assignments
            .map { ConfigurationViewModel.WorkspaceAssignmentRow(workspace: $0.workspace.trimmingCharacters(in: .whitespaces), monitor: $0.monitor.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.workspace.isEmpty && !$0.monitor.isEmpty }
            .sorted { $0.workspace < $1.workspace }
        out.exec.envVars = exec.envVars
            .map { ConfigurationViewModel.EnvVarRow(name: $0.name.trimmingCharacters(in: .whitespaces), value: $0.value) }
            .filter { !$0.name.isEmpty }
            .sorted { $0.name < $1.name }
        out.windowRules = ConfigurationWriter.ruleOrderAsWritten(windowRules).map { rule in
            var rule = rule
            rule.run = ConfigurationWriter.splitCommands(rule.run).joined(separator: separator)
            return rule
        }
        return out
    }

    private static func monitorToken(_ description: MonitorDescription) -> String {
        switch description {
            case .main: return "main"
            case .secondary: return "secondary"
            case .sequenceNumber(let n): return String(n)
            case .pattern(let raw, _): return raw
            case .fingerprint(let data): return data.displayUUID ?? data.displayNamePattern ?? "fingerprint"
        }
    }

    private static func monitorDescriptionIsComplex(_ description: MonitorDescription) -> Bool {
        guard case .fingerprint(let data) = description else { return false }
        // A UUID-only fingerprint maps losslessly to the picker's exact-display option, and a
        // name-only fingerprint to its matches-by-name option — the writer's own output for a
        // name pin is `{ fingerprint = { name = … } }`, so calling that complex would brand this
        // editor's output "use Raw TOML". Everything richer cannot round-trip through one token.
        let hardware = data.vendorID != nil || data.modelID != nil || data.serialNumber != nil ||
            data.widthPixels != nil || data.heightPixels != nil
        if hardware { return true }
        let uuidOnly = data.displayUUID != nil && data.displayNamePattern == nil
        let nameOnly = data.displayNamePattern != nil && data.displayUUID == nil
        return !(uuidOnly || nameOnly)
    }

    private static func assignmentRows(from parsed: [String: [MonitorDescription]]) -> [ConfigurationViewModel.WorkspaceAssignmentRow] {
        parsed
            .sorted { $0.key < $1.key }
            .compactMap { workspace, descriptions in
                descriptions.first.map {
                    ConfigurationViewModel.WorkspaceAssignmentRow(
                        workspace: workspace,
                        monitor: monitorToken($0),
                        isComplex: descriptions.count > 1 || monitorDescriptionIsComplex($0),
                    )
                }
            }
    }

    /// Key bindings are read from the raw config text: parsed `Command` objects can't be turned back
    /// into their exact source strings, and the raw text is what the writer round-trips against.
    @MainActor private static func loadBindings(_ table: TOMLTable?) -> [ConfigurationViewModel.ModeBindings] {
        var byMode: [String: [String: String]] = [:] // mode -> key -> command
        let commandString = ConfigurationViewModel.commandString
        // `[keys]` FIRST, so a `[mode.*]` entry for the same key overwrites it. That is the order
        // the parser layers them in, and the writer edits whichever section a key came from -- so
        // showing the weaker one here would make an edit look like it did nothing.
        if let table, isConfigV2(table) {
            for (key, value) in table["keys"]?.table ?? TOMLTable() {
                // A sub-table is a named mode (`[keys.service]`); anything else is main-mode.
                if let sub = value.table {
                    for (k, v) in sub { byMode[key, default: [:]][k] = commandString(v) }
                } else {
                    byMode[mainModeId, default: [:]][key] = commandString(value)
                }
            }
        }
        for (modeName, modeValue) in table?["mode"]?.table ?? TOMLTable() {
            guard let bindingTable = modeValue.table?["binding"]?.table else { continue }
            for (key, command) in bindingTable {
                byMode[modeName, default: [:]][key] = commandString(command)
            }
        }
        return byMode
            .map { mode, rows in
                ConfigurationViewModel.ModeBindings(mode: mode, bindings: rows.map { ConfigurationViewModel.BindingRow(key: $0.key, command: $0.value) }.sorted { $0.key < $1.key })
            }
            .sorted { $0.mode < $1.mode }
    }

    /// Reads BOTH spellings.
    ///
    /// `[on-window]` is the v2 shorthand, and the one the shipped default config documents. It
    /// desugars to the same `onWindowDetected` list in `parseConfigV2`, so those rules are live --
    /// but this used to read only the long form, so a v2 config showed "No window rules" while its
    /// rules were running. Adding a rule in that state wrote a long-form copy and left the shorthand
    /// table behind, so every original rule then applied twice.
    ///
    /// Long form first, then shorthand: `parseConfigV2` appends `[on-window]` after
    /// `on-window-detected`, so this is the order the rules are actually tried in, and the list is
    /// read top to bottom.
    @MainActor private static func loadWindowRules(_ table: TOMLTable?) -> [ConfigurationViewModel.WindowRuleRow] {
        var rows = (table?["on-window-detected"]?.array).map(loadLongFormWindowRules) ?? []
        if let shorthand = table?["on-window"]?.table {
            // Sorted to match `parseOnWindow`, which walks `table.keys.sorted()`.
            rows += shorthand.keys.sorted().map { appId in
                ConfigurationViewModel.WindowRuleRow(appId: appId, run: ConfigurationViewModel.commandString(shorthand[appId] ?? ""))
            }
        }
        return rows
    }

    @MainActor private static func loadLongFormWindowRules(_ array: TOMLArray) -> [ConfigurationViewModel.WindowRuleRow] {
        array.compactMap { entry -> ConfigurationViewModel.WindowRuleRow? in
            guard let t = entry.table else { return nil }
            let cond = t["if"]?.table
            return ConfigurationViewModel.WindowRuleRow(
                appId: cond?["app-id"]?.string ?? "",
                appNameRegex: cond?["app-name-regex-substring"]?.string ?? "",
                windowTitleRegex: cond?["window-title-regex-substring"]?.string ?? "",
                workspace: cond?["workspace"]?.string ?? "",
                run: ConfigurationViewModel.commandString(t["run"] ?? ""),
                checkFurtherCallbacks: t["check-further-callbacks"]?.bool ?? false,
                // One spelling only. The upstream-branded alias for this matcher used to be read
                // here too, because the parser still accepted it with a deprecation warning --
                // reading only the current name would have dropped the matcher on the first GUI
                // edit. The parser no longer accepts it, so a config carrying it does not load and
                // this view model never sees one: the fallback was dead code, not compatibility.
                duringStartup: cond?["during-aerospork-startup"]?.bool,
            )
        }
    }
}
