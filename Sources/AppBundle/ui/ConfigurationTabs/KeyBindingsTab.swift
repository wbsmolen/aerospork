import Common
import SwiftUI

struct KeyBindingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var selectedMode: String = "main"
    @State private var newKey: String = ""
    @State private var newCommand: String = ""

    private var currentMode: ConfigurationViewModel.ModeBindings? {
        viewModel.modes.first { $0.mode == selectedMode } ?? viewModel.modes.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Key Bindings")
                    .font(.headline)
                Spacer()
                if viewModel.modes.count > 1 {
                    Picker("Mode:", selection: $selectedMode) {
                        ForEach(viewModel.modes) { Text($0.mode).tag($0.mode) }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 180)
                }
            }
            .padding()

            Divider()

            if let mode = currentMode {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(mode.bindings.enumerated()), id: \.element.id) { index, binding in
                            HStack {
                                Text(formatKey(binding.key))
                                    .font(.system(.body, design: .monospaced))
                                    .frame(width: 200, alignment: .leading)
                                Text("→").foregroundColor(.secondary)
                                Text(binding.command)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    viewModel.removeBinding(mode: mode.mode, id: binding.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove binding")
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .background(index.isMultiple(of: 2) ? Color(NSColor.controlBackgroundColor) : Color.clear)
                        }
                    }
                }

                Divider()

                HStack {
                    TextField("key (e.g. alt-h)", text: $newKey)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 200)
                    TextField("command (e.g. focus left)", text: $newCommand)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Add") {
                        viewModel.addBinding(mode: mode.mode, key: newKey, command: newCommand)
                        newKey = ""
                        newCommand = ""
                    }
                    .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty
                        || newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            } else {
                Spacer()
                Text("No key bindings defined")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .onAppear {
            if currentMode?.mode != selectedMode, let first = viewModel.modes.first {
                selectedMode = first.mode
            }
        }
    }

    private func formatKey(_ key: String) -> String {
        key.replacingOccurrences(of: "cmd", with: "⌘")
            .replacingOccurrences(of: "alt", with: "⌥")
            .replacingOccurrences(of: "shift", with: "⇧")
            .replacingOccurrences(of: "ctrl", with: "⌃")
    }
}
