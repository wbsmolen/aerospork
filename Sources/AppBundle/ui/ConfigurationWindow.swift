import Common
import SwiftUI

public struct ConfigurationWindow: View {
    @StateObject private var viewModel = ConfigurationViewModel()
    @State private var selectedTab = "general"

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("aerospork")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                if viewModel.hasUnsavedChanges {
                    Text("Unsaved Changes")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            TabView(selection: $selectedTab) {
                GeneralSettingsTab(viewModel: viewModel)
                    .tabItem { Label("General", systemImage: "gear") }
                    .tag("general")

                GapsSettingsTab(viewModel: viewModel)
                    .tabItem { Label("Gaps", systemImage: "ruler") }
                    .tag("gaps")

                KeyBindingsTab(viewModel: viewModel)
                    .tabItem { Label("Key Bindings", systemImage: "keyboard") }
                    .tag("keybindings")

                WorkspacesMonitorsTab(viewModel: viewModel)
                    .tabItem { Label("Workspaces & Monitors", systemImage: "macwindow.on.rectangle") }
                    .tag("workspaces_monitors")
            }
            .padding()

            Divider()

            HStack {
                Button("Revert") { viewModel.revertChanges() }
                    .disabled(!viewModel.hasUnsavedChanges)

                Spacer()

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .lineLimit(2)
                        .frame(maxWidth: 300)
                }

                Spacer()

                Button("Cancel") {
                    if viewModel.hasUnsavedChanges {
                        showUnsavedChangesAlert()
                    } else {
                        closeWindow()
                    }
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    Task { @MainActor in
                        await viewModel.saveConfiguration()
                        if viewModel.errorMessage == nil {
                            closeWindow()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.hasUnsavedChanges || viewModel.isSaving)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .task { await viewModel.loadConfiguration() }
    }

    private func closeWindow() {
        NSApplication.shared.keyWindow?.close()
    }

    private func showUnsavedChangesAlert() {
        let alert = NSAlert()
        alert.messageText = "Unsaved Changes"
        alert.informativeText = "You have unsaved changes. Do you want to discard them?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
            case .alertFirstButtonReturn:
                Task { @MainActor in
                    await viewModel.saveConfiguration()
                    if viewModel.errorMessage == nil {
                        closeWindow()
                    }
                }
            case .alertSecondButtonReturn:
                closeWindow()
            default:
                break
        }
    }
}
