import Common
import SwiftUI

public struct ConfigurationWindow: View {
    @StateObject private var viewModel = ConfigurationViewModel()
    @State private var selectedTab = Tab.general

    public init() {}

    private enum Tab: Hashable {
        case general, gaps, keybindings, workspaces, callbacks, rules, raw
    }

    public var body: some View {
        VStack(spacing: 0) {
            // The startup error dialog is modal-and-gone. Without a persistent banner, an app
            // running the bundled default keymap looks exactly like one running the user's config.
            if isRunningFallbackDefaults {
                Banner(
                    "Your config was not loaded — AeroSpork is running built-in defaults. Fix the errors below and save; the config reloads by itself.\n\(configLoadFailure ?? "")",
                    kind: .error,
                )
            } else if !configWarnings.isEmpty {
                Banner(configWarnings.joined(separator: "\n"), kind: .warning)
            }
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)

            GapsSettingsTab(viewModel: viewModel)
                // "square.resize" is SF Symbols 5 (macOS 14); this app targets 13, where it renders blank.
                .tabItem { Label("Gaps", systemImage: "rectangle.split.3x3") }
                .tag(Tab.gaps)

            KeyBindingsTab(viewModel: viewModel)
                .tabItem { Label("Keys", systemImage: "keyboard") }
                .tag(Tab.keybindings)

            WorkspacesMonitorsTab(viewModel: viewModel)
                .tabItem { Label("Monitors", systemImage: "display.2") }
                .tag(Tab.workspaces)

            CallbacksTab(viewModel: viewModel)
                .tabItem { Label("Events", systemImage: "bolt") }
                .tag(Tab.callbacks)

            WindowRulesTab(viewModel: viewModel)
                .tabItem { Label("Window Rules", systemImage: "macwindow.badge.plus") }
                .tag(Tab.rules)

            RawTomlTab(viewModel: viewModel)
                .tabItem { Label("Raw TOML", systemImage: "doc.plaintext") }
                .tag(Tab.raw)
        }
        // Wide enough that the Window Rules split view has room for a table AND a form; tall enough
        // that a grouped Form shows more than two sections before it starts scrolling.
        .frame(minWidth: 780, idealWidth: 880, minHeight: 520, idealHeight: 620)
        // Structured tabs apply live (debounced), so there is no Save button -- that is the macOS
        // convention, and it is only safe because an untouched section is never rewritten. The Raw
        // TOML tab has its own explicit Apply, since half-typed TOML is invalid most of the time.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The raw tab shows its own errors inline next to its Apply button.
            if let error = viewModel.errorMessage, selectedTab != .raw {
                VStack(spacing: 0) {
                    Divider()
                    StatusLabel(error, kind: .error)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                }
                .background(Banner.Kind.error.tint.opacity(0.13))
            }
        }
        .task { await viewModel.loadConfiguration() }
        .onDisappear { viewModel.cancelPendingAutoSave() }
    }
}
