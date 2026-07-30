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
                help: "Runs once, after AeroSpork finishes launching.",
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
                keyPath: \.onFocusedMonitorChanged,
            )
            commandSection(
                "Focus changed",
                icon: "scope",
                help: "Any focus change at all: window, workspace or monitor. Fires the most often — keep it cheap.",
                keyPath: \.onFocusChanged,
            )

            Section {
                Toggle("Inherit AeroSpork's environment", isOn: viewModel.binding(\.execInheritEnvVars))
                ForEach(viewModel.execEnvVars) { row in
                    HStack(spacing: 8) {
                        SettingsField("Variable name", prompt: "PATH", text: envBinding(row.id, \.name))
                            .frame(width: 150)
                        SettingsField("Variable value", prompt: "/opt/homebrew/bin:/usr/bin", text: envBinding(row.id, \.value))
                        removeButton {
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
                Text("`exec-and-forget` and every command above run with this environment. `PATH` is the one people usually need.")
            }
        }
        .formStyle(.grouped)
    }

    private func commandSection(
        _ title: String,
        icon: String,
        help: String,
        keyPath: ReferenceWritableKeyPath<ConfigurationViewModel, [ConfigurationViewModel.CommandRow]>,
    ) -> some View {
        Section {
            if viewModel[keyPath: keyPath].isEmpty {
                Text("Nothing runs on this event.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            ForEach(viewModel[keyPath: keyPath]) { row in
                HStack(spacing: 8) {
                    SettingsField("Command", prompt: "exec-and-forget open -a Terminal", text: commandBinding(keyPath, row.id))
                    removeButton {
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

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove")
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
