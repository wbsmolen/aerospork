import SwiftUI
import Common
import AppKit

struct EnhancedWorkspaceAssignmentTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var selectedWorkspaceId: UUID?
    @State private var showingMonitorSelection = false
    @State private var editingAssignment: ConfigurationViewModel.WorkspaceAssignment?
    @State private var selectedTab = "workspaces"
    @State private var newWorkspaceName = ""
    @State private var showingAddWorkspace = false
    
    // Common workspace names from config
    let commonWorkspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Workspaces").tag("workspaces")
                Text("Monitor Assignments").tag("assignments")
                Text("Connected Monitors").tag("monitors")
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            Divider()
            
            // Tab content
            switch selectedTab {
            case "workspaces":
                workspaceManagementView
            case "assignments":
                assignmentView
            case "monitors":
                monitorView
            default:
                EmptyView()
            }
        }
    }
    
    var workspaceManagementView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Workspace Configuration")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddWorkspace = true }) {
                    Image(systemName: "plus")
                }
                .help("Add new workspace")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            // Workspace list
            List {
                ForEach(viewModel.allWorkspaces, id: \.self) { workspace in
                    WorkspaceConfigRow(
                        workspace: workspace,
                        assignment: viewModel.workspaceAssignments.first { $0.workspaceName == workspace },
                        monitors: viewModel.connectedMonitors,
                        onUpdate: { assignment in
                            viewModel.updateWorkspaceAssignment(workspace: workspace, assignment: assignment)
                        }
                    )
                }
                .onDelete { indices in
                    // Handle workspace deletion
                    let workspacesToDelete = indices.map { viewModel.allWorkspaces[$0] }
                    workspacesToDelete.forEach { workspace in
                        viewModel.removeWorkspace(workspace)
                    }
                }
            }
            .listStyle(InsetListStyle())
        }
        .sheet(isPresented: $showingAddWorkspace) {
            AddWorkspaceView(
                commonWorkspaces: commonWorkspaces.filter { !viewModel.allWorkspaces.contains($0) },
                onAdd: { workspace in
                    viewModel.addWorkspace(workspace)
                    showingAddWorkspace = false
                }
            )
        }
    }
    
    var assignmentView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Monitor Assignments")
                    .font(.headline)
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
                    .cornerRadius(4)
                Spacer()
            }
            .padding()
            
            // Assignment list
            List(selection: $selectedWorkspaceId) {
                ForEach(viewModel.workspaceAssignments) { assignment in
                    EnhancedWorkspaceAssignmentRow(
                        assignment: assignment,
                        monitors: viewModel.connectedMonitors,
                        onEdit: { editingAssignment = assignment },
                        onChange: { viewModel.markAsModified() }
                    )
                    .tag(assignment.id)
                }
                .onDelete { indices in
                    deleteAssignments(at: indices)
                }
            }
            .listStyle(InsetListStyle())
            
            // Bottom toolbar
            HStack {
                    Menu {
                        Button("Add Regular Assignment") {
                            viewModel.addWorkspaceAssignment(isForce: false)
                        }
                        Button("Add Force Assignment") {
                            viewModel.addWorkspaceAssignment(isForce: true)
                        }
                        Divider()
                        ForEach(viewModel.connectedMonitors) { monitor in
                            Menu("Assign to \(monitor.name)") {
                                Button("Regular Assignment") {
                                    viewModel.addWorkspaceAssignment(forMonitor: monitor, isForce: false)
                                }
                                Button("Force Assignment") {
                                    viewModel.addWorkspaceAssignment(forMonitor: monitor, isForce: true)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .help("Add workspace assignment")
                    
                    Button(action: {
                        if let selectedId = selectedWorkspaceId,
                           let index = viewModel.workspaceAssignments.firstIndex(where: { $0.id == selectedId }) {
                            viewModel.removeWorkspaceAssignment(at: index)
                            selectedWorkspaceId = nil
                        }
                    }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(selectedWorkspaceId == nil)
                    .help("Remove selected workspace assignment")
                    
                    Spacer()
                    
                    Text("\(viewModel.workspaceAssignments.count) assignments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 400)
        .sheet(item: $editingAssignment) { assignment in
            MonitorSelectionView(
                assignment: assignment,
                monitors: viewModel.connectedMonitors,
                onSave: { updatedAssignment in
                    if let index = viewModel.workspaceAssignments.firstIndex(where: { $0.id == assignment.id }) {
                        viewModel.workspaceAssignments[index] = updatedAssignment
                        viewModel.markAsModified()
                    }
                }
            )
        }
    }
    
    var monitorView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Connected Monitors")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            // Monitor preview
            MonitorPreviewPanel(monitors: viewModel.connectedMonitors)
                .frame(minHeight: 300)
                .padding()
            
            // Monitor details
            if !viewModel.connectedMonitors.isEmpty {
                ScrollView {
                    MonitorDetailsView(monitors: viewModel.connectedMonitors)
                        .padding()
                }
            }
            
            Spacer()
        }
    }
    
    private func deleteAssignments(at offsets: IndexSet) {
        let idsToDelete = offsets.map { viewModel.workspaceAssignments[$0].id }
        viewModel.workspaceAssignments.removeAll { assignment in
            idsToDelete.contains(assignment.id)
        }
        viewModel.markAsModified()
    }
}

struct EnhancedWorkspaceAssignmentRow: View {
    let assignment: ConfigurationViewModel.WorkspaceAssignment
    let monitors: [ConfigurationViewModel.MonitorInfo]
    let onEdit: () -> Void
    let onChange: () -> Void
    
    var body: some View {
        HStack {
            // Assignment type indicator
            Circle()
                .fill(assignment.isForceAssignment ? Color.orange : Color.blue)
                .frame(width: 8, height: 8)
                .help(assignment.isForceAssignment ? "Force assignment - workspace always returns to this monitor" : "Regular assignment - workspace moves on first detection")
            
            // Workspace name
            Text(assignment.workspaceName)
                .fontWeight(.medium)
                .frame(width: 60, alignment: .leading)
            
            Text("→")
                .foregroundColor(.secondary)
            
            // Monitor description
            VStack(alignment: .leading, spacing: 2) {
                Text(monitorDisplayName)
                    .lineLimit(1)
                
                if case .fingerprint(let fp) = assignment.monitorType {
                    Text(fingerprintSummary(fp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button("Edit") {
                onEdit()
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }
    
    private var monitorDisplayName: String {
        switch assignment.monitorType {
        case .name(let name):
            return name
        case .index(let index):
            return "Monitor \(index)"
        case .fingerprint(let fp):
            // Try to match with connected monitor
            if let monitor = monitors.first(where: { matchesFingerprint($0, fp) }) {
                return monitor.name
            }
            return fp.displayName ?? "Custom Fingerprint"
        }
    }
    
    private func matchesFingerprint(_ monitor: ConfigurationViewModel.MonitorInfo, _ fp: ConfigurationViewModel.WorkspaceAssignment.MonitorFingerprint) -> Bool {
        // Match by display name first (most reliable)
        if let fpDisplayName = fp.displayName {
            let monDisplayName = monitor.fingerprint.displayName
            if fpDisplayName.localizedCaseInsensitiveCompare(monDisplayName) == .orderedSame {
                // Also check resolution if available
                if let fpWidth = fp.width, let fpHeight = fp.height {
                    return fpWidth == monitor.fingerprint.widthPixels &&
                           fpHeight == monitor.fingerprint.heightPixels
                }
                return true
            }
            return false  // Display names don't match
        }
        
        // Fall back to vendor/model/serial matching
        let vendorMatch = fp.vendorId == nil || fp.vendorId == monitor.fingerprint.vendorId
        let modelMatch = fp.modelId == nil || fp.modelId == monitor.fingerprint.modelId
        let serialMatch = fp.serialNumber == nil || fp.serialNumber == monitor.fingerprint.serialNumber
        
        // Also check resolution
        let resolutionMatch = (fp.width == nil && fp.height == nil) ||
                              (fp.width == monitor.fingerprint.widthPixels && fp.height == monitor.fingerprint.heightPixels)
        
        return vendorMatch && modelMatch && serialMatch && resolutionMatch
    }
    
    private func fingerprintSummary(_ fp: ConfigurationViewModel.WorkspaceAssignment.MonitorFingerprint) -> String {
        var parts: [String] = []
        if let vendor = fp.vendorId { parts.append("V:\(vendor)") }
        if let model = fp.modelId { parts.append("M:\(model)") }
        if let serial = fp.serialNumber { parts.append("S:\(serial)") }
        if let width = fp.width, let height = fp.height {
            parts.append("\(width)×\(height)")
        }
        return parts.joined(separator: " ")
    }
}

struct MonitorPreviewPanel: View {
    let monitors: [ConfigurationViewModel.MonitorInfo]
    
    var body: some View {
        GeometryReader { geometry in
            if monitors.isEmpty {
                VStack {
                    Image(systemName: "display")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No monitors detected")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let layout = calculateLayout(in: geometry.size)
                ZStack {
                    ForEach(monitors) { monitor in
                        MonitorPreview(
                            monitor: monitor,
                            scale: layout.scale,
                            offset: layout.offset
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func calculateLayout(in size: CGSize) -> (scale: CGFloat, offset: CGPoint) {
        guard !monitors.isEmpty else { return (1.0, CGPoint.zero) }
        
        // Calculate bounds of all monitors
        let minX = monitors.map { $0.positionX }.min() ?? 0
        let minY = monitors.map { $0.positionY }.min() ?? 0
        let maxX = monitors.map { $0.positionX + CGFloat($0.width) }.max() ?? 0
        let maxY = monitors.map { $0.positionY + CGFloat($0.height) }.max() ?? 0
        
        let totalWidth = maxX - minX
        let totalHeight = maxY - minY
        
        // Calculate scale to fit with padding
        let padding: CGFloat = 40
        let scaleX = (size.width - padding * 2) / totalWidth
        let scaleY = (size.height - padding * 2) / totalHeight
        let scale = min(scaleX, scaleY, 0.3)
        
        // Calculate offset to center the monitors
        let scaledWidth = totalWidth * scale
        let scaledHeight = totalHeight * scale
        let offsetX = (size.width - scaledWidth) / 2 - minX * scale
        let offsetY = (size.height - scaledHeight) / 2 - minY * scale
        
        return (scale, CGPoint(x: offsetX, y: offsetY))
    }
}

struct MonitorPreview: View {
    let monitor: ConfigurationViewModel.MonitorInfo
    let scale: CGFloat
    let offset: CGPoint
    
    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4)
                .fill(monitor.isMain ? Color.blue.opacity(0.3) : Color.gray.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(monitor.isMain ? Color.blue : Color.gray, lineWidth: 2)
                )
                .frame(
                    width: CGFloat(monitor.width) * scale,
                    height: CGFloat(monitor.height) * scale
                )
            
            Text(monitor.name)
                .font(.caption)
                .lineLimit(1)
        }
        .position(
            x: monitor.positionX * scale + CGFloat(monitor.width) * scale / 2 + offset.x,
            y: monitor.positionY * scale + CGFloat(monitor.height) * scale / 2 + offset.y
        )
    }
}

struct MonitorDetailsView: View {
    let monitors: [ConfigurationViewModel.MonitorInfo]
    @State private var selectedMonitorId: UUID?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitor Details")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            ForEach(monitors) { monitor in
                MonitorDetailRow(
                    monitor: monitor,
                    isSelected: selectedMonitorId == monitor.id,
                    onTap: { selectedMonitorId = monitor.id }
                )
            }
        }
    }
}

struct MonitorDetailRow: View {
    let monitor: ConfigurationViewModel.MonitorInfo
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: monitor.isMain ? "star.fill" : "display")
                    .foregroundColor(monitor.isMain ? .yellow : .secondary)
                Text(monitor.name)
                    .fontWeight(.medium)
                Spacer()
                Text("\(monitor.width)×\(monitor.height)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(monitor.fingerprint.displayString)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Color.secondary)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            onTap()
        }
    }
}

struct WorkspaceConfigRow: View {
    let workspace: String
    let assignment: ConfigurationViewModel.WorkspaceAssignment?
    let monitors: [ConfigurationViewModel.MonitorInfo]
    let onUpdate: (ConfigurationViewModel.WorkspaceAssignment?) -> Void
    
    @State private var selectedMonitorIndex: Int
    @State private var isForceAssignment: Bool
    
    init(workspace: String, assignment: ConfigurationViewModel.WorkspaceAssignment?, monitors: [ConfigurationViewModel.MonitorInfo], onUpdate: @escaping (ConfigurationViewModel.WorkspaceAssignment?) -> Void) {
        self.workspace = workspace
        self.assignment = assignment
        self.monitors = monitors
        self.onUpdate = onUpdate
        
        // Initialize state
        if let assignment = assignment {
            self._isForceAssignment = State(initialValue: assignment.isForceAssignment)
            print("[DEBUG] WorkspaceConfigRow init for workspace '\(workspace)' with assignment to '\(assignment.monitorDescription)'")
            // Find monitor index
            if let index = monitors.firstIndex(where: { monitor in
                switch assignment.monitorType {
                case .fingerprint(let fp):
                    // Match by display name first (most reliable)
                    if let fpDisplayName = fp.displayName {
                        let monDisplayName = monitor.fingerprint.displayName
                        if fpDisplayName.localizedCaseInsensitiveCompare(monDisplayName) == .orderedSame {
                            // Also check resolution if available
                            if let fpWidth = fp.width, let fpHeight = fp.height {
                                return fpWidth == monitor.fingerprint.widthPixels &&
                                       fpHeight == monitor.fingerprint.heightPixels
                            }
                            return true
                        }
                    }
                    // Fall back to vendor/model matching if available
                    if let fpVendor = fp.vendorId, !fpVendor.isEmpty,
                       let fpModel = fp.modelId, !fpModel.isEmpty {
                        return monitor.fingerprint.vendorId == fpVendor &&
                               monitor.fingerprint.modelId == fpModel
                    }
                    // Match by resolution only as last resort
                    if let fpWidth = fp.width, let fpHeight = fp.height {
                        return fpWidth == monitor.fingerprint.widthPixels &&
                               fpHeight == monitor.fingerprint.heightPixels
                    }
                    return false
                default:
                    return false
                }
            }) {
                print("[DEBUG] Found monitor at index \(index): '\(monitors[index].name)' for workspace '\(workspace)'")
                self._selectedMonitorIndex = State(initialValue: index + 1)
            } else {
                print("[DEBUG] No monitor found for workspace '\(workspace)'")
                self._selectedMonitorIndex = State(initialValue: 0)
            }
        } else {
            self._selectedMonitorIndex = State(initialValue: 0)
            self._isForceAssignment = State(initialValue: false)
        }
    }
    
    var body: some View {
        HStack {
            Text("Workspace \(workspace)")
                .frame(width: 120, alignment: .leading)
            
            Picker("Monitor", selection: $selectedMonitorIndex) {
                Text("None").tag(0)
                ForEach(Array(monitors.enumerated()), id: \.offset) { index, monitor in
                    Text(monitor.name).tag(index + 1)
                }
            }
            .frame(width: 200)
            .onChange(of: selectedMonitorIndex) { _ in
                updateAssignment()
            }
            
            Toggle("Force", isOn: $isForceAssignment)
                .help("Force assignment: workspace always returns to this monitor")
                .onChange(of: isForceAssignment) { _ in
                    updateAssignment()
                }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    private func updateAssignment() {
        if selectedMonitorIndex == 0 {
            onUpdate(nil)
        } else if let monitor = monitors[safe: selectedMonitorIndex - 1] {
            let assignment = ConfigurationViewModel.WorkspaceAssignment(
                workspaceName: workspace,
                monitorDescription: monitor.name,
                monitorType: .fingerprint(ConfigurationViewModel.WorkspaceAssignment.MonitorFingerprint(
                    vendorId: monitor.fingerprint.vendorId,
                    modelId: monitor.fingerprint.modelId,
                    serialNumber: monitor.fingerprint.serialNumber,
                    displayName: monitor.fingerprint.displayName,
                    width: monitor.fingerprint.widthPixels,
                    height: monitor.fingerprint.heightPixels
                )),
                isForceAssignment: isForceAssignment
            )
            onUpdate(assignment)
        }
    }
}

struct AddWorkspaceView: View {
    let commonWorkspaces: [String]
    let onAdd: (String) -> Void
    
    @State private var customWorkspace = ""
    @State private var errorMessage = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Workspace")
                .font(.headline)
            
            if !commonWorkspaces.isEmpty {
                VStack(alignment: .leading) {
                    Text("Common Workspaces:")
                        .font(.subheadline)
                    
                    FlowLayout(items: commonWorkspaces, onTap: onAdd)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading) {
                Text("Custom Workspace:")
                    .font(.subheadline)
                
                HStack {
                    TextField("Enter workspace name", text: $customWorkspace)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            addCustomWorkspace()
                        }
                    
                    Button("Add") {
                        addCustomWorkspace()
                    }
                    .disabled(customWorkspace.isEmpty)
                }
                
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
    
    private func addCustomWorkspace() {
        let result = WorkspaceName.parse(customWorkspace)
        switch result {
        case .success:
            onAdd(customWorkspace)
        case .failure(let error):
            errorMessage = error
        }
    }
}

// Simple flow layout for workspace buttons
struct FlowLayout: View {
    let items: [String]
    let onTap: (String) -> Void
    let spacing: CGFloat = 8
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(items.chunked(into: 5)), id: \.self) { rowItems in
                HStack(spacing: spacing) {
                    ForEach(rowItems, id: \.self) { item in
                        Button(item) {
                            onTap(item)
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                }
            }
        }
    }
}

// Helper extension to chunk arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}