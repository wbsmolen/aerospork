import SwiftUI
import Common

struct WorkspaceAssignmentTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var selectedWorkspaceId: UUID?
    @State private var showingMonitorFingerprints = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Workspace to Monitor Assignment")
                    .font(.headline)
                Spacer()
                Button("Show Monitor Info") {
                    showingMonitorFingerprints.toggle()
                }
                .help("Display current monitor fingerprints")
            }
            .padding()
            
            // Assignment list
            List(selection: $selectedWorkspaceId) {
                ForEach($viewModel.workspaceAssignments) { $assignment in
                    WorkspaceAssignmentRow(assignment: $assignment, viewModel: viewModel)
                        .tag(assignment.id)
                }
                .onDelete { indices in
                    for index in indices {
                        viewModel.removeWorkspaceAssignment(at: index)
                    }
                }
            }
            .listStyle(InsetListStyle())
            
            // Bottom toolbar
            HStack {
                Button(action: {
                    viewModel.addWorkspaceAssignment()
                }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Add workspace assignment")
                
                Button(action: {
                    if let selectedId = selectedWorkspaceId,
                       let index = viewModel.workspaceAssignments.firstIndex(where: { $0.id == selectedId }) {
                        viewModel.removeWorkspaceAssignment(at: index)
                        selectedWorkspaceId = nil
                    }
                }) {
                    Image(systemName: "minus")
                }
                .buttonStyle(BorderlessButtonStyle())
                .disabled(selectedWorkspaceId == nil)
                .help("Remove selected workspace assignment")
                
                Spacer()
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .sheet(isPresented: $showingMonitorFingerprints) {
            MonitorInfoSheet()
        }
    }
}

struct WorkspaceAssignmentRow: View {
    @Binding var assignment: ConfigurationViewModel.WorkspaceAssignment
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var editingFingerprint = false
    
    var body: some View {
        HStack {
            TextField("Workspace", text: Binding(
                get: { assignment.workspaceName },
                set: { newValue in
                    assignment.workspaceName = newValue
                    viewModel.markAsModified()
                }
            ))
            .frame(width: 100)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Text("→")
                .foregroundColor(.secondary)
            
            Picker("Monitor", selection: Binding(
                get: { monitorTypeToString(assignment.monitorType) },
                set: { newValue in
                    assignment.monitorType = stringToMonitorType(newValue)
                    assignment.monitorDescription = newValue
                    viewModel.markAsModified()
                }
            )) {
                Group {
                    Text("Main").tag("main")
                    Text("Secondary").tag("secondary")
                    Divider()
                    ForEach(sortedMonitors.indices, id: \.self) { index in
                        Text("Monitor \(index + 1)").tag(String(index + 1))
                    }
                    Divider()
                    Text("Custom Pattern...").tag("__custom__")
                    Text("Fingerprint...").tag("__fingerprint__")
                }
            }
            .onChange(of: monitorTypeToString(assignment.monitorType)) { newValue in
                if newValue == "__fingerprint__" {
                    editingFingerprint = true
                }
            }
            
            if case .name(let pattern) = assignment.monitorType,
               pattern != "main" && pattern != "secondary" && Int(pattern) == nil {
                TextField("Pattern", text: Binding(
                    get: { pattern },
                    set: { newValue in
                        assignment.monitorType = .name(newValue)
                        assignment.monitorDescription = newValue
                        viewModel.markAsModified()
                    }
                ))
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .help("Regular expression to match monitor name")
            }
            
            if case .fingerprint = assignment.monitorType {
                Button("Edit") {
                    editingFingerprint = true
                }
                .help("Edit fingerprint properties")
            }
        }
        .sheet(isPresented: $editingFingerprint) {
            FingerprintEditor(assignment: $assignment, viewModel: viewModel)
        }
    }
    
    private func monitorTypeToString(_ type: ConfigurationViewModel.WorkspaceAssignment.MonitorType) -> String {
        switch type {
        case .name(let name):
            return name
        case .index(let index):
            return String(index)
        case .fingerprint:
            return "__fingerprint__"
        }
    }
    
    private func stringToMonitorType(_ string: String) -> ConfigurationViewModel.WorkspaceAssignment.MonitorType {
        if string == "__custom__" {
            return .name("pattern")
        } else if string == "__fingerprint__" {
            return .fingerprint(ConfigurationViewModel.WorkspaceAssignment.MonitorFingerprint())
        } else if let index = Int(string) {
            return .index(index)
        } else {
            return .name(string)
        }
    }
}

struct FingerprintEditor: View {
    @Binding var assignment: ConfigurationViewModel.WorkspaceAssignment
    @ObservedObject var viewModel: ConfigurationViewModel
    @Environment(\.dismiss) var dismiss
    @State private var fingerprint: ConfigurationViewModel.WorkspaceAssignment.MonitorFingerprint
    
    init(assignment: Binding<ConfigurationViewModel.WorkspaceAssignment>, viewModel: ConfigurationViewModel) {
        self._assignment = assignment
        self.viewModel = viewModel
        if case .fingerprint(let fp) = assignment.wrappedValue.monitorType {
            self._fingerprint = State(initialValue: fp)
        } else {
            self._fingerprint = State(initialValue: ConfigurationViewModel.WorkspaceAssignment.MonitorFingerprint())
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Monitor Fingerprint")
                .font(.headline)
            
            Form {
                TextField("Vendor ID (e.g., 0x410c)", text: Binding(
                    get: { fingerprint.vendorId ?? "" },
                    set: { fingerprint.vendorId = $0.isEmpty ? nil : $0 }
                ))
                
                TextField("Model ID (e.g., 0xa0b1)", text: Binding(
                    get: { fingerprint.modelId ?? "" },
                    set: { fingerprint.modelId = $0.isEmpty ? nil : $0 }
                ))
                
                TextField("Serial Number", text: Binding(
                    get: { fingerprint.serialNumber ?? "" },
                    set: { fingerprint.serialNumber = $0.isEmpty ? nil : $0 }
                ))
                
                TextField("Display Name Pattern", text: Binding(
                    get: { fingerprint.displayName ?? "" },
                    set: { fingerprint.displayName = $0.isEmpty ? nil : $0 }
                ))
                
                HStack {
                    TextField("Width", value: Binding(
                        get: { fingerprint.width ?? 0 },
                        set: { fingerprint.width = $0 == 0 ? nil : $0 }
                    ), format: .number)
                    .frame(width: 80)
                    
                    Text("×")
                    
                    TextField("Height", value: Binding(
                        get: { fingerprint.height ?? 0 },
                        set: { fingerprint.height = $0 == 0 ? nil : $0 }
                    ), format: .number)
                    .frame(width: 80)
                    
                    Text("pixels")
                }
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Done") {
                    assignment.monitorType = .fingerprint(fingerprint)
                    assignment.monitorDescription = "Fingerprint"
                    viewModel.markAsModified()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct MonitorInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var monitorInfo: [(name: String, fingerprint: String)] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current Monitor Information")
                .font(.headline)
            
            if monitorInfo.isEmpty {
                ProgressView("Loading monitor information...")
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(monitorInfo.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Monitor \(index + 1): \(monitorInfo[index].name)")
                                    .font(.headline)
                                Text("Fingerprint: \(monitorInfo[index].fingerprint)")
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
        .task {
            loadMonitorInfo()
        }
    }
    
    private func loadMonitorInfo() {
        monitorInfo = sortedMonitors.enumerated().map { (index, monitor) in
            var fingerprint = "Monitor \(index + 1)"
            
            // Try to get actual fingerprint if it's a LazyMonitor
            if let lazyMonitor = monitor as? LazyMonitor,
               let fp = lazyMonitor.fingerprint {
                fingerprint = fp.description
            }
            
            return (name: monitor.name, fingerprint: fingerprint)
        }
    }
}