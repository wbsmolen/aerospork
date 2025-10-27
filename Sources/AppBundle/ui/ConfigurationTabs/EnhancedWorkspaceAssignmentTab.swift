import SwiftUI
import Common
import AppKit

struct EnhancedWorkspaceAssignmentTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    @State private var newWorkspaceName = ""
    @State private var showingAddWorkspace = false
    @State private var isMonitorPreviewExpanded = true
    @State private var showingProfileEditor = false
    @State private var editingProfile: Config.WorkspaceProfile? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                profileManagementView
                Divider()
                workspaceManagementView
                Divider()
                monitorView
            }
            .padding()
        }
        .sheet(isPresented: $showingProfileEditor) {
            WorkspaceProfileEditor(viewModel: viewModel, editingProfile: editingProfile)
        }
    }

    var profileManagementView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspace Profiles")
                .font(.title2)
                .fontWeight(.bold)

            Text("Save and switch between different monitor setups (e.g., Home, Office, Docked)")
                .font(.caption)
                .foregroundColor(.secondary)

            // Profile selector and management buttons
            HStack(spacing: 12) {
                // Active profile picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Profile")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if viewModel.workspaceProfiles.isEmpty {
                        Text("No profiles created")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    } else {
                        Picker("Active Profile", selection: Binding(
                            get: { viewModel.activeProfileName ?? "" },
                            set: { newValue in
                                viewModel.activeProfileName = newValue.isEmpty ? nil : newValue
                                viewModel.markAsModified()
                            }
                        )) {
                            Text("None").tag("")
                            ForEach(viewModel.workspaceProfiles, id: \.name) { profile in
                                Text(profile.name).tag(profile.name)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 200)
                    }
                }

                Spacer()

                // Management buttons
                HStack(spacing: 8) {
                    Button(action: {
                        editingProfile = nil
                        showingProfileEditor = true
                    }) {
                        Label("New Profile", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    if let activeProfile = viewModel.activeProfileName,
                       let profile = viewModel.workspaceProfiles.first(where: { $0.name == activeProfile }) {
                        Button(action: {
                            editingProfile = profile
                            showingProfileEditor = true
                        }) {
                            Label("Edit", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            deleteProfile(profile)
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            duplicateProfile(profile)
                        }) {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Button(action: {
                            loadProfileAssignments(profile)
                        }) {
                            Label("Load", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Load this profile's assignments into the current workspace configuration")
                    }
                }
            }

            // Profile info
            if let activeProfile = viewModel.activeProfileName,
               let profile = viewModel.workspaceProfiles.first(where: { $0.name == activeProfile }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(profile.assignments.count) workspace assignments in this profile")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !profile.assignments.isEmpty {
                        Text("Workspaces: \(profile.assignments.map { $0.workspaceName }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    var workspaceManagementView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspace to Monitor Assignments")
                .font(.title2)
                .fontWeight(.bold)

            Text("Configure which monitor each workspace should appear on when connected.")
                .font(.caption)
                .foregroundColor(.secondary)

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
                    Button(action: { viewModel.addWorkspaceAssignment() }) {
                        Image(systemName: "plus")
                    }
                    .help("Add a new workspace assignment.")
                }
                .padding(.horizontal, 15) // Consistent horizontal padding
                .padding(.vertical, 10) // Increased vertical padding
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                // Workspace list - show all workspaces (assigned or not)
                List {
                    ForEach(viewModel.allWorkspaces, id: \.self) { workspaceName in
                        WorkspaceConfigRow(
                            workspace: workspaceName,
                            viewModel: viewModel
                        )
                    }
                    .onDelete { indexSet in
                        indexSet.forEach { index in
                            let workspaceName = viewModel.allWorkspaces[index]
                            viewModel.removeWorkspace(workspaceName)
                        }
                    }
                }
                .listStyle(InsetListStyle())
                .frame(minHeight: 200)
            }
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

    // MARK: - Profile Management Methods

    private func deleteProfile(_ profile: Config.WorkspaceProfile) {
        viewModel.workspaceProfiles.removeAll { $0.id == profile.id }
        if viewModel.activeProfileName == profile.name {
            viewModel.activeProfileName = nil
        }
        viewModel.markAsModified()
    }

    private func duplicateProfile(_ profile: Config.WorkspaceProfile) {
        var newName = "\(profile.name) Copy"
        var counter = 1
        while viewModel.workspaceProfiles.contains(where: { $0.name == newName }) {
            counter += 1
            newName = "\(profile.name) Copy \(counter)"
        }

        let duplicate = Config.WorkspaceProfile(
            name: newName,
            assignments: profile.assignments
        )
        viewModel.workspaceProfiles.append(duplicate)
        viewModel.markAsModified()
    }

    private func loadProfileAssignments(_ profile: Config.WorkspaceProfile) {
        // Replace current workspace assignments with profile's assignments
        viewModel.workspaceAssignments = profile.assignments
        viewModel.markAsModified()
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
                                offset: layout.offset,
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
                        .strokeBorder(monitor.isMain ? Color.blue : Color.gray, lineWidth: 2),
                )
                .frame(
                    width: CGFloat(monitor.width) * scale,
                    height: CGFloat(monitor.height) * scale,
                )

            Text(monitor.name)
                .font(.caption)
                .lineLimit(1)
        }
        .position(
            x: monitor.positionX * scale + CGFloat(monitor.width) * scale / 2 + offset.x,
            y: monitor.positionY * scale + CGFloat(monitor.height) * scale / 2 + offset.y,
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
                    onTap: { selectedMonitorId = monitor.id },
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
            // Find monitor index
            if let index = viewModel.connectedMonitors.firstIndex(where: { monitor in
                switch assignment.monitorType {
                    case .name(let name):
                        return monitor.name == name
                    case .index(let index):
                        return monitor.index == index
                    case .fingerprint(let fp):
                        // Match by display name AND resolution (most reliable)
                        if let fpDisplayName = fp.displayName {
                            let monDisplayName = monitor.fingerprint.displayName
                            let displayNameMatches = fpDisplayName.localizedCaseInsensitiveCompare(monDisplayName) == .orderedSame

                            // Check resolution if available
                            let resolutionMatches = (fp.width == nil && fp.height == nil) ||
                                (fp.width == monitor.fingerprint.widthPixels &&
                                    fp.height == monitor.fingerprint.heightPixels)

                            // Both display name and resolution must match
                            if displayNameMatches && resolutionMatches {
                                return true
                            }
                        }

                        // Fall back to vendor/model/serial matching if no display name
                        if fp.displayName == nil {
                            let vendorMatch = fp.vendorId == nil || fp.vendorId == monitor.fingerprint.vendorId
                            let modelMatch = fp.modelId == nil || fp.modelId == monitor.fingerprint.modelId
                            let serialMatch = fp.serialNumber == nil || fp.serialNumber == monitor.fingerprint.serialNumber
                            let resolutionMatch = (fp.width == nil && fp.height == nil) ||
                                (fp.width == monitor.fingerprint.widthPixels && fp.height == monitor.fingerprint.heightPixels)

                            return vendorMatch && modelMatch && serialMatch && resolutionMatch
                        }

                        return false
                }
            }) {
                self._selectedMonitorIndex = State(initialValue: index + 1)
            } else {
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
            let assignment = Config.WorkspaceAssignment(
                workspaceName: workspace,
                monitorDescription: monitor.name,
                monitorType: .fingerprint(Config.WorkspaceAssignment.MonitorFingerprint(
                    vendorId: monitor.fingerprint.vendorId,
                    modelId: monitor.fingerprint.modelId,
                    serialNumber: monitor.fingerprint.serialNumber,
                    displayName: monitor.fingerprint.displayName,
                    width: monitor.fingerprint.widthPixels,
                    height: monitor.fingerprint.heightPixels,
                )),
                isForceAssignment: isForceAssignment,
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
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
