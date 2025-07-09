import SwiftUI
import Common
import AppKit

struct EnhancedWorkspaceAssignmentTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    
    @State private var newWorkspaceName = ""
    @State private var showingAddWorkspace = false
    @State private var isMonitorPreviewExpanded = true // New state variable

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                workspaceProfileManagementView // New section for profile management
                Divider()
                workspaceManagementView // Now displays assignments for the active profile
                Divider()
                monitorView
            }
            .padding()
        }
    }

    var workspaceProfileManagementView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workspace Profiles")
                    .font(.title2) // Slightly larger font for main section header
                    .fontWeight(.bold)
                Spacer()
                Button("Add Profile") {
                    viewModel.addWorkspaceProfile(name: "New Profile")
                }
                .help("Add a new workspace profile for different monitor setups (e.g., home, home office, external display).")
                
                Button("Remove Profile") {
                    if let activeProfileId = viewModel.activeProfileId {
                        viewModel.removeWorkspaceProfile(id: activeProfileId)
                    }
                }
                .disabled(viewModel.workspaceProfiles.count <= 1) // Don't allow deleting the last profile
                .help("Remove the currently selected workspace profile.")
            }
            .padding(.bottom, 5) // Add some space below the buttons
            
            VStack(alignment: .leading, spacing: 8) { // Group picker and name field
                Picker("Active Profile:", selection: Binding(
                    get: { viewModel.activeProfileId ?? UUID() },
                    set: { newId in
                        viewModel.activeProfileId = newId
                    }
                )) {
                    ForEach(viewModel.workspaceProfiles) { profile in
                        Text(profile.name).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
                .help("Select the active workspace profile. Each profile can have different workspace-to-monitor assignments.")
                
                HStack {
                    Text("Profile Name:")
                        .frame(width: 100, alignment: .leading) // Align label
                    TextField("Profile Name", text: Binding(
                        get: { viewModel.workspaceProfiles.first(where: { $0.id == viewModel.activeProfileId })?.name ?? "" },
                        set: { newName in
                            if let index = viewModel.workspaceProfiles.firstIndex(where: { $0.id == viewModel.activeProfileId }) {
                                viewModel.workspaceProfiles[index].name = newName
                                viewModel.markAsModified()
                            }
                        }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 250) // Slightly wider text field
                    .disabled(viewModel.activeProfileId == nil)
                }
            }
            
            Text("Use workspace profiles to manage different monitor setups, for example, one for your home desk and another for your office docking station. Each profile saves its own workspace-to-monitor assignments.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 10) // More padding above hint text
        }
        .padding(20) // Increased overall padding
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    var workspaceManagementView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header for the table
            HStack {
                Text("Workspace Name")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(width: 120, alignment: .leading)
                Text("Assigned Monitor")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(width: 200, alignment: .leading)
                Text("Force Assignment")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { viewModel.addWorkspaceAssignment() }) { // Changed to add assignment
                    Image(systemName: "plus")
                }
                .help("Add a new workspace assignment for the current profile.")
            }
            .padding(.horizontal, 15) // Consistent horizontal padding
            .padding(.vertical, 10) // Increased vertical padding
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Workspace list
            List {
                ForEach(viewModel.workspaceAssignments.indices, id: \.self) { index in
                    WorkspaceConfigRow(
                        workspace: viewModel.workspaceAssignments[index].workspaceName,
                        viewModel: viewModel
                    )
                }
                .onDelete { indices in
                    indices.forEach { index in
                        viewModel.removeWorkspaceAssignment(at: index)
                    }
                }
            }
            .listStyle(InsetListStyle())
        }
        // Removed .sheet for AddWorkspaceView as assignments are added directly
    }
    
    var monitorView: some View {
        VStack(alignment: .leading, spacing: 0) { // Changed alignment to .leading
            // Header
            HStack {
                Text("Connected Monitors")
                    .font(.headline)
                Spacer()
                Toggle(isOn: $isMonitorPreviewExpanded) { // Toggle to expand/collapse
                    Text("Show Preview")
                }
                .toggleStyle(.switch) // Use switch style for toggle
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            if isMonitorPreviewExpanded {
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
            } else {
                // Collapsed view: just list monitor names
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.connectedMonitors) { monitor in
                        Text(monitor.name)
                            .font(.body)
                    }
                }
                .padding()
            }
            
            Spacer()
        }
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
                if layout.scale < 0.05 { // Threshold for collapsing to simplified view
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(monitors) { monitor in
                            Text(monitor.name)
                                .font(.body)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
        let scale = min(scaleX, scaleY, 0.3) // Original max scale
        
        // Ensure a minimum scale to avoid extremely tiny previews
        let effectiveScale = max(scale, 0.01) // Minimum scale to prevent division by zero or too small rendering
        
        // Calculate offset to center the monitors
        let scaledWidth = totalWidth * effectiveScale
        let scaledHeight = totalHeight * effectiveScale
        let offsetX = (size.width - scaledWidth) / 2 - minX * effectiveScale
        let offsetY = (size.height - scaledHeight) / 2 - minY * effectiveScale
        
        return (effectiveScale, CGPoint(x: offsetX, y: offsetY))
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
    @ObservedObject var viewModel: ConfigurationViewModel
    
    @State private var selectedMonitorIndex: Int
    @State private var isForceAssignment: Bool
    
    init(workspace: String, viewModel: ConfigurationViewModel) {
        self.workspace = workspace
        self.viewModel = viewModel
        
        // Initialize state
        if let assignment = viewModel.workspaceAssignments.first(where: { $0.workspaceName == workspace }) {
            self._isForceAssignment = State(initialValue: assignment.isForceAssignment)
            print("[DEBUG] WorkspaceConfigRow init for workspace '\(workspace)' with assignment to '\(assignment.monitorDescription)'")
            // Find monitor index
            if let index = viewModel.connectedMonitors.firstIndex(where: { monitor in
                switch assignment.monitorType {
                case .name(let name):
                    return monitor.name == name
                case .index(let index):
                    return monitor.index == index
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
            }) {
                print("[DEBUG] Found monitor at index \(index): '\(viewModel.connectedMonitors[index].name)' for workspace '\(workspace)'")
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
                ForEach(Array(viewModel.connectedMonitors.enumerated()), id: \.offset) { index, monitor in
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
            viewModel.updateWorkspaceAssignment(workspace: workspace, assignment: nil)
        } else if let monitor = viewModel.connectedMonitors[safe: selectedMonitorIndex - 1] {
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
            viewModel.updateWorkspaceAssignment(workspace: workspace, assignment: assignment)
        }
    }
}

struct AddWorkspaceView: View {
    let onAdd: (String) -> Void
    
    @State private var customWorkspace = ""
    @State private var errorMessage = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Workspace")
                .font(.headline)
            
            
            
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