import Common
import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    /// Sparkle's setting is not observable, so the toggle shows this copy. Not read in a build that
    /// cannot check: that would create the updater for nothing.
    @State private var checksAutomatically = Updater.shared.isEnabled && Updater.shared.automaticallyChecksForUpdates

    var body: some View {
        Form {
            Section {
                Toggle("Start AeroSpork at login", isOn: viewModel.binding(\.settings.general.startAtLogin))
                Toggle("Automatically unhide macOS hidden apps", isOn: viewModel.binding(\.settings.general.automaticallyUnhideMacosHiddenApps))
                Toggle("Move workspaces to assigned monitors on connect", isOn: viewModel.binding(\.settings.general.autoMoveWorkspacesOnMonitorConnect))
            } header: {
                SectionLabel("Startup & behaviour", "power")
            } footer: {
                SettingsHint("Automatically unhiding macOS hidden apps undoes ⌘H so a hidden window keeps tiling. Moving workspaces on monitor connect puts each one back on the monitor you pinned it to; off, a workspace stays wherever it landed when that monitor disappeared.")
            }

            Section {
                Toggle("Show icon in the menu bar", isOn: viewModel.binding(\.settings.general.showMenuBarIcon))
                    .help("The workspace chips, and the menu with workspace switching and Settings in it")
                // Shows the *effective* value, which is not always the stored one: with the menu bar
                // icon off, `AppVisibility` forces the Dock icon on so Settings stays reachable.
                Toggle("Show icon in the Dock", isOn: Binding(
                    get: { viewModel.appVisibility.showsDockIcon },
                    set: { viewModel.binding(\.settings.general.showDockIcon).wrappedValue = $0 },
                ))
                .disabled(viewModel.appVisibility.dockIconIsForced)
            } header: {
                SectionLabel("Menu bar & Dock", "menubar.rectangle")
            } footer: {
                SettingsHint(viewModel.appVisibility.dockIconIsForced
                    ? "Both icons off would leave nothing visible that leads into Settings, so the Dock icon is kept. Opening AeroSpork again, or `aerospork open-settings`, also opens this window."
                    : "AeroSpork has no window of its own, so these two icons are the quickest way back into Settings. Opening AeroSpork again, or `aerospork open-settings`, also opens this window.")
            }

            Section {
                Picker("New workspaces use", selection: viewModel.binding(\.settings.general.defaultRootContainerLayout)) {
                    Text("Tiles").tag("tiles")
                    Text("Accordion").tag("accordion")
                }
                .pickerStyle(.segmented)

                Picker("Split direction", selection: viewModel.binding(\.settings.general.defaultRootContainerOrientation)) {
                    Text("Auto").tag("auto")
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                .pickerStyle(.segmented)

                Picker("New windows open", selection: viewModel.binding(\.settings.general.newWindowPlacement)) {
                    Text("Beside").tag("sibling")
                    Text("Nested").tag("nest")
                }
                .pickerStyle(.segmented)

                NumberField("Accordion peek", value: viewModel.binding(\.settings.general.accordionPadding))
            } header: {
                SectionLabel("Layout", "rectangle.split.3x1")
            } footer: {
                SettingsHint("Auto gives wide monitors a horizontal split and tall monitors a vertical one. Layout and split direction apply to new workspaces; existing ones keep theirs. Nested splits the focused window's tile between it and the new window, so the other windows keep their size; beside gives every window in the row a narrower share. The accordion peek is how much of the window behind stays visible; 0 stacks them exactly. It applies to any accordion container, not just new workspaces.")
            }

            Section {
                Toggle("Flatten single-child containers", isOn: viewModel.binding(\.settings.general.enableNormalizationFlattenContainers))
                Toggle("Alternate orientation for nested containers", isOn: viewModel.binding(\.settings.general.enableNormalizationOppositeOrientation))
            } header: {
                SectionLabel("Normalization", "wand.and.stars")
            } footer: {
                SettingsHint("Housekeeping applied after every layout change. Turning one off leaves the tree as it is; it does not undo earlier changes. Turn both off if you want the tree to stay exactly as you built it.")
            }

            Section {
                Picker("Keyboard layout", selection: viewModel.binding(\.settings.keyMappingPreset)) {
                    Text("QWERTY").tag("qwerty")
                    Text("Dvorak").tag("dvorak")
                    Text("Colemak").tag("colemak")
                }
            } header: {
                SectionLabel("Keyboard", "keyboard")
            } footer: {
                SettingsHint("How the key names in your bindings map to physical keys. `alt-h` means the key labelled H on this layout.")
            }

            // Was a permanently visible menu bar row plus a "Copy version to clipboard" row below
            // it. It belongs where you go once, when filing a bug.
            Section {
                LabeledContent("Version") {
                    HStack(spacing: 6) {
                        Text("\(aeroSporkAppVersion) (\(gitShortHash))")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        CopyButton(value: "\(aeroSporkAppName) v\(aeroSporkAppVersion) \(gitHash)", help: "Copy full version for a bug report")
                    }
                }
                LabeledContent("Config file") {
                    HStack(spacing: 6) {
                        Text(viewModel.configPath)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .truncationMode(.head)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        CopyButton(value: viewModel.configPath, help: "Copy path")
                    }
                }
                // Only in a build that has a feed to check, like the menu's row. Not a config key, so
                // the writer is not involved.
                if Updater.shared.isEnabled {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { checksAutomatically },
                        set: {
                            checksAutomatically = $0
                            Updater.shared.automaticallyChecksForUpdates = $0
                        },
                    ))
                    LabeledContent("Updates") {
                        Button("Check for updates…") { Updater.shared.checkForUpdates() }
                    }
                }
            } header: {
                SectionLabel("About", "info.circle")
            }
        }
        .formStyle(.grouped)
    }
}
