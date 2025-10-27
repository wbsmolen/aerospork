import SwiftUI
import Common

struct AdvancedSettingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Advanced Configuration")
                    .font(.headline)
                    .padding(.bottom, 10)

                Text("Advanced settings and informational displays")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Preserved Workspaces Section
                preservedWorkspacesSection

                Divider()

                // Key Mapping Preset Section
                keyMappingSection

                Divider()

                // Callbacks Section (Read-only)
                callbacksSection

                Divider()

                // Window Detection Rules Section (Read-only)
                windowDetectionSection

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Preserved Workspaces Section

    private var preservedWorkspacesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preserved Workspaces")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Workspaces that should never be automatically destroyed, even when empty")
                .font(.caption)
                .foregroundColor(.secondary)

            if viewModel.preservedWorkspaceNames.isEmpty {
                Text("No preserved workspaces configured. All workspaces can be automatically destroyed when empty.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.preservedWorkspaceNames, id: \.self) { workspace in
                        HStack {
                            Image(systemName: "pin.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text(workspace)
                                .font(.body)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                Text("Preserved workspaces: \(viewModel.preservedWorkspaceNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }

            Text("Note: Edit preserved workspaces in the TOML config file")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.top, 4)
        }
    }

    // MARK: - Key Mapping Section

    private var keyMappingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Key Mapping Preset")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Keyboard layout preset for directional commands")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Text("Current preset:")
                    .font(.body)

                Text(viewModel.keyMappingPreset.uppercased())
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)

                Spacer()
            }

            // Preset info
            VStack(alignment: .leading, spacing: 4) {
                switch viewModel.keyMappingPreset {
                case "qwerty":
                    Text("QWERTY layout: left=h, down=j, up=k, right=l")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case "dvorak":
                    Text("Dvorak layout: left=d, down=h, up=t, right=n")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case "colemak":
                    Text("Colemak layout: left=m, down=n, up=e, right=i")
                        .font(.caption)
                        .foregroundColor(.secondary)
                default:
                    Text("Custom or unknown preset")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("Note: Edit key mapping preset in the TOML config file")
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.top, 4)
        }
    }

    // MARK: - Callbacks Section

    @State private var callbacksExpanded = false

    private var callbacksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event Callbacks")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { callbacksExpanded.toggle() }) {
                    Image(systemName: callbacksExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
            }

            if callbacksExpanded {
                Text("Commands that run automatically when certain events occur")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // After Login Commands
                if !viewModel.afterLoginCommands.isEmpty {
                    callbackGroupView(
                        title: "After Login",
                        icon: "person.crop.circle",
                        commands: viewModel.afterLoginCommands,
                        description: "Runs once after you log in"
                    )
                }

                // After Startup Commands
                if !viewModel.afterStartupCommands.isEmpty {
                    callbackGroupView(
                        title: "After Startup",
                        icon: "power",
                        commands: viewModel.afterStartupCommands,
                        description: "Runs once when j4 starts"
                    )
                }

                // On Focus Changed
                if !viewModel.onFocusChangedCommands.isEmpty {
                    callbackGroupView(
                        title: "On Focus Changed",
                        icon: "arrow.left.arrow.right",
                        commands: viewModel.onFocusChangedCommands,
                        description: "Runs when focused window changes"
                    )
                }

                // On Monitor Changed
                if !viewModel.onMonitorChangedCommands.isEmpty {
                    callbackGroupView(
                        title: "On Monitor Changed",
                        icon: "display",
                        commands: viewModel.onMonitorChangedCommands,
                        description: "Runs when focused monitor changes"
                    )
                }

                if viewModel.afterLoginCommands.isEmpty &&
                   viewModel.afterStartupCommands.isEmpty &&
                   viewModel.onFocusChangedCommands.isEmpty &&
                   viewModel.onMonitorChangedCommands.isEmpty {
                    Text("No event callbacks configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                Text("Note: Edit callbacks in the TOML config file")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
        }
    }

    private func callbackGroupView(title: String, icon: String, commands: [String], description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(commands, id: \.self) { command in
                    Text("• \(command)")
                        .font(.caption)
                        .foregroundColor(.primary)
                        .padding(.leading, 8)
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Window Detection Section

    @State private var windowDetectionExpanded = false

    private var windowDetectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Window Detection Rules")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { windowDetectionExpanded.toggle() }) {
                    Image(systemName: windowDetectionExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
            }

            if windowDetectionExpanded {
                Text("Automatic actions when specific windows are detected")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if viewModel.windowDetectionRules.isEmpty {
                    Text("No window detection rules configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(viewModel.windowDetectionRules.enumerated()), id: \.offset) { index, rule in
                            windowDetectionRuleView(rule: rule, index: index + 1)
                        }
                    }
                }

                Text("Note: Edit window detection rules in the TOML config file")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
        }
    }

    private func windowDetectionRuleView(rule: ConfigurationViewModel.WindowDetectionRule, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.green)
                Text("Rule \(index)")
                    .font(.body)
                    .fontWeight(.medium)
            }

            // Matchers
            VStack(alignment: .leading, spacing: 4) {
                Text("Matches:")
                    .font(.caption)
                    .fontWeight(.semibold)

                if let appId = rule.appId {
                    Text("• App ID: \(appId)")
                        .font(.caption)
                        .foregroundColor(.primary)
                }

                if let appNamePattern = rule.appNamePattern {
                    Text("• App Name Pattern: \(appNamePattern)")
                        .font(.caption)
                        .foregroundColor(.primary)
                }

                if let windowTitlePattern = rule.windowTitlePattern {
                    Text("• Window Title Pattern: \(windowTitlePattern)")
                        .font(.caption)
                        .foregroundColor(.primary)
                }

                if let workspace = rule.workspace {
                    Text("• Workspace: \(workspace)")
                        .font(.caption)
                        .foregroundColor(.primary)
                }

                if rule.duringStartup {
                    Text("• Only during j4 startup")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }

            // Actions
            if !rule.commands.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Actions:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(rule.commands, id: \.self) { command in
                        Text("→ \(command)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }
            }

            if rule.checkFurtherRules {
                Text("Continue checking further rules after this one")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(8)
    }
}
