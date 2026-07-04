import AppKit
import Common
import SwiftUI

struct WorkspacesMonitorsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectedMonitors
                Divider()
                assignmentsEditor
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var connectedMonitors: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connected Monitors")
                .font(.headline)
            Text("Copy a monitor's UUID to pin a workspace to it below. DisplayLink monitors expose no vendor/model fingerprint, so the UUID is the only reliable way to match them.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(viewModel.liveMonitors) { monitor in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(monitor.name).fontWeight(.medium)
                        Text(monitor.resolution)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let uuid = monitor.uuid {
                            Text(uuid)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text("no UUID available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    if let uuid = monitor.uuid {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(uuid, forType: .string)
                        } label: {
                            Label("Copy UUID", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
        }
    }

    private var assignmentsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Workspace to Monitor Assignments")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.addAssignment()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
            Text("Monitor value: 'main', 'secondary', a monitor number (1, 2, …), a name pattern (regex), or a UUID copied above.")
                .font(.caption)
                .foregroundColor(.secondary)

            if viewModel.assignments.isEmpty {
                Text("No assignments. Workspaces follow the focused monitor.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.assignments) { row in
                    HStack {
                        TextField("workspace", text: binding(for: row.id, \.workspace))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 140)
                        Text("→").foregroundColor(.secondary)
                        TextField("monitor", text: binding(for: row.id, \.monitor))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Button {
                            viewModel.removeAssignment(id: row.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func binding(
        for id: ConfigurationViewModel.WorkspaceAssignmentRow.ID,
        _ keyPath: WritableKeyPath<ConfigurationViewModel.WorkspaceAssignmentRow, String>
    ) -> Binding<String> {
        Binding(
            get: {
                viewModel.assignments.first { $0.id == id }?[keyPath: keyPath] ?? ""
            },
            set: { newValue in
                guard let index = viewModel.assignments.firstIndex(where: { $0.id == id }) else { return }
                viewModel.assignments[index][keyPath: keyPath] = newValue
                viewModel.markAsModified()
            }
        )
    }
}
