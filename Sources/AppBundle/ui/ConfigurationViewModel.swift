import AppKit
import Common
import SwiftUI
import TOMLKit

/// Backs the settings window. Reads current values from the live `config` (and the raw config text
/// for key bindings, which can't be losslessly reconstructed from parsed commands), and on save
/// hands its fields to the comment-preserving `ConfigurationWriter`, then reloads the config.
@MainActor
final class ConfigurationViewModel: ObservableObject {
    // General
    @Published var startAtLogin = false
    @Published var automaticallyUnhideMacosHiddenApps = false
    @Published var defaultRootContainerLayout = "tiles"
    @Published var defaultRootContainerOrientation = "auto"
    @Published var accordionPadding = 30
    @Published var enableNormalizationFlattenContainers = true
    @Published var enableNormalizationOppositeOrientation = true
    @Published var autoMoveWorkspacesOnMonitorConnect = true
    @Published var showMenuBarIcon = true
    @Published var showDockIcon = false

    /// What the two visibility toggles will actually produce, including the forced Dock icon. The
    /// General tab shows the rule rather than letting the user find out after they close Settings.
    var appVisibility: AppVisibility { AppVisibility(showMenuBarIcon: showMenuBarIcon, showDockIcon: showDockIcon) }

    // Gaps
    @Published var innerGapsHorizontal = 8
    @Published var innerGapsVertical = 8
    @Published var outerGapsTop = 8
    @Published var outerGapsBottom = 8
    @Published var outerGapsLeft = 8
    @Published var outerGapsRight = 8

    // Key bindings the writer manages: the `[mode.<name>.binding]` sections, plus anything the user
    // adds here. This list and ONLY this list is what `ConfigurationWriter.applyBindingDiff` writes.
    @Published var modes: [ModeBindings] = []

    /// Bindings that are active but live nowhere the writer can round-trip: the ~78 that `mod` +
    /// `workspaces` generate out of thin air, and the `[keys]` / `[keys.<mode>]` entries.
    ///
    /// They are kept OUT of `modes` on purpose. Putting them there would make the very next save
    /// write all of them back as `[mode.main.binding]` lines -- re-materializing exactly the
    /// boilerplate config v2 exists to delete. The tab still shows them, because a Keys tab that
    /// hides 78 live bindings is lying about what the keyboard does.
    @Published private(set) var inheritedBindings: [InheritedBinding] = []

    // Workspaces & monitors
    @Published var assignments: [WorkspaceAssignmentRow] = []
    @Published var liveMonitors: [MonitorRow] = []

    // Key mapping
    @Published var keyMappingPreset = "qwerty"

    // Callbacks. Read from the raw TOML rather than the parsed `config`, for the same reason as key
    // bindings: a parsed `Command` cannot be turned back into its exact source string.
    @Published var afterStartupCommands: [CommandRow] = []
    @Published var onFocusChanged: [CommandRow] = []
    @Published var onFocusedWorkspaceChanged: [CommandRow] = []
    @Published var onFocusedMonitorChanged: [CommandRow] = []

    // Exec environment
    @Published var execInheritEnvVars = true
    @Published var execEnvVars: [EnvVarRow] = []

    // Window detection rules ([[on-window-detected]])
    @Published var windowRules: [WindowRuleRow] = []

    // Raw TOML editor -- the guarantee that nothing in the config is unreachable from the GUI.
    @Published var rawToml = ""

    /// Set ONLY by the Raw TOML tab's Apply button.
    ///
    /// `rawTomlEdited` must never authorize a write on its own: an unapplied raw buffer used to
    /// hijack unrelated structured edits, so flipping a toggle on another tab would commit the
    /// half-finished raw text and silently discard the toggle.
    @Published var rawTomlApplyRequested = false

    // State
    @Published var hasUnsavedChanges = false
    @Published var errorMessage: String?
    @Published var isSaving = false

    /// Snapshot of what was loaded, so the writer can tell a real edit from an untouched section.
    /// The fields above are a lossy projection of the config (per-monitor gaps collapse to their
    /// default, fingerprints to a string, monitor fallback lists to `.first`), so re-serializing an
    /// untouched section silently destroys whatever the UI couldn't represent.
    private var loaded = LoadedSnapshot()

    private struct LoadedSnapshot {
        var startAtLogin = false
        var automaticallyUnhideMacosHiddenApps = false
        var autoMoveWorkspacesOnMonitorConnect = true
        var showMenuBarIcon = true
        var showDockIcon = false
        var enableNormalizationFlattenContainers = true
        var enableNormalizationOppositeOrientation = true
        var defaultRootContainerLayout = ""
        var defaultRootContainerOrientation = ""
        var accordionPadding = 0
        var gaps: [Int] = []
        var assignments: [(workspace: String, monitor: String)] = []
        var keyMappingPreset = ""
        var afterStartupCommands: [CommandRow] = []
        var onFocusChanged: [CommandRow] = []
        var onFocusedWorkspaceChanged: [CommandRow] = []
        var onFocusedMonitorChanged: [CommandRow] = []
        var execInheritEnvVars = true
        var execEnvVars: [EnvVarRow] = []
        var windowRules: [WindowRuleRow] = []
        var rawToml = ""
        var modeNames: Set<String> = []
    }

    var keyMappingEdited: Bool { keyMappingPreset != loaded.keyMappingPreset }
    var execEdited: Bool { execInheritEnvVars != loaded.execInheritEnvVars || execEnvVars != loaded.execEnvVars }
    var windowRulesEdited: Bool { windowRules != loaded.windowRules }
    var rawTomlEdited: Bool { rawToml != loaded.rawToml }

    /// Callback lists that changed, as `(config key, commands)`. Empty lists are still emitted when
    /// they were previously non-empty, so clearing a callback in the UI actually clears it on disk.
    func changedCallbacks() -> [(String, [String])] {
        var out: [(String, [String])] = []
        func add(_ key: String, _ now: [CommandRow], _ before: [CommandRow]) {
            if now != before { out.append((key, now.map(\.command).filter { !$0.isEmpty })) }
        }
        add("after-startup-command", afterStartupCommands, loaded.afterStartupCommands)
        add("on-focus-changed", onFocusChanged, loaded.onFocusChanged)
        add("on-focused-workspace-changed", onFocusedWorkspaceChanged, loaded.onFocusedWorkspaceChanged)
        add("on-focused-monitor-changed", onFocusedMonitorChanged, loaded.onFocusedMonitorChanged)
        return out
    }

    private var currentGaps: [Int] {
        [innerGapsHorizontal, innerGapsVertical, outerGapsTop, outerGapsBottom, outerGapsLeft, outerGapsRight]
    }

    var gapsEdited: Bool { currentGaps != loaded.gaps }

    var assignmentsEdited: Bool {
        let current = assignments.map { (workspace: $0.workspace, monitor: $0.monitor) }
        guard current.count == loaded.assignments.count else { return true }
        return zip(current, loaded.assignments).contains { $0.workspace != $1.workspace || $0.monitor != $1.monitor }
    }

    /// Top-level scalar keys whose value differs from what was loaded, as `(key, TOML literal)`.
    func changedScalars() -> [(String, String)] {
        var out: [(String, String)] = []
        func addBool(_ key: String, _ now: Bool, _ before: Bool) {
            if now != before { out.append((key, now ? "true" : "false")) }
        }
        addBool("start-at-login", startAtLogin, loaded.startAtLogin)
        addBool("automatically-unhide-macos-hidden-apps", automaticallyUnhideMacosHiddenApps, loaded.automaticallyUnhideMacosHiddenApps)
        addBool("auto-move-workspaces-on-monitor-connect", autoMoveWorkspacesOnMonitorConnect, loaded.autoMoveWorkspacesOnMonitorConnect)
        addBool("show-menu-bar-icon", showMenuBarIcon, loaded.showMenuBarIcon)
        addBool("show-dock-icon", showDockIcon, loaded.showDockIcon)
        addBool("enable-normalization-flatten-containers", enableNormalizationFlattenContainers, loaded.enableNormalizationFlattenContainers)
        addBool("enable-normalization-opposite-orientation-for-nested-containers", enableNormalizationOppositeOrientation, loaded.enableNormalizationOppositeOrientation)
        if defaultRootContainerLayout != loaded.defaultRootContainerLayout {
            out.append(("default-root-container-layout", "'\(defaultRootContainerLayout.replacingOccurrences(of: "'", with: ""))'"))
        }
        if defaultRootContainerOrientation != loaded.defaultRootContainerOrientation {
            out.append(("default-root-container-orientation", "'\(defaultRootContainerOrientation.replacingOccurrences(of: "'", with: ""))'"))
        }
        if accordionPadding != loaded.accordionPadding {
            out.append(("accordion-padding", String(accordionPadding)))
        }
        return out
    }

    struct ModeBindings: Identifiable {
        let id = UUID()
        var mode: String
        var bindings: [BindingRow]
    }

    struct BindingRow: Identifiable {
        let id = UUID()
        var key: String
        var command: String
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
    /// `rowId` is non-nil exactly when the row is editable, i.e. when it is backed by `modes`.
    struct DisplayBinding: Identifiable {
        var key: String
        var command: String
        var origin: BindingOrigin
        var rowId: BindingRow.ID?
        var id: String { key }
    }

    struct WorkspaceAssignmentRow: Identifiable {
        let id = UUID()
        var workspace: String
        var monitor: String
    }

    struct MonitorRow: Identifiable {
        let id = UUID()
        var name: String
        var resolution: String
        var uuid: String?
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

    func markAsModified() {
        hasUnsavedChanges = true
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
                self.markAsModified()
                self.scheduleAutoSave()
            },
        )
    }

    private var autoSaveTask: Task<Void, Never>?

    /// Called when the settings window goes away. Without this a pending autosave outlives the
    /// window and writes the config up to 600ms after it was dismissed.
    func cancelPendingAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
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
        errorMessage = nil

        startAtLogin = config.startAtLogin
        automaticallyUnhideMacosHiddenApps = config.automaticallyUnhideMacosHiddenApps
        defaultRootContainerLayout = config.defaultRootContainerLayout.rawValue
        defaultRootContainerOrientation = config.defaultRootContainerOrientation.rawValue
        accordionPadding = config.accordionPadding
        enableNormalizationFlattenContainers = config.enableNormalizationFlattenContainers
        enableNormalizationOppositeOrientation = config.enableNormalizationOppositeOrientationForNestedContainers
        autoMoveWorkspacesOnMonitorConnect = config.autoMoveWorkspacesOnMonitorConnect
        showMenuBarIcon = config.showMenuBarIcon
        showDockIcon = config.showDockIcon

        innerGapsHorizontal = gapValue(config.gaps.inner.horizontal)
        innerGapsVertical = gapValue(config.gaps.inner.vertical)
        outerGapsTop = gapValue(config.gaps.outer.top)
        outerGapsBottom = gapValue(config.gaps.outer.bottom)
        outerGapsLeft = gapValue(config.gaps.outer.left)
        outerGapsRight = gapValue(config.gaps.outer.right)

        assignments = config.workspaceToMonitorForceAssignment
            .sorted { $0.key < $1.key }
            .compactMap { workspace, descriptions in
                descriptions.first.map { WorkspaceAssignmentRow(workspace: workspace, monitor: monitorToken($0)) }
            }

        liveMonitors = loadMonitors()

        let base = configBaseText()
        rawToml = base
        let table = try? TOMLTable(string: base)
        modes = loadBindings(table)
        inheritedBindings = loadInheritedBindings(table)
        // `KeyMapping.preset` is fileprivate and `RawExecConfig` isn't reachable from the parsed
        // `config`, so these come from the raw TOML with the parser's own defaults as fallback.
        keyMappingPreset = table?["key-mapping"]?.table?["preset"]?.string ?? "qwerty"
        afterStartupCommands = commandRows(table?["after-startup-command"])
        onFocusChanged = commandRows(table?["on-focus-changed"])
        onFocusedWorkspaceChanged = commandRows(table?["on-focused-workspace-changed"])
        onFocusedMonitorChanged = commandRows(table?["on-focused-monitor-changed"])

        let exec = table?["exec"]?.table
        execInheritEnvVars = exec?["inherit-env-vars"]?.bool ?? true
        var envRows: [EnvVarRow] = []
        if let envTable = exec?["env-vars"]?.table {
            for (name, value) in envTable {
                envRows.append(EnvVarRow(name: name, value: value.string ?? ""))
            }
        }
        execEnvVars = envRows.sorted { $0.name < $1.name }

        windowRules = loadWindowRules(table)

        markLoaded()

        hasUnsavedChanges = false
    }

    /// Record the current field values as the "loaded" baseline that edit detection compares
    /// against. Called at the end of a load; also used by tests that build a view model directly.
    func markLoaded() {
        loaded = LoadedSnapshot(
            startAtLogin: startAtLogin,
            automaticallyUnhideMacosHiddenApps: automaticallyUnhideMacosHiddenApps,
            autoMoveWorkspacesOnMonitorConnect: autoMoveWorkspacesOnMonitorConnect,
            showMenuBarIcon: showMenuBarIcon,
            showDockIcon: showDockIcon,
            enableNormalizationFlattenContainers: enableNormalizationFlattenContainers,
            enableNormalizationOppositeOrientation: enableNormalizationOppositeOrientation,
            defaultRootContainerLayout: defaultRootContainerLayout,
            defaultRootContainerOrientation: defaultRootContainerOrientation,
            accordionPadding: accordionPadding,
            gaps: currentGaps,
            assignments: assignments.map { (workspace: $0.workspace, monitor: $0.monitor) },
            keyMappingPreset: keyMappingPreset,
            afterStartupCommands: afterStartupCommands,
            onFocusChanged: onFocusChanged,
            onFocusedWorkspaceChanged: onFocusedWorkspaceChanged,
            onFocusedMonitorChanged: onFocusedMonitorChanged,
            execInheritEnvVars: execInheritEnvVars,
            execEnvVars: execEnvVars,
            windowRules: windowRules,
            rawToml: rawToml,
            modeNames: Set(modes.map(\.mode)),
        )
    }

    private func gapValue(_ value: DynamicConfigValue<Int>) -> Int {
        switch value {
            case .constant(let v): return v
            case .perMonitor(_, let def): return def
        }
    }

    private func monitorToken(_ description: MonitorDescription) -> String {
        switch description {
            case .main: return "main"
            case .secondary: return "secondary"
            case .sequenceNumber(let n): return String(n)
            case .pattern(let raw, _): return raw
            case .fingerprint(let data): return data.displayUUID ?? data.displayNamePattern ?? "fingerprint"
        }
    }

    private func loadMonitors() -> [MonitorRow] {
        sortedMonitors.map { monitor in
            let fingerprint = (monitor as? LazyMonitor)?.fingerprint
            let width = fingerprint?.widthPixels ?? Int(monitor.width)
            let height = fingerprint?.heightPixels ?? Int(monitor.height)
            return MonitorRow(name: monitor.name, resolution: "\(width)×\(height)", uuid: fingerprint?.displayUUID)
        }
    }

    /// Key bindings are read from the raw config text: parsed `Command` objects can't be turned back
    /// into their exact source strings, and the raw text is what the writer round-trips against.
    private func loadBindings(_ table: TOMLTable?) -> [ModeBindings] {
        var byMode: [String: [String: String]] = [:] // mode -> key -> command
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
                ModeBindings(mode: mode, bindings: rows.map { BindingRow(key: $0.key, command: $0.value) }.sorted { $0.key < $1.key })
            }
            .sorted { $0.mode < $1.mode }
    }

    /// Everything bound that the writer does NOT manage: the bindings `mod` + `workspaces` generate,
    /// which exist nowhere in the file and so have no lines to round-trip against. Empty for a v1
    /// config. (`[keys]` used to be listed here too, back when the writer only understood
    /// `[mode.*.binding]`; it is editable in place now and belongs to `loadBindings`.)
    private func loadInheritedBindings(_ table: TOMLTable?) -> [InheritedBinding] {
        guard let table, isConfigV2(table), let mod = table["mod"]?.string else { return [] }
        // Same function the parser and the migration collapser use, so the tab cannot show a set of
        // generated bindings that differs from the set actually registered.
        return generatedBindingsV2(mod: mod, workspaces: workspaceNames(table["workspaces"]))
            .map { InheritedBinding(mode: mainModeId, key: $0.notation, command: $0.command, origin: .generated) }
    }

    /// `workspaces = "1-9"`, `["dev", "web"]`, or both. Mirrors the parser's own reading; the
    /// parser's copy is private and returning a different list here would mean the tab and the
    /// keyboard disagree about which workspace keys exist.
    private func workspaceNames(_ value: TOMLValueConvertible?) -> [String] {
        guard let value else { return [] }
        if let array = value.array { return (0 ..< array.count).flatMap { workspaceNames(array[$0]) } }
        guard let token = value.string ?? value.int.map(String.init) else { return [] }
        return expandWorkspaceRange(token) ?? [token]
    }

    /// A binding value is either a single command string or an array of them. Multi-command
    /// bindings are joined with " ; " -- NOT ", " -- because the writer splits on the same
    /// separator to re-emit a TOML array. Joining with ", " used to produce `key = 'a, b'`, a
    /// single bogus command, whenever such a row was re-added.
    static let commandSeparator = " ; "

    /// Also used by `ConfigurationWriter.applyBindingDiff` to decide whether a binding line changed.
    /// It must be the same function both places: comparing against a differently-derived string
    /// would rewrite untouched lines and break the byte-identical no-op-save invariant.
    static func commandString(_ value: TOMLValueConvertible) -> String {
        if let string = value.string { return string }
        if let array = value.array { return array.compactMap { $0.string }.joined(separator: Self.commandSeparator) }
        return ""
    }

    private func commandString(_ value: TOMLValueConvertible) -> String { Self.commandString(value) }

    private func commandRows(_ value: TOMLValueConvertible?) -> [CommandRow] {
        guard let value else { return [] }
        if let string = value.string { return [CommandRow(command: string)] }
        if let array = value.array { return array.compactMap { $0.string }.map { CommandRow(command: $0) } }
        return []
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
    private func loadWindowRules(_ table: TOMLTable?) -> [WindowRuleRow] {
        var rows = (table?["on-window-detected"]?.array).map(loadLongFormWindowRules) ?? []
        if let shorthand = table?["on-window"]?.table {
            // Sorted to match `parseOnWindow`, which walks `table.keys.sorted()`.
            rows += shorthand.keys.sorted().map { appId in
                WindowRuleRow(
                    appId: appId,
                    appNameRegex: "",
                    windowTitleRegex: "",
                    workspace: "",
                    run: commandString(shorthand[appId] ?? ""),
                    checkFurtherCallbacks: false,
                    duringStartup: nil,
                )
            }
        }
        return rows
    }

    private func loadLongFormWindowRules(_ array: TOMLArray) -> [WindowRuleRow] {
        array.compactMap { entry -> WindowRuleRow? in
            guard let t = entry.table else { return nil }
            let cond = t["if"]?.table
            return WindowRuleRow(
                appId: cond?["app-id"]?.string ?? "",
                appNameRegex: cond?["app-name-regex-substring"]?.string ?? "",
                windowTitleRegex: cond?["window-title-regex-substring"]?.string ?? "",
                workspace: cond?["workspace"]?.string ?? "",
                run: commandString(t["run"] ?? ""),
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

    /// Load both binding lists from config text instead of from the real config file. The only
    /// caller besides `reloadFromConfig` is the test suite, which must not depend on `~/.aerospork.toml`.
    func loadBindings(fromText text: String) {
        let table = try? TOMLTable(string: text)
        modes = loadBindings(table)
        inheritedBindings = loadInheritedBindings(table)
    }

    /// Same, for window rules. Lets a test assert that what the writer emitted reads back as the
    /// same rule -- which is the only way to catch a matcher key the writer and the loader spell
    /// differently.
    func loadWindowRules(fromText text: String) {
        windowRules = loadWindowRules(try? TOMLTable(string: text))
    }

    // MARK: - Displaying

    /// Every mode that has bindings from any source, `main` first. The picker cannot read `modes`
    /// alone: a v2 config's modes live in `[keys.<name>]`, which the writer never sees.
    var allModeNames: [String] {
        Set(modes.map(\.mode)).union(inheritedBindings.map(\.mode))
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
        for row in modes.first(where: { $0.mode == mode })?.bindings ?? [] {
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
        guard let m = modes.firstIndex(where: { $0.mode == mode }),
              let r = modes[m].bindings.firstIndex(where: { $0.id == id }) else { return false }
        if let key {
            let key = key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return false }
            // Two writable rows with the same key in one mode is not a cosmetic problem: the writer
            // emits a line for each, and duplicate keys in one TOML table do not parse -- so the
            // save that follows would leave the user with a config the app refuses to load. The
            // table would show only one of them too, making the other invisible as well as fatal.
            guard !modes[m].bindings.contains(where: { $0.id != id && $0.key == key }) else { return false }
            modes[m].bindings[r].key = key
        }
        if let command { modes[m].bindings[r].command = command }
        markAsModified()
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
        let i = modes.firstIndex { $0.mode == mode } ?? { addMode(mode); return modes.count - 1 }()
        modes[i].bindings.removeAll { $0.key == key }
        modes[i].bindings.append(BindingRow(key: key, command: command))
        modes[i].bindings.sort { $0.key < $1.key }
        markAsModified()
        return true
    }

    func removeBinding(mode: String, id: BindingRow.ID) {
        guard let i = modes.firstIndex(where: { $0.mode == mode }) else { return }
        modes[i].bindings.removeAll { $0.id == id }
        markAsModified()
    }

    /// Returns false if the name is empty or already taken.
    @discardableResult
    func addMode(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !modes.contains(where: { $0.mode == name }) else { return false }
        modes.append(ModeBindings(mode: name, bindings: []))
        markAsModified()
        return true
    }

    /// `main` is the mode the app starts in; deleting it would leave nothing to fall back to.
    func canRemoveMode(_ name: String) -> Bool { name != mainModeId && modes.contains { $0.mode == name } }

    func removeMode(_ name: String) {
        guard canRemoveMode(name) else { return }
        modes.removeAll { $0.mode == name }
        markAsModified()
    }

    /// Modes present when the config was loaded, so the writer can tell "the user deleted this mode"
    /// from "this view model never loaded any modes" -- the latter must not delete anything.
    var loadedModeNames: Set<String> { loaded.modeNames }

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
        markAsModified()
    }

    func addAssignment() {
        assignments.append(WorkspaceAssignmentRow(workspace: "", monitor: "main"))
        markAsModified()
    }

    func removeAssignment(id: WorkspaceAssignmentRow.ID) {
        assignments.removeAll { $0.id == id }
        markAsModified()
    }

    // MARK: - Saving

    func saveConfiguration() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let base = configBaseText()

        // Refuse rather than corrupt when the file uses a TOML spelling this line-based writer
        // cannot rewrite safely. Only applies to structured edits -- raw TOML replaces the file.
        if !rawTomlApplyRequested, let shape = ConfigurationWriter.unsupportedShapeReason(base) {
            errorMessage = shape
            return
        }
        // An unapplied raw buffer must not be silently committed by an unrelated structured edit,
        // and the structured edit must not silently overwrite what the user typed in the raw tab.
        if !rawTomlApplyRequested, rawTomlEdited {
            errorMessage = "You have unapplied Raw TOML edits. Apply or revert them first."
            return
        }

        // Validate BEFORE touching the file. Previously an invalid config was written to disk and
        // only then failed to reload, leaving a broken file plus two separate error surfaces.
        let rendered = ConfigurationWriter.render(baseText: base, from: self)
        if let problem = ConfigurationWriter.validate(rendered) {
            errorMessage = problem
            return
        }

        do {
            try ConfigurationWriter.write(rendered)
            _ = reloadConfig()
            // A GUI save reloads the config WITHOUT running a refresh session, so the `updateTrayText`
            // hook does not fire. Without this, flipping "Show Dock icon" did nothing until the next
            // window event -- which, with the settings window in front, may be a long time.
            syncAppVisibility()
            rawToml = rendered
            // Deliberately NOT reloadFromConfig() here. That rebuilds every row as a fresh struct
            // with a new UUID, which invalidates Table selections and in-flight text-field bindings
            // -- so a 600ms autosave would yank the row out from under someone mid-edit. The view
            // model is already the source of this write; re-reading it gains nothing.
            markLoaded()
            rawTomlApplyRequested = false
            hasUnsavedChanges = false
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
        }
    }

    /// Live validation for the raw TOML tab, so errors surface while typing rather than on save.
    var rawTomlError: String? { rawTomlEdited ? ConfigurationWriter.validate(rawToml) : nil }
}
