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

    // Gaps
    @Published var innerGapsHorizontal = 8
    @Published var innerGapsVertical = 8
    @Published var outerGapsTop = 8
    @Published var outerGapsBottom = 8
    @Published var outerGapsLeft = 8
    @Published var outerGapsRight = 8

    // Key bindings (add / remove editable)
    @Published var modes: [ModeBindings] = []

    // Workspaces & monitors
    @Published var assignments: [WorkspaceAssignmentRow] = []
    @Published var liveMonitors: [MonitorRow] = []

    // State
    @Published var hasUnsavedChanges = false
    @Published var errorMessage: String?
    @Published var isSaving = false

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

    // MARK: - Loading

    func loadConfiguration() async {
        reloadFromConfig()
    }

    func revertChanges() {
        reloadFromConfig()
    }

    func markAsModified() {
        hasUnsavedChanges = true
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
        modes = loadBindings()

        hasUnsavedChanges = false
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
    private func loadBindings() -> [ModeBindings] {
        guard let table = try? TOMLTable(string: configBaseText()), let modeTable = table["mode"]?.table else {
            return []
        }
        var result: [ModeBindings] = []
        for (modeName, modeValue) in modeTable {
            guard let bindingTable = modeValue.table?["binding"]?.table else { continue }
            var rows: [BindingRow] = []
            for (key, command) in bindingTable {
                rows.append(BindingRow(key: key, command: commandString(command)))
            }
            result.append(ModeBindings(mode: modeName, bindings: rows.sorted { $0.key < $1.key }))
        }
        return result.sorted { $0.mode < $1.mode }
    }

    private func commandString(_ value: TOMLValueConvertible) -> String {
        if let string = value.string { return string }
        if let array = value.array { return array.compactMap { $0.string }.joined(separator: ", ") }
        return ""
    }

    // MARK: - Editing

    func addBinding(mode: String, key: String, command: String) {
        let key = key.trimmingCharacters(in: .whitespaces)
        let command = command.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !command.isEmpty, let i = modes.firstIndex(where: { $0.mode == mode }) else { return }
        modes[i].bindings.removeAll { $0.key == key }
        modes[i].bindings.append(BindingRow(key: key, command: command))
        modes[i].bindings.sort { $0.key < $1.key }
        markAsModified()
    }

    func removeBinding(mode: String, id: BindingRow.ID) {
        guard let i = modes.firstIndex(where: { $0.mode == mode }) else { return }
        modes[i].bindings.removeAll { $0.id == id }
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

        do {
            try ConfigurationWriter.write(from: self)
            if reloadConfig() {
                reloadFromConfig()
            } else {
                errorMessage = "Config was saved but failed to reload. See the config error dialog."
            }
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
        }
    }

    // MARK: - Validation

    func validateGaps() -> [String] {
        let fields: [(String, Int)] = [
            ("Inner horizontal", innerGapsHorizontal),
            ("Inner vertical", innerGapsVertical),
            ("Outer top", outerGapsTop),
            ("Outer bottom", outerGapsBottom),
            ("Outer left", outerGapsLeft),
            ("Outer right", outerGapsRight),
        ]
        return fields.filter { $0.1 < 0 }.map { "\($0.0) gap cannot be negative" }
    }
}
