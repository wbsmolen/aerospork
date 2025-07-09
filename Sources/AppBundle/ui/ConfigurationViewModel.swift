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
    @Published var workspaceAssignments: [Config.WorkspaceAssignment] = []
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
            
            // Load workspace assignments directly from TOML
            workspaceAssignments = []
            print("[DEBUG] Loading workspace assignments from TOML")
            
            if let wsAssignments = tomlTable["workspace-to-monitor-force-assignment"]?.table {
                print("[DEBUG] Found workspace-to-monitor-force-assignment with \(wsAssignments.count) entries")
                for (workspace, value) in wsAssignments {
                    print("[DEBUG] Processing workspace '\(workspace)' with value type: \(type(of: value))")
                    
                    // Parse the monitor assignment
                    if let stringValue = value.string {
                        // Simple string like "main" or "secondary"
                        let assignment = Config.WorkspaceAssignment(
                            workspaceName: workspace,
                            monitorDescription: stringValue,
                            monitorType: .name(stringValue),
                            isForceAssignment: true
                        )
                        workspaceAssignments.append(assignment)
                        print("[DEBUG] Added assignment for workspace \(workspace) to monitor \(stringValue)")
                    } else if let tableValue = value.table, let fingerprintTable = tableValue["fingerprint"]?.table {
                        // Fingerprint format
                        let displayName = fingerprintTable["display_name"]?.string ?? "Unknown"
                        let width = fingerprintTable["width"]?.int
                        let height = fingerprintTable["height"]?.int
                        
                        let fingerprint = Config.WorkspaceAssignment.MonitorFingerprint(
                            vendorId: fingerprintTable["vendor_id"]?.string,
                            modelId: fingerprintTable["model_id"]?.string,
                            serialNumber: fingerprintTable["serial_number"]?.string,
                            displayName: displayName,
                            width: width,
                            height: height
                        )
                        
                        let assignment = Config.WorkspaceAssignment(
                            workspaceName: workspace,
                            monitorDescription: displayName,
                            monitorType: .fingerprint(fingerprint),
                            isForceAssignment: true
                        )
                        workspaceAssignments.append(assignment)
                        print("[DEBUG] Added fingerprint assignment for workspace \(workspace) to monitor \(displayName)")
                    } else if let intValue = value.int {
                        // Sequence number
                        let assignment = Config.WorkspaceAssignment(
                            workspaceName: workspace,
                            monitorDescription: "Monitor \(intValue)",
                            monitorType: .index(intValue),
                            isForceAssignment: true
                        )
                        workspaceAssignments.append(assignment)
                        print("[DEBUG] Added assignment for workspace \(workspace) to monitor index \(intValue)")
                    }
                }
            } else {
                print("[DEBUG] No workspace-to-monitor-force-assignment found in TOML")
            }
            
            // Sort assignments by workspace name for consistent display
            workspaceAssignments.sort { $0.workspaceName < $1.workspaceName }
            print("[DEBUG] Loaded \(workspaceAssignments.count) total workspace assignments")
            
            // Load current monitor information
            loadConnectedMonitors()
            
            // Load key bindings for display
            loadKeyBindings(from: tomlTable)
            
            // Extract all workspace names from keybindings and assignments
            extractAllWorkspaces(from: tomlTable)
            
            hasUnsavedChanges = false
            print("[DEBUG] Configuration loaded successfully with \(workspaceAssignments.count) assignments")
        } catch {
            errorMessage = "Failed to load configuration: \(error.localizedDescription)"
            print("[DEBUG] Error loading configuration: \(error)")
        }
        
        isLoading = false
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
            
            // Update workspace-to-monitor-force-assignment from assignments
            var newAssignments: [String: [MonitorDescription]] = [:]
            for assignment in workspaceAssignments where assignment.isForceAssignment {
                let monitorDesc = convertAssignmentToMonitorDescription(assignment)
                newAssignments[assignment.workspaceName] = [monitorDesc]
            }
            config.workspaceToMonitorForceAssignment = newAssignments
            
            // Update TOML table
            var assignmentTable = TOMLTable()
            for (workspace, descriptions) in newAssignments {
                if let desc = descriptions.first {
                    assignmentTable[workspace] = createTOMLValueForMonitorDescription(desc)
                }
            }
            tomlTable["workspace-to-monitor-force-assignment"] = assignmentTable
            
            // Write to file
            guard let configPath = configFilePath else {
                throw ConfigError.noConfigFile
            }
            
            // Backup existing file
            let backupPath = configPath + ".backup"
            try FileManager.default.copyItem(atPath: configPath, toPath: backupPath)
            
            // Write new configuration
            let tomlString = serializeTomlWithInlineTables(tomlTable)
            print("[DEBUG] Saving configuration to: \(configPath)")
            print("[DEBUG] Saving \(workspaceAssignments.count) workspace assignments")
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
    
    // Helper functions for converting MonitorDescription to assignment format
    private func descriptionString(for desc: MonitorDescription) -> String {
        switch desc {
        case .main:
            return "main"
        case .secondary:
            return "secondary"
        case .sequenceNumber(let num):
            return "Monitor \(num)"
        case .pattern(let name, _):
            return name
        case .fingerprint(let data):
            return data.displayNamePattern ?? "Fingerprint"
        }
    }
    
    private func convertMonitorDescription(_ desc: MonitorDescription) -> Config.WorkspaceAssignment.MonitorType {
        switch desc {
        case .main:
            return .name("main")
        case .secondary:
            return .name("secondary")
        case .sequenceNumber(let num):
            return .index(num)
        case .pattern(let name, _):
            return .name(name)
        case .fingerprint(let data):
            return .fingerprint(Config.WorkspaceAssignment.MonitorFingerprint(
                vendorId: data.vendorID.map { String(format: "0x%04X", $0) },
                modelId: data.modelID.map { String(format: "0x%04X", $0) },
                serialNumber: data.serialNumber,
                displayName: data.displayNamePattern,
                width: data.widthPixels,
                height: data.heightPixels
            ))
        }
    }
    
    // Helper function to match monitor fingerprints comprehensively
    func matchesFingerprint(_ monitor: MonitorInfo, _ fingerprint: Config.WorkspaceAssignment.MonitorFingerprint) -> Bool {
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
        let newAssignment = Config.WorkspaceAssignment(
            workspaceName: findNextAvailableWorkspaceName(),
            monitorDescription: "main",
            monitorType: .name("main"),
            isForceAssignment: true
        )
        print("[DEBUG] Adding new workspace assignment: \(newAssignment.workspaceName)")
        workspaceAssignments.append(newAssignment)
        objectWillChange.send()
        markAsModified()
    }
    
    func removeWorkspaceAssignment(at index: Int) {
        guard index < workspaceAssignments.count else { return }
        let removed = workspaceAssignments[index]
        print("[DEBUG] Removing workspace assignment: \(removed.workspaceName)")
        workspaceAssignments.remove(at: index)
        objectWillChange.send()
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
    
    func addWorkspaceAssignment(forMonitor monitor: MonitorInfo? = nil, isForce: Bool = true) {
        var newAssignment = Config.WorkspaceAssignment(
            workspaceName: findNextAvailableWorkspaceName(),
            monitorDescription: monitor?.name ?? "main",
            monitorType: .name(monitor?.name ?? "main"),
            isForceAssignment: isForce
        )
        
        if let monitor = monitor {
            // Create fingerprint from the selected monitor
            newAssignment.monitorType = .fingerprint(Config.WorkspaceAssignment.MonitorFingerprint(
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
    
    func updateWorkspaceAssignment(workspace: String, assignment: Config.WorkspaceAssignment?) {
        print("[DEBUG] Updating workspace assignment for: \(workspace)")
        // Remove existing assignment for this workspace
        workspaceAssignments.removeAll { $0.workspaceName == workspace }
        
        // Add new assignment if provided
        if let assignment = assignment {
            workspaceAssignments.append(assignment)
            print("[DEBUG] New assignment: \(assignment.monitorDescription)")
        }
        
        objectWillChange.send()
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
    
    private func convertAssignmentToMonitorDescription(_ assignment: Config.WorkspaceAssignment) -> MonitorDescription {
        switch assignment.monitorType {
        case .name(let name):
            if name == "main" {
                return .main
            } else if name == "secondary" {
                return .secondary
            } else {
                return .pattern(name, try! SendableRegex(name))
            }
        case .index(let index):
            return .sequenceNumber(index)
        case .fingerprint(let fp):
            let data = MonitorFingerprintPatternData(
                vendorID: fp.vendorId.flatMap { hexString in
                    let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
                    return UInt32(cleanHex, radix: 16)
                },
                modelID: fp.modelId.flatMap { hexString in
                    let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
                    return UInt32(cleanHex, radix: 16)
                },
                serialNumber: fp.serialNumber,
                displayNamePattern: fp.displayName,
                widthPixels: fp.width,
                heightPixels: fp.height
            )
            return .fingerprint(data)
        }
    }
    
    private func createTOMLValueForMonitorDescription(_ desc: MonitorDescription) -> any TOMLValueConvertible {
        switch desc {
        case .main:
            return "main"
        case .secondary:
            return "secondary"
        case .sequenceNumber(let num):
            return num
        case .pattern(let pattern, _):
            return pattern
        case .fingerprint(let data):
            let fingerprintTable = TOMLTable()
            if let displayName = data.displayNamePattern {
                fingerprintTable["display_name"] = displayName
            }
            if let width = data.widthPixels {
                fingerprintTable["width"] = TOMLInt(width)
            }
            if let height = data.heightPixels {
                fingerprintTable["height"] = TOMLInt(height)
            }
            if let vendorId = data.vendorID {
                fingerprintTable["vendor_id"] = String(format: "0x%04X", vendorId)
            }
            if let modelId = data.modelID {
                fingerprintTable["model_id"] = String(format: "0x%04X", modelId)
            }
            if let serial = data.serialNumber {
                fingerprintTable["serial_number"] = serial
            }
            
            let wrapper = TOMLTable()
            wrapper["fingerprint"] = fingerprintTable
            return wrapper
        }
    }
    
    private func convertWorkspaceAssignmentsToInlineFormat(_ tomlString: String) -> String {
        let lines = tomlString.components(separatedBy: "\n")
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