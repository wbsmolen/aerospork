import Common
import SwiftUI

/// `[[on-window-detected]]` — assign windows to workspaces, float them, etc. when they appear.
/// Typically the most-configured feature after keybindings, and previously invisible to the GUI.
struct WindowRulesTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var selection: ConfigurationViewModel.WindowRuleRow.ID?

    private var selectedIndex: Int? {
        selection.flatMap { id in viewModel.windowRules.firstIndex { $0.id == id } }
    }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 280, idealWidth: 340)
            detail.frame(minWidth: 330)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Rules", "list.bullet")
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            rulesTable
            ListActionBar(
                addHelp: "Add a window rule",
                removeHelp: "Remove the selected rule",
                onAdd: { addRule() },
                onRemove: removeAction,
            )
        }
    }

    private var removeAction: (() -> Void)? {
        guard selection != nil else { return nil }
        return { removeRule() }
    }

    @ViewBuilder
    private var rulesTable: some View {
        if viewModel.windowRules.isEmpty {
            ContentUnavailableViewCompat(
                icon: "macwindow",
                title: "No window rules",
                message: "Rules run once, when a window first appears — the usual use is sending an app straight to its workspace.",
                actionTitle: "Add rule",
                action: { addRule() },
            )
        } else {
            Table(viewModel.windowRules, selection: $selection) {
                TableColumn("Matches") { rule in matchCell(rule) }
                TableColumn("Run") { rule in Text(rule.run).font(.system(.body, design: .monospaced)) }
            }
            .tableStyle(.inset)
            .onDeleteCommand { removeRule() }
        }
    }

    @ViewBuilder
    private func matchCell(_ rule: ConfigurationViewModel.WindowRuleRow) -> some View {
        HStack(spacing: 5) {
            Text(summary(rule)).font(.system(.body, design: .monospaced))
            // The UI has no control for `during-aerospork-startup`, but it round-trips it. Say so,
            // or a rule that only fires at startup looks identical to one that fires every time.
            if rule.duringStartup == true {
                Badge("startup", tone: .muted, help: "Only applies while AeroSpork is starting up")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let i = selectedIndex {
            Form {
                Section {
                    LabeledContent("App ID") {
                        SettingsField("App ID", prompt: "com.apple.finder", text: field(i, \.appId))
                    }
                    LabeledContent("App name") {
                        SettingsField("App name", prompt: "^Finder$", text: field(i, \.appNameRegex))
                    }
                    LabeledContent("Window title") {
                        SettingsField("Window title", prompt: "^Preferences$", text: field(i, \.windowTitleRegex))
                    }
                    LabeledContent("Workspace") {
                        SettingsField("Workspace", prompt: "3", text: field(i, \.workspace))
                    }
                } header: {
                    SectionLabel("Match when…", "line.3.horizontal.decrease.circle")
                } footer: {
                    Text("Empty matchers are left out. A rule with no matchers at all applies to every window. `aerospork list-apps` prints app IDs.")
                }

                Section {
                    LabeledContent("Command") {
                        SettingsField("Command", prompt: "move-node-to-workspace 3", text: field(i, \.run))
                    }
                    Toggle("Keep checking later rules", isOn: Binding(
                        get: { viewModel.windowRules[i].checkFurtherCallbacks },
                        set: {
                            viewModel.windowRules[i].checkFurtherCallbacks = $0
                            viewModel.markAsModified()
                            viewModel.scheduleAutoSave()
                        },
                    ))
                } header: {
                    SectionLabel("Then run", "bolt")
                } footer: {
                    Text("Chain commands with `\(ConfigurationViewModel.commandSeparator.trimmingCharacters(in: .whitespaces))`. By default a matching rule stops the search.")
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableViewCompat(
                icon: "sidebar.left",
                title: "No rule selected",
                message: "Pick a rule on the left to edit what it matches and what it does.",
            )
        }
    }

    private func addRule() {
        viewModel.windowRules.append(.init())
        viewModel.markAsModified()
        selection = viewModel.windowRules.last?.id
    }

    private func removeRule() {
        guard let selection else { return }
        viewModel.windowRules.removeAll { $0.id == selection }
        viewModel.markAsModified()
        viewModel.scheduleAutoSave()
        self.selection = nil
    }

    private func summary(_ r: ConfigurationViewModel.WindowRuleRow) -> String {
        var parts: [String] = []
        if !r.appId.isEmpty { parts.append(r.appId) }
        if !r.appNameRegex.isEmpty { parts.append("name~\(r.appNameRegex)") }
        if !r.windowTitleRegex.isEmpty { parts.append("title~\(r.windowTitleRegex)") }
        if !r.workspace.isEmpty { parts.append("ws=\(r.workspace)") }
        return parts.isEmpty ? "(any window)" : parts.joined(separator: " ")
    }

    private func field(_ i: Int, _ keyPath: WritableKeyPath<ConfigurationViewModel.WindowRuleRow, String>) -> Binding<String> {
        Binding(
            get: { viewModel.windowRules.indices.contains(i) ? viewModel.windowRules[i][keyPath: keyPath] : "" },
            set: { newValue in
                guard viewModel.windowRules.indices.contains(i) else { return }
                viewModel.windowRules[i][keyPath: keyPath] = newValue
                viewModel.markAsModified()
                viewModel.scheduleAutoSave()
            },
        )
    }
}
