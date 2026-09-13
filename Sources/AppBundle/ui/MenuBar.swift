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
            Label("Config not loaded — running defaults", systemImage: Banner.Kind.error.icon)
            Button("Show config error…") {
                showMessageInGui(filenameIfConsoleApp: nil, title: "AeroSpork config error", message: configLoadFailure ?? "")
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
        // Workspaces are created on demand and garbage-collected when empty unless the config declares
        // them, so every row here holds windows, owns a monitor, or is one the user listed. No header: a
        // list of monospaced names with a checkmark on the focused one does not need to be labelled.
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
        Button(viewModel.isEnabled ? "Pause tiling" : "Resume tiling") {
            runDetached("menuBarToggleTiling") {
                try await runSession(.menuBarButton, .forceRun) { () throws in
                    _ = try await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                        .run(.defaultEnv, .emptyStdin)
                }
            }
        }
        // Lowercase. An uppercase KeyEquivalent implies Shift to AppKit, so "E"/"Q" rendered as
        // Shift-Cmd-E / Shift-Cmd-Q and plain Cmd-Q did nothing while the menu was open.
        .keyboardShortcut("e", modifiers: .command)
        Divider()
        // Through `openSettingsWindow`, not `SettingsLink`. The link opens the scene without making the
        // app active, and an accessory app that is not active gets its window BEHIND every other app's
        // -- which, under a tiling layout that covers the screen, is nowhere (#40). The function still
        // opens the scene through the public `\.openSettings`, captured by the label below, which has
        // necessarily rendered by the time this menu is open.
        Button("Settings…") { openSettingsWindow() }
            .keyboardShortcut(",", modifiers: .command)
        // Only in a build that has a feed to check. Rendering a disabled row in a debug build
        // would be a permanent dead control, which is what the deleted settings submenu was.
        if Updater.shared.isEnabled {
            Button("Check for updates…") { Updater.shared.checkForUpdates() }
        }
        // Just terminate: `AeroSporkAppDelegate.applicationShouldTerminate` runs the cleanup for
        // every quit route, so doing it here too would mean two paths, one of which only this
        // button exercised -- which is how the other routes went unnoticed for so long.
        Button("Quit \(aeroSporkAppName)") { terminateApp() }
            .keyboardShortcut("q", modifiers: .command)
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
        bringSettingsWindowForward()
        return true
    }
    // On 14+ a nil opener means the menu bar label has not rendered yet -- `aerospork
    // open-settings` in the first seconds after launch lands here. Report that, rather than
    // falling through to the selector below: `sendAction` returns true for it while opening
    // nothing, which is the exact silent success this function was rewritten to stop. The command
    // then exits 0 having done nothing visible.
    if #available(macOS 14, *) { return false }
    // macOS 13 has no `\.openSettings`. The pre-Ventura selector is still the only route there.
    return NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
}

/// The settings window once it exists, recorded by the view inside it that already reaches it.
@MainActor weak var settingsWindow: NSWindow?

/// Puts the settings window in front of every other app's windows.
///
/// `activate` only asks. Activation is cooperative from macOS 14, so it can be refused while another
/// app is frontmost -- Terminal, when this runs for `aerospork open-settings` -- and the window then
/// opens behind the tiled windows that cover the screen. Ordering it front works either way. A first
/// open has no window yet at this point; `ResizableWindowEnforcer` calls this again once it lands.
@MainActor func bringSettingsWindowForward() {
    Task { @MainActor in
        guard let settingsWindow else { return }
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
    }
}
