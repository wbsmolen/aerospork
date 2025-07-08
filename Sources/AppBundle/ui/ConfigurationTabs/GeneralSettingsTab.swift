import SwiftUI
import Common

struct GeneralSettingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    
    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Start AeroSpace at Login", isOn: Binding(
                    get: { viewModel.startAtLogin },
                    set: { 
                        viewModel.startAtLogin = $0
                        viewModel.markAsModified()
                    }
                ))
                .help("Launch AeroSpace automatically when you log in to your Mac")
            }
            
            Section("Window Management") {
                Toggle("Automatically unhide macOS hidden apps", isOn: Binding(
                    get: { viewModel.automaticallyUnhideMacosHiddenApps },
                    set: { 
                        viewModel.automaticallyUnhideMacosHiddenApps = $0
                        viewModel.markAsModified()
                    }
                ))
                .help("When enabled, AeroSpace will automatically unhide apps that were hidden using Command+H")
            }
            
            Section("Monitor Management") {
                Toggle("Auto-move workspaces on monitor connect", isOn: Binding(
                    get: { viewModel.autoMoveWorkspacesOnMonitorConnect },
                    set: { 
                        viewModel.autoMoveWorkspacesOnMonitorConnect = $0
                        viewModel.markAsModified()
                    }
                ))
                .help("When enabled, workspaces will automatically move to their assigned monitors when a monitor is connected")
            }
            
            Section("Layout") {
                HStack {
                    Text("Default root container layout:")
                    Picker("", selection: Binding(
                        get: { viewModel.defaultRootContainerLayout },
                        set: { 
                            viewModel.defaultRootContainerLayout = $0
                            viewModel.markAsModified()
                        }
                    )) {
                        Text("Tiles").tag("tiles")
                        Text("Accordion").tag("accordion")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .help("Choose the default layout style for new workspaces")
                }
                
                HStack {
                    Text("Default root container orientation:")
                    Picker("", selection: Binding(
                        get: { viewModel.defaultRootContainerOrientation },
                        set: { 
                            viewModel.defaultRootContainerOrientation = $0
                            viewModel.markAsModified()
                        }
                    )) {
                        Text("Auto").tag("auto")
                        Text("Horizontal").tag("horizontal")
                        Text("Vertical").tag("vertical")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .help("Choose the default orientation for tiling windows")
                }
                
                HStack {
                    Text("Accordion padding:")
                    TextField("", value: Binding(
                        get: { viewModel.accordionPadding },
                        set: { 
                            viewModel.accordionPadding = $0
                            viewModel.markAsModified()
                        }
                    ), format: .number)
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("pixels")
                    Spacer()
                }
                .help("Padding between windows in accordion layout")
            }
            
            Section("Normalization") {
                Toggle("Enable flatten containers", isOn: Binding(
                    get: { viewModel.enableNormalizationFlattenContainers },
                    set: { 
                        viewModel.enableNormalizationFlattenContainers = $0
                        viewModel.markAsModified()
                    }
                ))
                .help("Automatically flatten containers with only one child")
                
                Toggle("Enable opposite orientation for nested containers", isOn: Binding(
                    get: { viewModel.enableNormalizationOppositeOrientation },
                    set: { 
                        viewModel.enableNormalizationOppositeOrientation = $0
                        viewModel.markAsModified()
                    }
                ))
                .help("Automatically use opposite orientation for nested containers")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}