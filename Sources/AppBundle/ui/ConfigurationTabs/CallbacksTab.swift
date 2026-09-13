import Common
import SwiftUI

/// Covers the config keys that run commands in response to events, plus the exec environment.
/// None of these were reachable from the GUI before.
struct CallbacksTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    var body: some View {
        Form {
            commandSection(
                "After startup",
                icon: "play.circle",
                // The help used to be a grey row *inside* the box, indistinguishable from a
                // command. Section footers are where macOS puts this, and they stay out of the way.
                help: "Runs once, after AeroSpork finishes launching. Multiple commands run in order, top to bottom.",
                keyPath: \.afterStartupCommands,
            )
            commandSection(
                "Focused workspace changed",
                icon: "rectangle.on.rectangle",
                help: "Every workspace switch, including switches within one monitor. `move-mouse window-lazy-center` here is what makes the pointer follow you.",
                keyPath: \.onFocusedWorkspaceChanged,
            )
            commandSection(
                "Focused monitor changed",
                icon: "display.2",
                help: "Only when focus moves to a different monitor.",
                placeholder: "move-mouse monitor-lazy-center",
                keyPath: \.onFocusedMonitorChanged,
            )
            commandSection(
                "Focus changed",
                icon: "scope",
                help: "Any focus change at all: window, workspace or monitor. Fires the most often — keep it cheap.",
                placeholder: "move-mouse window-lazy-center",
                keyPath: \.onFocusChanged,
            )

            Section {
                Toggle("Inherit AeroSpork's environment", isOn: viewModel.binding(\.execInheritEnvVars))
                if viewModel.execInheritEnvVars {
                    SettingsHint("Every command on this page runs with AeroSpork's full environment, including anything sensitive in it. Turn this off and list only what you need below.")
                }
                ForEach(viewModel.execEnvVars) { row in
                    HStack(spacing: 8) {
                        SettingsField("Variable name", prompt: "PATH", text: envBinding(row.id, \.name))
                            .frame(width: 150)
                        SettingsField("Variable value", prompt: "/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}", text: envBinding(row.id, \.value))
                        IconButton(systemImage: "minus.circle", label: row.name.isEmpty ? "Remove variable" : "Remove “\(row.name)”", role: .destructive) {
                            viewModel.execEnvVars.removeAll { $0.id == row.id }
                            viewModel.markAsModified()
                            viewModel.scheduleAutoSave()
                        }
                    }
                }
                addButton("Add variable") {
                    viewModel.execEnvVars.append(.init(name: "", value: ""))
                    viewModel.markAsModified()
                }
            } header: {
                SectionLabel("Environment for exec commands", "terminal")
            } footer: {
                Text("`exec-and-forget` and every command above run with this environment. `PATH` is the one people usually need. Commands with a window or workspace target also get `AEROSPORK_WINDOW_ID` or `AEROSPORK_WORKSPACE`, and workspace-change commands get `AEROSPORK_FOCUSED_WORKSPACE` and `AEROSPORK_PREV_WORKSPACE`. `aerospork list-exec-env-vars` shows the environment they all start from.")
            }
        }
        .formStyle(.grouped)
    }

    private func commandSection(
        _ title: String,
        icon: String,
        help: String,
        placeholder: String = "exec-and-forget open -a Terminal",
        keyPath: ReferenceWritableKeyPath<ConfigurationViewModel, [ConfigurationViewModel.CommandRow]>,
    ) -> some View {
        Section {
            if viewModel[keyPath: keyPath].isEmpty {
                SettingsHint("Nothing here yet. Anything you add runs every time this event fires — `exec-and-forget` for a shell command, or an aerospork command directly.")
            }
            ForEach(viewModel[keyPath: keyPath]) { row in
                HStack(spacing: 8) {
                    SettingsField("Command", prompt: placeholder, text: commandBinding(keyPath, row.id))
                    IconButton(systemImage: "minus.circle", label: row.command.isEmpty ? "Remove command" : "Remove “\(row.command)”", role: .destructive) {
                        viewModel[keyPath: keyPath].removeAll { $0.id == row.id }
                        viewModel.markAsModified()
                        viewModel.scheduleAutoSave()
                    }
                }
            }
            addButton("Add command") {
                viewModel[keyPath: keyPath].append(.init(command: ""))
                viewModel.markAsModified()
            }
        } header: {
            SectionLabel(title, icon)
        } footer: {
            Text(LocalizedStringKey(help))
        }
    }

    private func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: "plus.circle") }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
    }

    private func commandBinding(
        _ keyPath: ReferenceWritableKeyPath<ConfigurationViewModel, [ConfigurationViewModel.CommandRow]>,
        _ id: ConfigurationViewModel.CommandRow.ID,
    ) -> Binding<String> {
        Binding(
            get: { viewModel[keyPath: keyPath].first { $0.id == id }?.command ?? "" },
            set: { newValue in
                guard let i = viewModel[keyPath: keyPath].firstIndex(where: { $0.id == id }) else { return }
                viewModel[keyPath: keyPath][i].command = newValue
                viewModel.markAsModified()
                viewModel.scheduleAutoSave()
            },
        )
    }

    private func envBinding(
        _ id: ConfigurationViewModel.EnvVarRow.ID,
        _ field: WritableKeyPath<ConfigurationViewModel.EnvVarRow, String>,
    ) -> Binding<String> {
        Binding(
            get: { viewModel.execEnvVars.first { $0.id == id }?[keyPath: field] ?? "" },
            set: { newValue in
                guard let i = viewModel.execEnvVars.firstIndex(where: { $0.id == id }) else { return }
                viewModel.execEnvVars[i][keyPath: field] = newValue
                viewModel.markAsModified()
                viewModel.scheduleAutoSave()
            },
        )
    }
}
