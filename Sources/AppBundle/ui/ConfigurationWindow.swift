import SwiftUI
import Common

public struct ConfigurationWindow: View {
    @StateObject private var viewModel = ConfigurationViewModel()
    @State private var selectedTab = "general"
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("AeroSpace Configuration")
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
            
            // Tab View
            TabView(selection: $selectedTab) {
                GeneralSettingsTab(viewModel: viewModel)
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                    .tag("general")
                
                EnhancedWorkspaceAssignmentTab(viewModel: viewModel)
                    .tabItem {
                        Label("Workspaces", systemImage: "square.grid.3x3")
                    }
                    .tag("workspaces")
                
                GapsSettingsTab(viewModel: viewModel)
                    .tabItem {
                        Label("Gaps", systemImage: "ruler")
                    }
                    .tag("gaps")
                
                KeyBindingsTab(viewModel: viewModel)
                    .tabItem {
                        Label("Key Bindings", systemImage: "keyboard")
                    }
                    .tag("keybindings")
            }
            .padding()
            
            Divider()
            
            // Footer with buttons
            HStack {
                Button("Revert") {
                    viewModel.revertChanges()
                }
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
                        // Show confirmation dialog
                        showUnsavedChangesAlert()
                    } else {
                        closeWindow()
                    }
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Save") {
                    Task {
                        await viewModel.saveConfiguration()
                        if viewModel.errorMessage == nil {
                            closeWindow()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.hasUnsavedChanges)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await viewModel.loadConfiguration()
        }
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
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            Task {
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