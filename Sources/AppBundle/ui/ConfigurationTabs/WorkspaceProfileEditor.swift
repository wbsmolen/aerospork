import SwiftUI
import Common

/// Modal editor for creating and editing workspace profiles
struct WorkspaceProfileEditor: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @Environment(\.dismiss) private var dismiss

    // Editing state
    let editingProfile: Config.WorkspaceProfile?
    @State private var profileName: String = ""
    @State private var profileAssignments: [Config.WorkspaceAssignment] = []
    @State private var errorMessage: String?

    // UI state
    @State private var showingAddAssignment = false
    @State private var selectedWorkspace: String = ""
    @State private var selectedMonitorIndex: Int = 0

    init(viewModel: ConfigurationViewModel, editingProfile: Config.WorkspaceProfile? = nil) {
        self.viewModel = viewModel
        self.editingProfile = editingProfile

        if let profile = editingProfile {
            _profileName = State(initialValue: profile.name)
            _profileAssignments = State(initialValue: profile.assignments)
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(editingProfile == nil ? "Create Profile" : "Edit Profile")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }

            // Profile name field
            VStack(alignment: .leading, spacing: 8) {
                Text("Profile Name")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                TextField("e.g., Home, Office, Docked", text: $profileName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Text("Give this profile a descriptive name for your monitor setup")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Assignments section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Workspace Assignments")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Button(action: { showingAddAssignment = true }) {
                        Label("Add Assignment", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if profileAssignments.isEmpty {
                    Text("No workspace assignments yet. Click + to add one.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    List {
                        ForEach(profileAssignments, id: \.workspaceName) { assignment in
                            HStack {
                                Text("Workspace \(assignment.workspaceName)")
                                    .font(.body)

                                Spacer()

                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)

                                Text(assignment.monitorDescription)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { indexSet in
                            profileAssignments.remove(atOffsets: indexSet)
                        }
                    }
                    .frame(height: 200)
                    .listStyle(InsetListStyle())
                }
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(editingProfile == nil ? "Create" : "Save") {
                    saveProfile()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(profileName.isEmpty)
            }
        }
        .padding()
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingAddAssignment) {
            AddAssignmentSheet(
                viewModel: viewModel,
                onAdd: { assignment in
                    // Remove any existing assignment for this workspace first
                    profileAssignments.removeAll { $0.workspaceName == assignment.workspaceName }
                    profileAssignments.append(assignment)
                    profileAssignments.sort { $0.workspaceName < $1.workspaceName }
                }
            )
        }
    }

    private func saveProfile() {
        // Validate profile name
        guard !profileName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Profile name cannot be empty"
            return
        }

        // Check for duplicate name (if creating or renaming)
        if editingProfile?.name != profileName {
            if viewModel.workspaceProfiles.contains(where: { $0.name == profileName }) {
                errorMessage = "A profile with this name already exists"
                return
            }
        }

        // Create or update profile
        let profile = Config.WorkspaceProfile(
            name: profileName,
            assignments: profileAssignments
        )

        if let existingProfile = editingProfile {
            // Update existing profile
            if let index = viewModel.workspaceProfiles.firstIndex(where: { $0.id == existingProfile.id }) {
                viewModel.workspaceProfiles[index] = profile
            }
        } else {
            // Add new profile
            viewModel.workspaceProfiles.append(profile)
        }

        viewModel.markAsModified()
        dismiss()
    }
}

/// Sheet for adding a workspace assignment
struct AddAssignmentSheet: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @Environment(\.dismiss) private var dismiss

    let onAdd: (Config.WorkspaceAssignment) -> Void

    @State private var selectedWorkspace: String = ""
    @State private var selectedMonitorIndex: Int = 0

    var availableWorkspaces: [String] {
        viewModel.allWorkspaces
    }

    var availableMonitors: [ConfigurationViewModel.MonitorInfo] {
        viewModel.connectedMonitors
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Workspace Assignment")
                .font(.headline)

            // Workspace picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Workspace")
                    .font(.subheadline)

                Picker("Workspace", selection: $selectedWorkspace) {
                    ForEach(availableWorkspaces, id: \.self) { workspace in
                        Text(workspace).tag(workspace)
                    }
                }
                .pickerStyle(MenuPickerStyle())
            }

            // Monitor picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Monitor")
                    .font(.subheadline)

                if availableMonitors.isEmpty {
                    Text("No monitors detected")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    Picker("Monitor", selection: $selectedMonitorIndex) {
                        ForEach(0..<availableMonitors.count, id: \.self) { index in
                            Text(availableMonitors[index].fingerprint.displayName).tag(index)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    addAssignment()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedWorkspace.isEmpty || availableMonitors.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
        .onAppear {
            if !availableWorkspaces.isEmpty {
                selectedWorkspace = availableWorkspaces[0]
            }
        }
    }

    private func addAssignment() {
        guard selectedMonitorIndex < availableMonitors.count else { return }

        let monitor = availableMonitors[selectedMonitorIndex]

        // Create fingerprint assignment
        let fingerprint = Config.WorkspaceAssignment.MonitorFingerprint(
            vendorId: monitor.fingerprint.vendorId,
            modelId: monitor.fingerprint.modelId,
            serialNumber: monitor.fingerprint.serialNumber,
            displayName: monitor.fingerprint.displayName,
            width: monitor.width,
            height: monitor.height
        )

        let assignment = Config.WorkspaceAssignment(
            workspaceName: selectedWorkspace,
            monitorDescription: monitor.fingerprint.displayName,
            monitorType: .fingerprint(fingerprint),
            isForceAssignment: true
        )

        onAdd(assignment)
        dismiss()
    }
}
