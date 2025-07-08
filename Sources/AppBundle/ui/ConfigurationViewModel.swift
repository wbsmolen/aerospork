import SwiftUI
import Common
import TOMLKit
import AppKit

@MainActor
class ConfigurationViewModel: ObservableObject {
    // General settings
    @Published var startAtLogin: Bool = false
    @Published var automaticallyUnhideMacosHiddenApps: Bool = false
    @Published var defaultRootContainerLayout: String = "tiles"
    @Published var defaultRootContainerOrientation: String = "auto"
    @Published var accordionPadding: Int = 30
    @Published var enableNormalizationFlattenContainers: Bool = true
    @Published var enableNormalizationOppositeOrientation: Bool = true
    
    // Workspace assignments
    @Published var workspaceAssignments: [WorkspaceAssignment] = []
    @Published var autoMoveWorkspacesOnMonitorConnect: Bool = true
    @Published var connectedMonitors: [MonitorInfo] = []
    @Published var allWorkspaces: [String] = []
    
    // Gaps
    @Published var innerGaps: Int = 5
    @Published var outerGapsTop: Int = 20
    @Published var outerGapsBottom: Int = 20
    @Published var outerGapsLeft: Int = 20
    @Published var outerGapsRight: Int = 20
    
    // Key bindings (read-only display)
    @Published var keyBindings: [(mode: String, bindings: [(key: String, command: String)])] = []
    
    // State management
    @Published var hasUnsavedChanges: Bool = false
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    
    private var originalTomlTable: TOMLTable?
    private var configFilePath: String?
    
    struct MonitorInfo: Identifiable {
        let id = UUID()
        let name: String
        let index: Int
        let fingerprint: MonitorFingerprint
        let isMain: Bool
        let width: Int
        let height: Int
        let positionX: CGFloat
        let positionY: CGFloat
        
        struct MonitorFingerprint: Equatable {
            let vendorId: String?
            let modelId: String?
            let serialNumber: String?
            let displayName: String
            let widthPixels: Int
            let heightPixels: Int
            
            var displayString: String {
                var parts: [String] = []
                if let vendorId = vendorId {
                    parts.append("vendor:\(vendorId)")
                }
                if let modelId = modelId {
                    parts.append("model:\(modelId)")
                }
                if let serial = serialNumber, !serial.isEmpty {
                    parts.append("serial:\(serial)")
                }
                parts.append("\(widthPixels)×\(heightPixels)")
                return parts.joined(separator: " ")
            }
        }
    }
    
    struct WorkspaceAssignment: Identifiable {
        let id = UUID()
        var workspaceName: String
        var monitorDescription: String
        var monitorType: MonitorType
        var isForceAssignment: Bool = false
        
        enum MonitorType {
            case name(String)
            case index(Int)
            case fingerprint(MonitorFingerprint)
        }
        
        struct MonitorFingerprint {
            var vendorId: String?
            var modelId: String?
            var serialNumber: String?
            var displayName: String?
            var width: Int?
            var height: Int?
        }
    }
    
    func loadConfiguration() async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Get config file path
            let configFile = findCustomConfigUrl()
            guard let configUrl = configFile.urlOrNil else {
                errorMessage = "No configuration file found"
                isLoading = false
                return
            }
            configFilePath = configUrl.path
            
            // Read and parse TOML
            let content = try String(contentsOfFile: configFilePath!)
            let tomlTable = try TOMLTable(string: content)
            originalTomlTable = tomlTable
            
            // Load general settings
            if let startAtLoginValue = tomlTable["start-at-login"]?.bool {
                startAtLogin = startAtLoginValue
            }
            if let autoUnhide = tomlTable["automatically-unhide-macos-hidden-apps"]?.bool {
                automaticallyUnhideMacosHiddenApps = autoUnhide
            }
            if let layout = tomlTable["default-root-container-layout"]?.string {
                defaultRootContainerLayout = layout
            }
            if let orientation = tomlTable["default-root-container-orientation"]?.string {
                defaultRootContainerOrientation = orientation
            }
            if let padding = tomlTable["accordion-padding"]?.int {
                accordionPadding = padding
            }
            if let flatten = tomlTable["enable-normalization-flatten-containers"]?.bool {
                enableNormalizationFlattenContainers = flatten
            }
            if let opposite = tomlTable["enable-normalization-opposite-orientation-for-nested-containers"]?.bool {
                enableNormalizationOppositeOrientation = opposite
            }
            if let autoMove = tomlTable["auto-move-workspaces-on-monitor-connect"]?.bool {
                autoMoveWorkspacesOnMonitorConnect = autoMove
            }
            
            // Load gaps
            if let gaps = tomlTable["gaps"]?.table {
                if let inner = gaps["inner"]?.table?["horizontal"]?.int {
                    innerGaps = inner
                }
                if let outer = gaps["outer"]?.table {
                    if let top = outer["top"]?.int { outerGapsTop = top }
                    if let bottom = outer["bottom"]?.int { outerGapsBottom = bottom }
                    if let left = outer["left"]?.int { outerGapsLeft = left }
                    if let right = outer["right"]?.int { outerGapsRight = right }
                }
            }
            
            // Load workspace assignments
            workspaceAssignments = []
            
            // Load regular assignments
            // Note: AeroSpace only has workspace-to-monitor-force-assignment key,
            // but we'll track regular vs force assignments in our UI
            
            // Load force assignments
            if let assignments = tomlTable["workspace-to-monitor-force-assignment"]?.table {
                print("[DEBUG] Loading workspace assignments from config")
                for (workspace, value) in assignments {
                    print("[DEBUG] Processing workspace '\(workspace)' with value type: \(type(of: value))")
                    
                    // Try to parse the assignment
                    if var assignment = parseWorkspaceAssignment(workspace: workspace, value: value) {
                        assignment.isForceAssignment = true
                        workspaceAssignments.append(assignment)
                        print("[DEBUG] Successfully loaded assignment for workspace '\(workspace)'")
                    } else {
                        print("[DEBUG] Failed to parse assignment for workspace '\(workspace)'")
                    }
                }
                print("[DEBUG] Loaded \(workspaceAssignments.count) workspace assignments")
            } else {
                print("[DEBUG] No workspace-to-monitor-force-assignment section found")
            }
            
            // Load current monitor information
            loadConnectedMonitors()
            
            // Load key bindings for display
            loadKeyBindings(from: tomlTable)
            
            // Extract all workspace names from keybindings and assignments
            extractAllWorkspaces(from: tomlTable)
            
            hasUnsavedChanges = false
        } catch {
            errorMessage = "Failed to load configuration: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func parseWorkspaceAssignment(workspace: String, value: TOMLValueConvertible) -> WorkspaceAssignment? {
        print("[DEBUG] parseWorkspaceAssignment for workspace '\(workspace)'")
        print("[DEBUG] Value type: \(type(of: value))")
        
        if let stringValue = value.string {
            // Simple string assignment
            print("[DEBUG] Found string value: \(stringValue)")
            return WorkspaceAssignment(
                workspaceName: workspace,
                monitorDescription: stringValue,
                monitorType: parseMonitorType(from: stringValue)
            )
        } else if let intValue = value.int {
            // Index assignment
            print("[DEBUG] Found int value: \(intValue)")
            return WorkspaceAssignment(
                workspaceName: workspace,
                monitorDescription: String(intValue),
                monitorType: .index(intValue)
            )
        } else if let table = value.table {
            print("[DEBUG] Found table with keys: \(table.keys)")
            print("[DEBUG] Table contents:")
            for (key, val) in table {
                print("[DEBUG]   \(key): \(type(of: val)) = \(val)")
            }
            
            // Table assignment - could be inline or nested section format
            let fingerprintTable: TOMLTable?
            
            if let fp = table["fingerprint"]?.table {
                // Inline format: { fingerprint = { ... } }
                print("[DEBUG] Found inline fingerprint table")
                fingerprintTable = fp
            } else if table.keys.contains(where: { ["vendor_id", "model_id", "serial_number", "display_name", "width", "height"].contains($0) }) {
                // Nested section format: the table itself is the fingerprint
                print("[DEBUG] Table appears to be fingerprint data directly")
                fingerprintTable = table
            } else if table.count == 1, let firstKey = table.keys.first, firstKey == "fingerprint",
                      let nestedTable = table[firstKey]?.table {
                // Handle case where we have { "fingerprint": <table> } from nested sections
                print("[DEBUG] Found nested fingerprint structure")
                fingerprintTable = nestedTable
            } else {
                // Unknown table format
                print("[DEBUG] Unknown table format, keys: \(table.keys)")
                return nil
            }
            
            if let fingerprint = fingerprintTable {
                print("[DEBUG] Processing fingerprint with keys: \(fingerprint.keys)")
                var fp = WorkspaceAssignment.MonitorFingerprint()
                fp.vendorId = fingerprint["vendor_id"]?.string
                fp.modelId = fingerprint["model_id"]?.string
                fp.serialNumber = fingerprint["serial_number"]?.string
                fp.displayName = fingerprint["display_name"]?.string
                fp.width = fingerprint["width"]?.int
                fp.height = fingerprint["height"]?.int
                
                print("[DEBUG] Created fingerprint: vendorId=\(fp.vendorId ?? "nil"), modelId=\(fp.modelId ?? "nil"), displayName=\(fp.displayName ?? "nil"), width=\(fp.width?.description ?? "nil"), height=\(fp.height?.description ?? "nil")")
                
                return WorkspaceAssignment(
                    workspaceName: workspace,
                    monitorDescription: "Fingerprint",
                    monitorType: .fingerprint(fp)
                )
            }
        }
        print("[DEBUG] Failed to parse assignment - returning nil")
        return nil
    }
    
    private func parseMonitorType(from string: String) -> WorkspaceAssignment.MonitorType {
        if let index = Int(string) {
            return .index(index)
        } else {
            return .name(string)
        }
    }
    
    private func loadKeyBindings(from toml: TOMLTable) {
        keyBindings = []
        
        if let modes = toml["mode"]?.table {
            for (modeName, modeTable) in modes {
                if let bindings = modeTable.table?["binding"]?.table {
                    var modeBindings: [(key: String, command: String)] = []
                    for (key, command) in bindings {
                        if let cmdString = command.string {
                            modeBindings.append((key: key, command: cmdString))
                        } else if let cmdArray = command.array {
                            let cmdString = cmdArray.compactMap { $0.string }.joined(separator: " ")
                            modeBindings.append((key: key, command: cmdString))
                        }
                    }
                    keyBindings.append((mode: modeName, bindings: modeBindings))
                }
            }
        }
    }
    
    private func extractAllWorkspaces(from toml: TOMLTable) {
        var workspaceSet = Set<String>()
        
        // Add workspaces from assignments
        for assignment in workspaceAssignments {
            workspaceSet.insert(assignment.workspaceName)
        }
        
        // Extract workspaces from keybindings
        if let modes = toml["mode"]?.table {
            for (_, modeTable) in modes {
                if let bindings = modeTable.table?["binding"]?.table {
                    for (_, command) in bindings {
                        let cmdString: String
                        if let str = command.string {
                            cmdString = str
                        } else if let cmdArray = command.array {
                            cmdString = cmdArray.compactMap { $0.string }.joined(separator: " ")
                        } else {
                            continue
                        }
                        
                        // Look for workspace commands
                        let components = cmdString.split(separator: " ").map { String($0) }
                        if components.count >= 2 {
                            if components[0] == "workspace" || 
                               components[0] == "move-node-to-workspace" ||
                               components[0] == "move-workspace-to-monitor" {
                                let workspace = components[1]
                                // Validate workspace name
                                if case .success = WorkspaceName.parse(workspace) {
                                    workspaceSet.insert(workspace)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        allWorkspaces = Array(workspaceSet).sorted()
    }
    
    func saveConfiguration() async {
        errorMessage = nil
        
        do {
            // Create new TOML table with updated values
            var tomlTable = originalTomlTable ?? TOMLTable()
            
            // Update general settings
            tomlTable["start-at-login"] = startAtLogin
            tomlTable["automatically-unhide-macos-hidden-apps"] = automaticallyUnhideMacosHiddenApps
            tomlTable["default-root-container-layout"] = defaultRootContainerLayout
            tomlTable["default-root-container-orientation"] = defaultRootContainerOrientation
            tomlTable["accordion-padding"] = accordionPadding
            tomlTable["enable-normalization-flatten-containers"] = enableNormalizationFlattenContainers
            tomlTable["enable-normalization-opposite-orientation-for-nested-containers"] = enableNormalizationOppositeOrientation
            tomlTable["auto-move-workspaces-on-monitor-connect"] = autoMoveWorkspacesOnMonitorConnect
            
            // Update gaps
            if tomlTable["gaps"] == nil {
                tomlTable["gaps"] = TOMLTable()
            }
            if let gaps = tomlTable["gaps"] as? TOMLTable {
                if gaps["inner"] == nil {
                    gaps["inner"] = TOMLTable()
                }
                if let inner = gaps["inner"] as? TOMLTable {
                    inner["horizontal"] = innerGaps
                    inner["vertical"] = innerGaps
                    gaps["inner"] = inner
                }
                
                if gaps["outer"] == nil {
                    gaps["outer"] = TOMLTable()
                }
                if let outer = gaps["outer"] as? TOMLTable {
                    outer["top"] = outerGapsTop
                    outer["bottom"] = outerGapsBottom
                    outer["left"] = outerGapsLeft
                    outer["right"] = outerGapsRight
                    gaps["outer"] = outer
                }
                tomlTable["gaps"] = gaps
            }
            
            // Update workspace assignments
            var regularAssignments = TOMLTable()
            var forceAssignments = TOMLTable()
            
            for assignment in workspaceAssignments {
                switch assignment.monitorType {
                case .name(let name):
                    if assignment.isForceAssignment {
                        forceAssignments[assignment.workspaceName] = name
                    } else {
                        regularAssignments[assignment.workspaceName] = name
                    }
                case .index(let index):
                    if assignment.isForceAssignment {
                        forceAssignments[assignment.workspaceName] = index
                    } else {
                        regularAssignments[assignment.workspaceName] = index
                    }
                case .fingerprint(let fp):
                    let fpTable = TOMLTable()
                    if let vendorId = fp.vendorId { fpTable["vendor_id"] = vendorId }
                    if let modelId = fp.modelId { fpTable["model_id"] = modelId }
                    if let serial = fp.serialNumber { fpTable["serial_number"] = serial }
                    if let name = fp.displayName { fpTable["display_name"] = name }
                    if let width = fp.width { fpTable["width"] = width }
                    if let height = fp.height { fpTable["height"] = height }
                    
                    let wrapper = TOMLTable()
                    wrapper["fingerprint"] = fpTable
                    
                    if assignment.isForceAssignment {
                        forceAssignments[assignment.workspaceName] = wrapper
                    } else {
                        regularAssignments[assignment.workspaceName] = wrapper
                    }
                }
            }
            
            // All workspace assignments go under workspace-to-monitor-force-assignment
            // The UI tracks regular vs force, but config only has one key
            let allAssignments = TOMLTable()
            
            for assignment in workspaceAssignments {
                switch assignment.monitorType {
                case .name(let name):
                    allAssignments[assignment.workspaceName] = name
                case .index(let index):
                    allAssignments[assignment.workspaceName] = index
                case .fingerprint(let fp):
                    let fpTable = TOMLTable()
                    if let vendorId = fp.vendorId { fpTable["vendor_id"] = vendorId }
                    if let modelId = fp.modelId { fpTable["model_id"] = modelId }
                    if let serial = fp.serialNumber { fpTable["serial_number"] = serial }
                    if let name = fp.displayName { fpTable["display_name"] = name }
                    if let width = fp.width { fpTable["width"] = width }
                    if let height = fp.height { fpTable["height"] = height }
                    
                    let wrapper = TOMLTable()
                    wrapper["fingerprint"] = fpTable
                    allAssignments[assignment.workspaceName] = wrapper
                }
            }
            
            // Set the workspace assignments (only valid key)
            tomlTable["workspace-to-monitor-force-assignment"] = allAssignments
            
            // Debug: Print what we're about to save
            print("[DEBUG] Workspace assignments being saved:")
            for (key, value) in allAssignments {
                print("[DEBUG]   \(key): \(value)")
            }
            
            // Write to file
            guard let configPath = configFilePath else {
                throw ConfigError.noConfigFile
            }
            
            // Backup existing file
            let backupPath = configPath + ".backup"
            try FileManager.default.copyItem(atPath: configPath, toPath: backupPath)
            
            // Write new configuration
            let tomlString = serializeTomlWithInlineTables(tomlTable)
            print("[DEBUG] Saving TOML configuration to: \(configPath)")
            print("[DEBUG] TOML content preview (first 500 chars): \(String(tomlString.prefix(500)))")
            try tomlString.write(toFile: configPath, atomically: true, encoding: .utf8)
            
            // Reload configuration
            _ = reloadConfig()
            
            hasUnsavedChanges = false
            
            // Clean up backup
            try? FileManager.default.removeItem(atPath: backupPath)
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
        }
    }
    
    func revertChanges() {
        Task {
            await loadConfiguration()
        }
    }
    
    func markAsModified() {
        hasUnsavedChanges = true
    }
    
    // Helper function to match monitor fingerprints comprehensively
    func matchesFingerprint(_ monitor: MonitorInfo, _ fingerprint: WorkspaceAssignment.MonitorFingerprint) -> Bool {
        // Check display name match (highest priority)
        if let fpDisplayName = fingerprint.displayName {
            let monDisplayName = monitor.fingerprint.displayName
            if fpDisplayName.localizedCaseInsensitiveCompare(monDisplayName) != .orderedSame {
                return false
            }
        }
        
        // Check resolution match
        if let fpWidth = fingerprint.width, let fpHeight = fingerprint.height {
            if fpWidth != monitor.fingerprint.widthPixels || fpHeight != monitor.fingerprint.heightPixels {
                return false
            }
        }
        
        // Check vendor/model if available
        if let fpVendorId = fingerprint.vendorId, !fpVendorId.isEmpty,
           let monVendorId = monitor.fingerprint.vendorId {
            if fpVendorId != monVendorId {
                return false
            }
        }
        
        if let fpModelId = fingerprint.modelId, !fpModelId.isEmpty,
           let monModelId = monitor.fingerprint.modelId {
            if fpModelId != monModelId {
                return false
            }
        }
        
        // If we have a display name match, that's sufficient
        if fingerprint.displayName != nil {
            return true
        }
        
        // Otherwise require at least one matching field
        return (fingerprint.vendorId != nil && fingerprint.vendorId == monitor.fingerprint.vendorId) ||
               (fingerprint.modelId != nil && fingerprint.modelId == monitor.fingerprint.modelId) ||
               (fingerprint.width != nil && fingerprint.width == monitor.fingerprint.widthPixels &&
                fingerprint.height != nil && fingerprint.height == monitor.fingerprint.heightPixels)
    }
    
    func addWorkspaceAssignment() {
        let newAssignment = WorkspaceAssignment(
            workspaceName: findNextAvailableWorkspaceName(),
            monitorDescription: "main",
            monitorType: .name("main")
        )
        workspaceAssignments.append(newAssignment)
        markAsModified()
    }
    
    func removeWorkspaceAssignment(at index: Int) {
        guard index < workspaceAssignments.count else { return }
        workspaceAssignments.remove(at: index)
        markAsModified()
    }
    
    private func findNextAvailableWorkspaceName() -> String {
        let existingNames = Set(workspaceAssignments.map { $0.workspaceName })
        var counter = 1
        while existingNames.contains(String(counter)) {
            counter += 1
        }
        return String(counter)
    }
    
    func loadConnectedMonitors() {
        connectedMonitors = sortedMonitors.enumerated().compactMap { (index, monitor) in
            if let lazyMonitor = monitor as? LazyMonitor,
               let fp = lazyMonitor.fingerprint {
                print("[DEBUG] Loading monitor '\(monitor.name)' with fingerprint displayName: '\(fp.displayName ?? "nil")'")
                return MonitorInfo(
                    name: monitor.name,
                    index: index + 1,
                    fingerprint: MonitorInfo.MonitorFingerprint(
                        vendorId: fp.vendorID.map { String(format: "0x%04X", $0) },
                        modelId: fp.modelID.map { String(format: "0x%04X", $0) },
                        serialNumber: fp.serialNumber,
                        displayName: fp.displayName ?? monitor.name,
                        widthPixels: fp.widthPixels ?? Int(monitor.width),
                        heightPixels: fp.heightPixels ?? Int(monitor.height)
                    ),
                    isMain: monitor.rect.minX == 0 && monitor.rect.minY == 0,
                    width: Int(monitor.width),
                    height: Int(monitor.height),
                    positionX: monitor.rect.minX,
                    positionY: monitor.rect.minY
                )
            }
            return nil
        }
    }
    
    func addWorkspaceAssignment(forMonitor monitor: MonitorInfo? = nil, isForce: Bool = false) {
        var newAssignment = WorkspaceAssignment(
            workspaceName: findNextAvailableWorkspaceName(),
            monitorDescription: monitor?.name ?? "main",
            monitorType: .name(monitor?.name ?? "main"),
            isForceAssignment: isForce
        )
        
        if let monitor = monitor {
            // Create fingerprint from the selected monitor
            newAssignment.monitorType = .fingerprint(WorkspaceAssignment.MonitorFingerprint(
                vendorId: monitor.fingerprint.vendorId,
                modelId: monitor.fingerprint.modelId,
                serialNumber: monitor.fingerprint.serialNumber,
                displayName: monitor.fingerprint.displayName,
                width: monitor.fingerprint.widthPixels,
                height: monitor.fingerprint.heightPixels
            ))
            newAssignment.monitorDescription = monitor.name
        }
        
        workspaceAssignments.append(newAssignment)
        markAsModified()
    }
    
    // Workspace management methods
    func addWorkspace(_ workspace: String) {
        if !allWorkspaces.contains(workspace) {
            allWorkspaces.append(workspace)
            allWorkspaces.sort()
            markAsModified()
        }
    }
    
    func removeWorkspace(_ workspace: String) {
        allWorkspaces.removeAll { $0 == workspace }
        workspaceAssignments.removeAll { $0.workspaceName == workspace }
        markAsModified()
    }
    
    func updateWorkspaceAssignment(workspace: String, assignment: WorkspaceAssignment?) {
        // Remove existing assignment for this workspace
        workspaceAssignments.removeAll { $0.workspaceName == workspace }
        
        // Add new assignment if provided
        if let assignment = assignment {
            workspaceAssignments.append(assignment)
        }
        
        markAsModified()
    }
    
    enum ConfigError: LocalizedError {
        case noConfigFile
        
        var errorDescription: String? {
            switch self {
            case .noConfigFile:
                return "No configuration file path available"
            }
        }
    }
    
    // Helper method to serialize TOML with proper inline table formatting for workspace assignments
    private func serializeTomlWithInlineTables(_ tomlTable: TOMLTable) -> String {
        // For now, just use the default serialization
        // The issue is that we need to convert the result to use inline tables for workspace assignments
        let defaultSerialization = String(describing: tomlTable)
        
        // Post-process to convert workspace assignment nested tables to inline format
        return convertWorkspaceAssignmentsToInlineFormat(defaultSerialization)
    }
    
    private func convertWorkspaceAssignmentsToInlineFormat(_ tomlString: String) -> String {
        var lines = tomlString.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0
        
        while i < lines.count {
            let line = lines[i]
            
            // Check if this is a workspace assignment nested table
            if line.matches(regex: #"^\[workspace-to-monitor-force-assignment\.(.+)\.fingerprint\]$"#) {
                // Extract workspace name
                let workspaceMatch = line.replacingOccurrences(of: "[workspace-to-monitor-force-assignment.", with: "")
                    .replacingOccurrences(of: ".fingerprint]", with: "")
                
                // Collect fingerprint properties
                var fingerprintProps: [String] = []
                i += 1
                while i < lines.count && !lines[i].starts(with: "[") && !lines[i].isEmpty {
                    let propLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if !propLine.isEmpty {
                        fingerprintProps.append(propLine)
                    }
                    i += 1
                }
                
                // Only add the header once
                if !result.contains("[workspace-to-monitor-force-assignment]") {
                    if !result.isEmpty && !result.last!.isEmpty {
                        result.append("")
                    }
                    result.append("[workspace-to-monitor-force-assignment]")
                }
                
                // Format as inline table
                let propsString = fingerprintProps.joined(separator: ", ")
                result.append("\(workspaceMatch) = { fingerprint = { \(propsString) } }")
                
                // Back up one since the outer loop will increment
                i -= 1
            } else {
                result.append(line)
            }
            
            i += 1
        }
        
        return result.joined(separator: "\n")
    }
    
}

extension String {
    func matches(regex: String) -> Bool {
        return self.range(of: regex, options: .regularExpression) != nil
    }
}