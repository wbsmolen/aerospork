import SwiftUI
import Common

struct MonitorSelectionView: View {
    let assignment: Config.WorkspaceAssignment
    let monitors: [ConfigurationViewModel.MonitorInfo]
    let onSave: (Config.WorkspaceAssignment) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var editedAssignment: Config.WorkspaceAssignment
    @State private var selectedMonitorId: UUID?
    @State private var customPattern: String = ""
    @State private var useFingerprint: Bool = true
    @State private var partialFingerprint: PartialFingerprint
    
    struct PartialFingerprint: Equatable {
        var useVendor: Bool = true
        var useModel: Bool = true
        var useSerial: Bool = false
        var useResolution: Bool = false
    }
    
    init(assignment: Config.WorkspaceAssignment, monitors: [ConfigurationViewModel.MonitorInfo], onSave: @escaping (Config.WorkspaceAssignment) -> Void) {
        self.assignment = assignment
        self.monitors = monitors
        self.onSave = onSave
        self._editedAssignment = State(initialValue: assignment)
        self._partialFingerprint = State(initialValue: PartialFingerprint())
        
        // Initialize state based on assignment type
        if case .name(let pattern) = assignment.monitorType {
            self._customPattern = State(initialValue: pattern)
            self._useFingerprint = State(initialValue: false)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Configure Monitor Assignment")
                    .font(.headline)
                Spacer()
                Toggle("Force Assignment", isOn: $editedAssignment.isForceAssignment)
                    .help("Force assignment: workspace always returns to this monitor. Regular: moves on first detection only.")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Workspace configuration
                    Section {
                        HStack {
                            Text("Workspace:")
                            TextField("Name", text: $editedAssignment.workspaceName)
                                .frame(width: 100)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    
                    // Monitor selection method
                    Section {
                        Text("Monitor Selection Method")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Picker("", selection: $useFingerprint) {
                            Text("Select from Connected Monitors").tag(true)
                            Text("Custom Pattern").tag(false)
                        }
                        .pickerStyle(RadioGroupPickerStyle())
                    }
                    
                    if useFingerprint {
                        // Connected monitors selection
                        Section {
                            Text("Select Monitor")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            VStack(spacing: 8) {
                                ForEach(monitors) { monitor in
                                    MonitorSelectionRow(
                                        monitor: monitor,
                                        isSelected: selectedMonitorId == monitor.id,
                                        onSelect: {
                                            selectedMonitorId = monitor.id
                                            applyMonitorFingerprint(monitor)
                                        }
                                    )
                                }
                                
                                if monitors.isEmpty {
                                    Text("No monitors detected")
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                }
                            }
                        }
                        
                        // Fingerprint options
                        if selectedMonitorId != nil {
                            Section {
                                Text("Fingerprint Matching")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle("Match Vendor ID", isOn: $partialFingerprint.useVendor)
                                    Toggle("Match Model ID", isOn: $partialFingerprint.useModel)
                                    Toggle("Match Serial Number", isOn: $partialFingerprint.useSerial)
                                    Toggle("Match Resolution", isOn: $partialFingerprint.useResolution)
                                }
                                .onChange(of: partialFingerprint) { _ in
                                    updateFingerprintFromSelection()
                                }
                                
                                Text("Tip: Use fewer criteria for more flexible matching")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // Custom pattern input
                        Section {
                            Text("Monitor Pattern")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Pattern (e.g., 'Dell', 'main', '1')", text: $customPattern)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Text("Enter a monitor name pattern, 'main', 'secondary', or a number")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // Preview
                    Section {
                        Text("Assignment Preview")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        AssignmentPreview(assignment: editedAssignment)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save") {
                    if !useFingerprint {
                        editedAssignment.monitorType = .name(customPattern)
                        editedAssignment.monitorDescription = customPattern
                    }
                    onSave(editedAssignment)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }
    
    private var isValid: Bool {
        !editedAssignment.workspaceName.isEmpty &&
        (useFingerprint ? selectedMonitorId != nil : !customPattern.isEmpty)
    }
    
    private func applyMonitorFingerprint(_ monitor: ConfigurationViewModel.MonitorInfo) {
        let fp = Config.WorkspaceAssignment.MonitorFingerprint(
            vendorId: partialFingerprint.useVendor ? monitor.fingerprint.vendorId : nil,
            modelId: partialFingerprint.useModel ? monitor.fingerprint.modelId : nil,
            serialNumber: partialFingerprint.useSerial ? monitor.fingerprint.serialNumber : nil,
            displayName: monitor.fingerprint.displayName,
            width: partialFingerprint.useResolution ? monitor.fingerprint.widthPixels : nil,
            height: partialFingerprint.useResolution ? monitor.fingerprint.heightPixels : nil
        )
        
        editedAssignment.monitorType = .fingerprint(fp)
        editedAssignment.monitorDescription = monitor.name
    }
    
    private func updateFingerprintFromSelection() {
        guard let monitorId = selectedMonitorId,
              let monitor = monitors.first(where: { $0.id == monitorId }) else { return }
        applyMonitorFingerprint(monitor)
    }
}

struct MonitorSelectionRow: View {
    let monitor: ConfigurationViewModel.MonitorInfo
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: monitor.isMain ? "star.fill" : "display")
                .foregroundColor(monitor.isMain ? .yellow : .secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.name)
                    .fontWeight(.medium)
                
                Text("\(monitor.width)×\(monitor.height) • \(monitor.fingerprint.displayString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

struct AssignmentPreview: View {
    let assignment: Config.WorkspaceAssignment
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle()
                        .fill(assignment.isForceAssignment ? Color.orange : Color.blue)
                        .frame(width: 8, height: 8)
                    Text("Workspace \(assignment.workspaceName)")
                        .fontWeight(.medium)
                }
                
                Text(assignment.isForceAssignment ? "Force Assignment" : "Regular Assignment")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text("→")
                .font(.title2)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.monitorDescription)
                    .fontWeight(.medium)
                
                if case .fingerprint(let fp) = assignment.monitorType {
                    Text(fingerprintDescription(fp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func fingerprintDescription(_ fp: Config.WorkspaceAssignment.MonitorFingerprint) -> String {
        var parts: [String] = []
        if let vendor = fp.vendorId { parts.append("Vendor: \(vendor)") }
        if let model = fp.modelId { parts.append("Model: \(model)") }
        if let serial = fp.serialNumber { parts.append("Serial: \(serial)") }
        if let width = fp.width, let height = fp.height {
            parts.append("Resolution: \(width)×\(height)")
        }
        return parts.isEmpty ? "Any monitor" : parts.joined(separator: ", ")
    }
}