import Common
import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    private var configPath: String {
        (findCustomConfigUrl().urlOrNil ?? defaultConfigUrl).path(percentEncoded: false)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Start AeroSpork at login", isOn: viewModel.binding(\.startAtLogin))
                Toggle("Automatically unhide macOS hidden apps", isOn: viewModel.binding(\.automaticallyUnhideMacosHiddenApps))
                    .help("Undo ⌘H automatically, so hidden windows keep tiling")
                Toggle("Move workspaces to assigned monitors on connect", isOn: viewModel.binding(\.autoMoveWorkspacesOnMonitorConnect))
                    .help("Plug in a dock and your pinned workspaces go back to the monitors you assigned them. Off, they stay wherever they landed when the monitor went away.")
            } header: {
                SectionLabel("Startup & behaviour", "power")
            }

            Section {
                Toggle("Show icon in the menu bar", isOn: viewModel.binding(\.showMenuBarIcon))
                    .help("The workspace chips, and the menu with workspace switching and Settings in it")
                // Shows the *effective* value, which is not always the stored one: with the menu bar
                // icon off, `AppVisibility` forces the Dock icon on so Settings stays reachable.
                Toggle("Show icon in the Dock", isOn: Binding(
                    get: { viewModel.appVisibility.showsDockIcon },
                    set: { viewModel.binding(\.showDockIcon).wrappedValue = $0 },
                ))
                .disabled(viewModel.appVisibility.dockIconIsForced)
            } header: {
                SectionLabel("Appearance", "menubar.rectangle")
            } footer: {
                Text(viewModel.appVisibility.dockIconIsForced
                    ? "Both icons off would leave no way into Settings, so the Dock icon is kept. `aerospork open-settings` opens this window from anywhere if you would rather use a shortcut."
                    : "AeroSpork has no window of its own, so these two icons are the only ways back into Settings without the command line. `aerospork open-settings` opens this window from anywhere.")
            }

            Section {
                Picker("New workspaces use", selection: viewModel.binding(\.defaultRootContainerLayout)) {
                    Text("Tiles").tag("tiles")
                    Text("Accordion").tag("accordion")
                }
                .pickerStyle(.segmented)

                Picker("Split direction", selection: viewModel.binding(\.defaultRootContainerOrientation)) {
                    Text("Auto").tag("auto")
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                .pickerStyle(.segmented)

                NumberField("Accordion peek", value: viewModel.binding(\.accordionPadding))
            } header: {
                SectionLabel("Layout", "rectangle.split.3x1")
            } footer: {
                Text("Auto gives wide monitors a horizontal split and tall monitors a vertical one. The accordion peek is how much of the window behind stays visible; 0 stacks them exactly.")
            }

            Section {
                Toggle("Flatten single-child containers", isOn: viewModel.binding(\.enableNormalizationFlattenContainers))
                Toggle("Alternate orientation for nested containers", isOn: viewModel.binding(\.enableNormalizationOppositeOrientation))
            } header: {
                SectionLabel("Normalization", "wand.and.stars")
            } footer: {
                Text("Housekeeping applied after every layout change. Turn both off if you want the tree to stay exactly as you built it.")
            }

            Section {
                Picker("Keyboard layout", selection: viewModel.binding(\.keyMappingPreset)) {
                    Text("QWERTY").tag("qwerty")
                    Text("Dvorak").tag("dvorak")
                    Text("Colemak").tag("colemak")
                }
            } header: {
                SectionLabel("Keyboard", "keyboard")
            } footer: {
                Text("How the key names in your bindings map to physical keys. `alt-h` means the key labelled H on this layout.")
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
                        Text(configPath)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .truncationMode(.head)
                            .lineLimit(1)
                            .textSelection(.enabled)
                        CopyButton(value: configPath, help: "Copy path")
                    }
                }
            } header: {
                SectionLabel("About", "info.circle")
            }
        }
        .formStyle(.grouped)
    }
}
