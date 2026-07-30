import AppKit
import Common
import SwiftUI

struct WorkspacesMonitorsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var selection: ConfigurationViewModel.WorkspaceAssignmentRow.ID?

    var body: some View {
        VStack(spacing: 0) {
            monitors
            Divider()
            assignments
            ListActionBar(
                addHelp: "Pin a workspace to a monitor",
                removeHelp: "Remove the selected assignment",
                onAdd: { viewModel.addAssignment() },
                onRemove: selection == nil ? nil : {
                    if let id = selection { viewModel.removeAssignment(id: id) }
                    viewModel.scheduleAutoSave()
                    selection = nil
                },
                hint: "Hardware fingerprints already in your config are preserved — they just show up here under the monitor's name. A DisplayLink monitor reports no vendor or serial, so its UUID is the only thing that pins a workspace to that exact monitor.",
            )
        }
    }

    /// Read-only, and the reason this tab exists at all: you cannot write a monitor assignment
    /// without knowing what the monitors are actually called and what their UUIDs are.
    private var monitors: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Connected monitors", "display.2")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            // Same empty-state treatment as every other list in this window, rather than a section
            // header floating above nothing.
            if viewModel.liveMonitors.isEmpty {
                SettingsHint("No monitors reported yet — they appear as soon as macOS reports one, and their UUIDs are what pins a workspace to a physical panel.")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.liveMonitors) { monitor in
                        HStack(spacing: 10) {
                            Image(systemName: "display")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(monitor.name).fontWeight(.medium)
                                Text(monitor.resolution)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 12)
                            if let uuid = monitor.uuid {
                                Text(uuid.prefix(8) + "…")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                CopyButton(value: uuid, help: "Copy monitor UUID\n\(uuid)")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .frame(maxHeight: 200)
    }

    @ViewBuilder
    private var assignments: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Workspace assignments", "arrow.triangle.branch")
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            if viewModel.assignments.isEmpty {
                ContentUnavailableViewCompat(
                    icon: "arrow.triangle.branch",
                    title: "No assignments",
                    message: "Workspaces land wherever they were last used. Add an assignment to pin one to a specific monitor.",
                    actionTitle: "Add assignment",
                    action: { viewModel.addAssignment() },
                )
            } else {
                Table(viewModel.assignments, selection: $selection) {
                    TableColumn("Workspace") { row in
                        SettingsField("Workspace name", prompt: "web", text: binding(row.id, \.workspace))
                    }
                    .width(min: 110, ideal: 140)

                    TableColumn("Monitor") { row in
                        // A Table column header is not a control label, so without this the
                        // picker is announced as an unnamed pop-up button.
                        Picker("Monitor for this workspace", selection: binding(row.id, \.monitor)) {
                            Text("Main").tag("main")
                            Text("Non-main").tag("secondary")
                            Divider()
                            ForEach(viewModel.liveMonitors) { m in
                                Text(m.name).tag(m.name)
                                if let uuid = m.uuid { Text("\(m.name) — this exact monitor").tag(uuid) }
                            }
                            // Keep whatever is already in the config selectable, even if it's a
                            // regex, a sequence number, or a monitor that isn't connected now.
                            let current = viewModel.assignments.first { $0.id == row.id }?.monitor ?? ""
                            if !current.isEmpty, !knownTokens.contains(current) {
                                Divider()
                                Text(current).tag(current)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .tableStyle(.inset)
                // Both columns are filled edge to edge by focusable controls, which swallow the
                // click that would select the row -- so `selection` stayed nil and ListActionBar's
                // Remove was permanently disabled. Window Rules has had this since it has Text-only
                // cells; this table needs it to have any delete affordance at all.
                .onDeleteCommand {
                    if let id = selection { viewModel.removeAssignment(id: id); selection = nil }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var knownTokens: Set<String> {
        var t: Set<String> = ["main", "secondary"]
        for m in viewModel.liveMonitors {
            t.insert(m.name)
            if let uuid = m.uuid { t.insert(uuid) }
        }
        return t
    }

    private func binding(
        _ id: ConfigurationViewModel.WorkspaceAssignmentRow.ID,
        _ keyPath: WritableKeyPath<ConfigurationViewModel.WorkspaceAssignmentRow, String>,
    ) -> Binding<String> {
        Binding(
            get: { viewModel.assignments.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let i = viewModel.assignments.firstIndex(where: { $0.id == id }) else { return }
                viewModel.assignments[i][keyPath: keyPath] = newValue
                viewModel.markAsModified()
                viewModel.scheduleAutoSave()
            },
        )
    }
}
