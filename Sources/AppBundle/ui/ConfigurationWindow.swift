import Common
import SwiftUI

public struct ConfigurationWindow: View {
    @StateObject private var viewModel = ConfigurationViewModel()
    /// Apple recommends restoring the last pane in a multi-pane Settings window. A stable string
    /// rather than an enum-backed integer keeps the preference readable and survives reordering.
    @AppStorage("settings.selectedPane") private var selectedPaneID = SettingsPane.general.rawValue

    public init() {}

    enum SettingsPane: String, CaseIterable, Identifiable {
        case general, gaps, keys, monitors, events, windowRules, rawToml

        var id: String { rawValue }

        var title: String {
            switch self {
                case .general: "General"
                case .gaps: "Gaps"
                case .keys: "Keys"
                case .monitors: "Monitors"
                case .events: "Events"
                case .windowRules: "Window Rules"
                case .rawToml: "Raw TOML"
            }
        }

        var symbol: String {
            switch self {
                case .general: "gearshape"
                case .gaps: "rectangle.split.3x3"
                case .keys: "keyboard"
                case .monitors: "display.2"
                case .events: "bolt"
                case .windowRules: "macwindow.badge.plus"
                case .rawToml: "doc.plaintext"
            }
        }
    }

    private var selectedPane: SettingsPane { SettingsPane(rawValue: selectedPaneID) ?? .general }

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
        TabView(selection: $selectedPaneID) {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem { paneLabel(.general) }
                .tag(SettingsPane.general.rawValue)

            GapsSettingsTab(viewModel: viewModel)
                // "square.resize" is SF Symbols 5 (macOS 14); this app targets 13, where it renders blank.
                .tabItem { paneLabel(.gaps) }
                .tag(SettingsPane.gaps.rawValue)

            KeyBindingsTab(viewModel: viewModel)
                .tabItem { paneLabel(.keys) }
                .tag(SettingsPane.keys.rawValue)

            WorkspacesMonitorsTab(viewModel: viewModel)
                .tabItem { paneLabel(.monitors) }
                .tag(SettingsPane.monitors.rawValue)

            CallbacksTab(viewModel: viewModel)
                .tabItem { paneLabel(.events) }
                .tag(SettingsPane.events.rawValue)

            WindowRulesTab(viewModel: viewModel)
                .tabItem { paneLabel(.windowRules) }
                .tag(SettingsPane.windowRules.rawValue)

            RawTomlTab(viewModel: viewModel)
                .tabItem { paneLabel(.rawToml) }
                .tag(SettingsPane.rawToml.rawValue)
        }
        .navigationTitle(selectedPane.title)
        // Wide enough that the Window Rules split view has room for a table AND a form; tall enough
        // that a grouped Form shows more than two sections before it starts scrolling.
        .frame(minWidth: 780, idealWidth: 880, minHeight: 520, idealHeight: 620)
        // `.windowResizability(.contentMinSize)` on the scene is not enough: a `Settings` scene
        // window ships without `.resizable` in its styleMask (verified: AXSize not settable), so
        // the minimums above were theoretical. The styleMask is the ground truth; set it there.
        .background(ResizableWindowEnforcer(minSize: NSSize(width: 780, height: 520)))
        // Structured panes apply live (debounced), so there is no Save button -- that is the macOS
        // convention, and it is only safe because an untouched section is never rewritten. The Raw
        // TOML tab has its own explicit Apply, since half-typed TOML is invalid most of the time.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The raw tab shows its own errors inline next to its Apply button.
            if let error = viewModel.errorMessage, selectedPane != .rawToml {
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
        .onAppear {
            // A removed or corrupt stored value must never leave TabView with no selected pane.
            if SettingsPane(rawValue: selectedPaneID) == nil { selectedPaneID = SettingsPane.general.rawValue }
        }
        // Flushed, not cancelled: closing the window inside the 600ms debounce used to drop the last edit.
        .onDisappear { Task { await viewModel.flushPendingAutoSave() } }
    }

    private func paneLabel(_ pane: SettingsPane) -> some View {
        Label(pane.title, systemImage: pane.symbol)
    }
}

/// Makes the hosting window user-resizable. Invisible; sits in the window's view hierarchy only to
/// reach the `NSWindow`, because a SwiftUI `Settings` scene ignores `windowResizability` at the
/// styleMask level and an overflowing pane in a fixed window is unrecoverable. Re-applied on every
/// update in case SwiftUI re-asserts the mask on a pane switch.
private struct ResizableWindowEnforcer: NSViewRepresentable {
    let minSize: NSSize

    final class EnforcerView: NSView {
        var minSize = NSSize.zero
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            enforce()
            // A first open lands here after `openSettingsWindow` has already returned, so this is where
            // a new settings window is put in front.
            if settingsWindow !== window {
                settingsWindow = window
                bringSettingsWindowForward()
            }
            // The scene re-asserts its own styleMask after this view lands in the window, so a
            // one-shot insert is silently undone. Watching window updates and re-inserting only
            // when the bit is missing wins that fight without churning the mask every pass.
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didUpdateNotification,
                    object: window,
                    queue: .main,
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.enforceIfNeeded() }
                }
            }
        }

        private func enforceIfNeeded() {
            if let window, !window.styleMask.contains(.resizable) { enforce() }
        }

        func enforce() {
            guard let window else { return }
            window.styleMask.insert(.resizable)
            window.contentMinSize = minSize
        }
    }

    func makeNSView(context: Context) -> EnforcerView {
        let view = EnforcerView()
        view.minSize = minSize
        return view
    }

    func updateNSView(_ view: EnforcerView, context: Context) {
        view.minSize = minSize
        view.enforce()
    }
}
