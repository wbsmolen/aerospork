import AppKit
import Common
import SwiftUI
import UniformTypeIdentifiers

struct GuidedWindowAction: Equatable {
    enum Layout: String, Hashable { case unchanged, floating, tiling }
    var layout: Layout = .unchanged
    var workspace = ""
    var isCustom = false
    /// The parts the guided controls cannot represent, verbatim. The UI disables its setters when
    /// `isCustom`, but the compose side must still round-trip them: losing a user's command may
    /// never depend on every call site remembering a guard.
    var customParts: [String] = []
}

func parseGuidedWindowAction(_ command: String) -> GuidedWindowAction {
    var result = GuidedWindowAction()
    for part in command.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
        switch part {
            case "layout floating": result.layout = .floating
            case "layout tiling": result.layout = .tiling
            case _ where part.hasPrefix("move-node-to-workspace "):
                result.workspace = String(part.dropFirst("move-node-to-workspace ".count)).trimmingCharacters(in: .whitespaces)
            default:
                result.isCustom = true
                result.customParts.append(part)
        }
    }
    return result
}

@MainActor func composeGuidedWindowAction(_ action: GuidedWindowAction) -> String {
    var commands: [String] = []
    switch action.layout {
        case .unchanged: break
        case .floating: commands.append("layout floating")
        case .tiling: commands.append("layout tiling")
    }
    if !action.workspace.isEmpty { commands.append("move-node-to-workspace \(action.workspace)") }
    commands.append(contentsOf: action.customParts)
    return commands.joined(separator: ConfigurationViewModel.commandSeparator)
}

/// `[[on-window-detected]]` — assign windows to workspaces, float them, etc. when they appear.
/// Typically the most-configured feature after keybindings, and previously invisible to the GUI.
struct WindowRulesTab: View {
    /// Shown for a rule with no matchers at all. Prose, not config text -- see `matchCell`.
    private static let anyWindow = "(any window)"

    private typealias Rule = ConfigurationViewModel.WindowRuleRow

    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var selection: ConfigurationViewModel.WindowRuleRow.ID?

    private var selectedRule: Rule? {
        selection.flatMap { id in viewModel.settings.windowRules.first { $0.id == id } }
    }

    var body: some View {
        HSplitView {
            list.frame(minWidth: 280, idealWidth: 340)
            detail.frame(minWidth: 330)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader("All rules", "list.bullet")
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
        if viewModel.settings.windowRules.isEmpty {
            ContentUnavailableViewCompat(
                icon: "macwindow",
                title: "No window rules",
                message: "Rules run once, when a window first appears — the usual use is sending an app straight to its workspace.",
                actionTitle: "Add rule",
                action: { addRule() },
            )
        } else {
            Table(viewModel.settings.windowRules, selection: $selection) {
                TableColumn("Matches") { rule in matchCell(rule) }
                TableColumn("Run") { rule in Text(rule.run).font(.system(.body, design: .monospaced)) }
            }
            .tableStyle(.inset)
            .onDeleteCommand { removeRule() }
        }
    }

    @ViewBuilder
    private func matchCell(_ rule: Rule) -> some View {
        HStack(spacing: 5) {
            if !rule.appId.isEmpty {
                ApplicationIcon(bundleIdentifier: rule.appId)
            }
            // Monospace only for a real matcher, which is config text. "(any window)" is prose
            // describing an absence, and reading it as something pasteable is misleading.
            Text(summary(rule))
                .font(hasNoMatchers(rule) ? .body : .system(.body, design: .monospaced))
                .foregroundStyle(hasNoMatchers(rule) ? .secondary : .primary)
            // The UI has no control for `during-aerospork-startup`, but it round-trips it. Say so,
            // or a rule that only fires at startup looks identical to one that fires every time.
            if rule.duringStartup == true {
                Badge("startup", tone: .muted, help: "Only applies while AeroSpork is starting up")
            } else if rule.duringStartup == false {
                Badge("runtime", tone: .muted, help: "Only applies after AeroSpork finishes starting up")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let rule = selectedRule {
            Form {
                Section {
                    LabeledContent("App ID") {
                        HStack(spacing: 8) {
                            SettingsField("App ID", prompt: "com.apple.finder", text: field(rule.id, \.appId))
                            Button("Choose app…") { chooseApplication(for: rule.id) }
                                .fixedSize()
                        }
                    }
                    LabeledContent("App name") {
                        SettingsField("App name", prompt: "^Finder$", text: field(rule.id, \.appNameRegex))
                    }
                    LabeledContent("Window title") {
                        SettingsField("Window title", prompt: "^Preferences$", text: field(rule.id, \.windowTitleRegex))
                    }
                    LabeledContent("Workspace") {
                        SettingsField("Workspace", prompt: "3", text: field(rule.id, \.workspace))
                            .frame(maxWidth: 140)
                    }
                    Picker("Startup timing", selection: startupTiming(rule.id)) {
                        Text("Any").tag("any")
                        Text("Startup").tag("startup")
                        Text("Runtime").tag("runtime")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    SectionLabel("Match when…", "line.3.horizontal.decrease.circle")
                } footer: {
                    SettingsHint("Empty matchers are left out. A rule with no matchers at all applies to every window. `aerospork list-apps` prints app IDs.")
                }

                Section {
                    let guided = parseGuidedWindowAction(rule.run)
                    if guided.isCustom {
                        HStack(spacing: 8) {
                            Badge("custom", tone: .muted, help: "This command contains actions the guided controls cannot represent.")
                            Button("Start over with guided controls") { field(rule.id, \.run).wrappedValue = "" }
                                .buttonStyle(.borderless)
                        }
                    } else {
                        Picker("Make the window", selection: guidedLayout(rule.id)) {
                            Text("Leave as is").tag(GuidedWindowAction.Layout.unchanged)
                            Text("Float").tag(GuidedWindowAction.Layout.floating)
                            Text("Tile").tag(GuidedWindowAction.Layout.tiling)
                        }
                        .pickerStyle(.segmented)
                        LabeledContent("Move it to workspace") {
                            SettingsField("Workspace", prompt: "don't move it", text: guidedWorkspace(rule.id))
                                .frame(maxWidth: 160)
                        }
                    }
                    LabeledContent("Exact command") {
                        SettingsField("Command", prompt: "move-node-to-workspace 3", text: field(rule.id, \.run))
                    }
                    Toggle("Keep checking later rules", isOn: viewModel.windowRuleBinding(
                        rule.id,
                        default: false,
                        get: { $0.checkFurtherCallbacks },
                        set: { $0.checkFurtherCallbacks = $1 },
                    ))
                } header: {
                    SectionLabel("Then run", "bolt")
                } footer: {
                    // The writer holds every rule edit back until each rule has a command.
                    if rule.run.trimmingCharacters(in: .whitespaces).isEmpty {
                        StatusLabel("No command yet, so rule changes aren't saved. Add one to save them.", kind: .warning)
                    }
                    SettingsHint("Applied once, when the window appears. Chain commands with `\(ConfigurationViewModel.commandSeparator.trimmingCharacters(in: .whitespaces))`. By default a matching rule stops the search.")
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
        viewModel.settings.windowRules.append(.init())
        selection = viewModel.settings.windowRules.last?.id
    }

    private func removeRule() {
        guard let selection else { return }
        viewModel.settings.windowRules.removeAll { $0.id == selection }
        viewModel.scheduleAutoSave()
        self.selection = nil
    }

    /// Whether the row shows the placeholder rather than a matcher.
    ///
    /// Asked of the rule, not of the rendered string: an app id of literally `(any window)` is legal
    /// free text, and comparing the summary would render a real matcher as prose.
    private func hasNoMatchers(_ r: Rule) -> Bool {
        r.appId.isEmpty && r.appNameRegex.isEmpty && r.windowTitleRegex.isEmpty && r.workspace.isEmpty
    }

    private func summary(_ r: Rule) -> String {
        var parts: [String] = []
        if !r.appId.isEmpty { parts.append(r.appId) }
        if !r.appNameRegex.isEmpty { parts.append("name~\(r.appNameRegex)") }
        if !r.windowTitleRegex.isEmpty { parts.append("title~\(r.windowTitleRegex)") }
        if !r.workspace.isEmpty { parts.append("ws=\(r.workspace)") }
        return parts.isEmpty ? Self.anyWindow : parts.joined(separator: " ")
    }

    private func field(_ id: Rule.ID, _ keyPath: WritableKeyPath<Rule, String>) -> Binding<String> {
        viewModel.windowRuleBinding(id, default: "", get: { $0[keyPath: keyPath] }, set: { $0[keyPath: keyPath] = $1 })
    }

    private func startupTiming(_ id: Rule.ID) -> Binding<String> {
        viewModel.windowRuleBinding(
            id,
            default: "any",
            get: {
                switch $0.duringStartup {
                    case true?: "startup"
                    case false?: "runtime"
                    case nil: "any"
                }
            },
            set: { rule, value in
                rule.duringStartup = switch value {
                    case "startup": true
                    case "runtime": false
                    default: nil
                }
            },
        )
    }

    private func guidedLayout(_ id: Rule.ID) -> Binding<GuidedWindowAction.Layout> {
        viewModel.windowRuleBinding(
            id,
            default: .unchanged,
            get: { parseGuidedWindowAction($0.run).layout },
            set: { rule, layout in
                var action = parseGuidedWindowAction(rule.run)
                guard !action.isCustom else { return }
                action.layout = layout
                rule.run = composeGuidedWindowAction(action)
            },
        )
    }

    private func guidedWorkspace(_ id: Rule.ID) -> Binding<String> {
        viewModel.windowRuleBinding(
            id,
            default: "",
            get: { parseGuidedWindowAction($0.run).workspace },
            set: { rule, workspace in
                var action = parseGuidedWindowAction(rule.run)
                guard !action.isCustom else { return }
                action.workspace = workspace.trimmingCharacters(in: .whitespaces)
                rule.run = composeGuidedWindowAction(action)
            },
        )
    }

    private func chooseApplication(for ruleID: Rule.ID) {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.prompt = "Choose"
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let complete: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
            Task { @MainActor in
                guard let i = viewModel.settings.windowRules.firstIndex(where: { $0.id == ruleID }) else { return }
                viewModel.settings.windowRules[i].appId = bundleID
                viewModel.scheduleAutoSave()
            }
        }
        // An accessory app cannot bring a detached open panel forward: `begin` shows it behind
        // whatever is frontmost, which reads as the button doing nothing while the invisible
        // panel swallows every click. A sheet attaches to the settings window instead, which
        // needs no app activation at all.
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.begin(completionHandler: complete)
        }
    }
}

@MainActor private enum ApplicationIconCache {
    enum Entry { case image(NSImage), missing }
    static var entries: [String: Entry] = [:]

    static func image(for bundleIdentifier: String) -> NSImage? {
        if let entry = entries[bundleIdentifier] {
            if case .image(let image) = entry { return image }
            return nil
        }
        // The key is whatever is in the App ID field, one entry per typed prefix, and this app
        // runs for weeks. ponytail: dump-and-refill cap; entries repopulate in one 140ms debounce,
        // so an LRU would be machinery for nothing.
        if entries.count >= 256 { entries.removeAll(keepingCapacity: true) }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            entries[bundleIdentifier] = .missing
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        entries[bundleIdentifier] = .image(image)
        return image
    }
}

/// Resolves through LaunchServices only after typing settles, then caches both hits and misses.
/// Looking up an application icon directly in a table cell body would query the on-disk app
/// database on every settings autosave and every character typed into App ID.
private struct ApplicationIcon: View {
    let bundleIdentifier: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().foregroundStyle(.tertiary)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
        .task(id: bundleIdentifier) {
            image = nil
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            image = ApplicationIconCache.image(for: bundleIdentifier)
        }
    }
}
