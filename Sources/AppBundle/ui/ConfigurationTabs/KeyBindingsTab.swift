import SwiftUI
import Common

struct KeyBindingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var selectedMode: String = "main"
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Key Bindings")
                    .font(.headline)
                
                Spacer()
                
                // Mode selector
                if !viewModel.keyBindings.isEmpty {
                    Picker("Mode:", selection: $selectedMode) {
                        ForEach(viewModel.keyBindings, id: \.mode) { modeBinding in
                            Text(modeBinding.mode).tag(modeBinding.mode)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(width: 150)
                }
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search bindings...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .frame(width: 200)
            }
            .padding()
            
            Divider()
            
            // Bindings list
            if let modeBindings = viewModel.keyBindings.first(where: { $0.mode == selectedMode }) {
                let filteredBindings = modeBindings.bindings.filter { binding in
                    searchText.isEmpty ||
                    binding.key.localizedCaseInsensitiveContains(searchText) ||
                    binding.command.localizedCaseInsensitiveContains(searchText)
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredBindings.indices, id: \.self) { index in
                            KeyBindingRow(
                                key: filteredBindings[index].key,
                                command: filteredBindings[index].command,
                                isEven: index % 2 == 0
                            )
                        }
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("No key bindings found")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Key bindings are read-only. Edit the config file to modify bindings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
}

struct KeyBindingRow: View {
    let key: String
    let command: String
    let isEven: Bool
    
    var body: some View {
        HStack {
            Text(formatKeyBinding(key))
                .font(.system(.body, design: .monospaced))
                .frame(width: 200, alignment: .leading)
                .padding(.horizontal)
            
            Text("→")
                .foregroundColor(.secondary)
            
            Text(command)
                .font(.system(.body))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
        .padding(.vertical, 6)
        .background(isEven ? Color(NSColor.controlBackgroundColor) : Color.clear)
    }
    
    private func formatKeyBinding(_ key: String) -> String {
        // Format the key binding for better display
        key.replacingOccurrences(of: "cmd", with: "⌘")
           .replacingOccurrences(of: "alt", with: "⌥")
           .replacingOccurrences(of: "shift", with: "⇧")
           .replacingOccurrences(of: "ctrl", with: "⌃")
    }
}