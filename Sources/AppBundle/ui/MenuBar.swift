import Common
import Foundation
import SwiftUI

/// The menu is a *remote control*, not a control panel. Everything that is configuration lives in
/// Settings, everything that is documentation lives in the docs; what is left is the handful of
/// things you reach for with the mouse while windows are on screen: see where you are, jump to a
/// workspace, get out of a binding mode, pause tiling, open Settings, quit.
///
/// Removed on purpose (each was a permanent row paying for a once-a-year action):
///   * version line + "Copy version" -> Settings ▸ General ▸ About, with the same copy button;
///   * "Experimental UI Settings" -> deleted; it was four fake toggles (`Button { } label: {
///     Toggle(isOn: .constant(...)) }`) driving a `UserDefaults` key no other surface could see;
///   * "Open config in <editor>" -> Settings ▸ Raw TOML, next to the text it opens;
///   * "Reload config" -> `ConfigFileWatcher` already reloads on every write, from any editor.
///
/// Nothing here re-rasterizes anything: the label is `MenuBarLabel`, and it is only rebuilt when
/// `TrayMenuModel` actually publishes a changed value (`PerfInvariantsTest`).
@MainActor
public func menuBar(viewModel: TrayMenuModel) -> some Scene {
    // `isInserted` is how `show-menu-bar-icon` takes the icon away without tearing the scene out of
    // the App body. Read-only on purpose: the config file is the source of truth, and letting the
    // system write back here would fight the next reload.
    MenuBarExtra(isInserted: Binding(get: { viewModel.showsMenuBarIcon }, set: { _ in })) {
        // The only always-visible surface. A user whose config failed to parse is running a keymap
        // they never wrote, and every one of their bindings is gone -- they have to be told here,
        // not only in a startup dialog they already dismissed.
        if isRunningFallbackDefaults {
            Text("⚠ Config not loaded — running defaults")
            Button("Show config error…") {
                showMessageInGui(filenameIfConsoleApp: nil, title: "AeroSpork Config Error", message: configLoadFailure ?? "")
            }
            Divider()
        }
        // A binding mode swallows the whole keyboard, so someone who entered one by accident has no
        // shortcut left to leave with -- including the one that would have opened Settings. Only
        // rendered while a non-main mode is active, so it is not a permanent row.
        if let mode = viewModel.trayItems.first(where: { $0.type == .mode }) {
            Button("Leave “\(mode.name)” mode") {
                runDetached("menuBarLeaveMode") { try await runSession(.menuBarButton, .forceRun) { activateMode(mainModeId) } }
            }
            Divider()
        }
        // Workspaces are created on demand and garbage-collected when empty, so every row here is a
        // workspace that actually holds windows or owns a monitor. No header: a list of monospaced
        // names with a checkmark on the focused one does not need to be labelled.
        if let token: RunSessionGuard = .isServerEnabled {
            ForEach(viewModel.workspaces, id: \.name) { workspace in
                Button {
                    runDetached("menuBarWorkspace") {
                        try await runSession(.menuBarButton, token) { _ = Workspace.get(byName: workspace.name).focusWorkspace() }
                    }
                } label: {
                    // `Toggle(isOn: .constant(...))` inside a `Button` is the only way to get a
                    // menu checkmark out of SwiftUI; the Button is what makes it actually do
                    // something, which is exactly what the deleted settings submenu never did.
                    Toggle(isOn: .constant(workspace.isFocused)) {
                        Text(workspace.name).font(.system(.body, design: .monospaced)) + Text(workspace.suffix)
                    }
                }
            }
            Divider()
        }
        Button(viewModel.isEnabled ? "Pause Tiling" : "Resume Tiling") {
            runDetached("menuBarToggleTiling") {
                try await runSession(.menuBarButton, .forceRun) { () throws in
                    _ = try await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                        .run(.defaultEnv, .emptyStdin)
                }
            }
        }.keyboardShortcut("E", modifiers: .command)
        Divider()
        // `SettingsLink` rather than a Button that sends an action: it is the supported way to open
        // a `Settings` scene, and unlike the private selector it does not quietly do nothing.
        if #available(macOS 14, *) {
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",", modifiers: .command)
        } else {
            Button("Settings…") { openSettingsWindow() }
                .keyboardShortcut(",", modifiers: .command)
        }
        // Only in a build that has a feed to check. Rendering a disabled row in a debug build
        // would be a permanent dead control, which is what the deleted settings submenu was.
        if Updater.shared.isEnabled {
            Button("Check for Updates…") { Updater.shared.checkForUpdates() }
        }
        Button("Quit \(aeroSporkAppName)") {
            runDetached("menuBarQuit") {
                defer { terminateApp() }
                try await terminationHandler.beforeTermination()
            }
        }.keyboardShortcut("Q", modifiers: .command)
    } label: {
        settingsBridged(
            Group {
                if viewModel.isEnabled {
                    MenuBarLabel(text: viewModel.trayText, items: viewModel.trayItems)
                } else {
                    Image(systemName: "pause.circle.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            },
        )
    }
}

/// `\.openSettings`, lifted out of the SwiftUI environment so code that is not a view can call it.
/// The CLI's `open-settings` runs on the server with no environment to read from, which is why it
/// used to send `showSettingsWindow:` instead.
///
/// That selector is private, and on macOS 27 it stopped opening anything while *still being claimed
/// by the responder chain*: `sendAction` returns true, so `OpenSettingsCommand`'s error path never
/// fired and the command reported success having done nothing. A public API that fails loudly is
/// worth the indirection; `settingsOpener == nil` is a real state the caller has to handle.
@MainActor var settingsOpener: (() -> Void)?

/// Wraps the menu bar label, which is the one view in this scene that is always rendered, so the
/// bridge is live before anyone opens the menu. Attaching it to the menu *content* would only
/// capture the action after the user had already opened the menu once.
@available(macOS 14, *)
private struct SettingsBridge<Content: View>: View {
    @Environment(\.openSettings) private var openSettings
    let content: Content

    var body: some View {
        content.onAppear { settingsOpener = { openSettings() } }
    }
}

@MainActor @ViewBuilder
func settingsBridged(_ content: some View) -> some View {
    if #available(macOS 14, *) { SettingsBridge(content: content) } else { content }
}

/// Returns whether the window was actually asked to open, so callers can report failure instead of
/// silently succeeding.
@discardableResult
@MainActor func openSettingsWindow() -> Bool {
    NSApplication.shared.activate(ignoringOtherApps: true)
    if let settingsOpener {
        settingsOpener()
        return true
    }
    // macOS 13 has no `\.openSettings`. The pre-Ventura selector is still the only route there.
    return NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
}
