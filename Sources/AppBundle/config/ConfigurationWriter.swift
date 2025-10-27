import Foundation
import Common
import TOMLKit
import os.log

private let writerLogger = Logger(subsystem: "com.wbs.aerospork", category: "config-writer")

/// Writes configuration back to TOML file while preserving formatting, comments, and sections
/// that are not managed by the UI
@MainActor
struct ConfigurationWriter {

    /// Write configuration changes back to TOML file
    /// - Parameters:
    ///   - config: The configuration to write
    ///   - path: Path to TOML config file
    ///   - originalContent: Original TOML file content (for preservation)
    /// - Throws: ConfigurationWriteError if writing fails
    func writeConfig(
        _ config: Config,
        toFile path: String,
        preservingOriginal originalContent: String
    ) throws {
        writerLogger.info("Writing config to: \(path)")

        // Create backup before writing
        let backupPath = path + ".backup"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)

        // Parse original content into sections
        var sections = parseSections(originalContent)

        // Update each managed section
        updateGeneralSettings(&sections, config: config)
        updateGapsSection(&sections, config: config)
        updateWorkspaceAssignments(&sections, config: config)
        updateWorkspaceProfiles(&sections, config: config)

        // Reassemble with preserved formatting
        let result = reassemble(sections)

        // Write atomically
        try result.write(toFile: path, atomically: true, encoding: .utf8)

        writerLogger.info("Config written successfully")
    }

    // MARK: - Section Parsing

    /// Parse TOML content into logical sections
    private func parseSections(_ content: String) -> [ConfigSection] {
        var sections: [ConfigSection] = []
        var currentSection: ConfigSection?
        var currentLines: [String] = []

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect section headers
            if trimmed.starts(with: "[") && trimmed.hasSuffix("]") {
                // Save previous section
                if let section = currentSection {
                    sections.append(ConfigSection(
                        name: section.name,
                        lines: currentLines,
                        startIndex: section.startIndex
                    ))
                }

                // Start new section
                let sectionName = trimmed
                    .dropFirst() // Remove [
                    .dropLast()  // Remove ]
                    .trimmingCharacters(in: .whitespaces)

                currentSection = ConfigSection(
                    name: String(sectionName),
                    lines: [line],
                    startIndex: sections.count
                )
                currentLines = [line]
            } else {
                // Add line to current section
                currentLines.append(line)
            }
        }

        // Save final section
        if let section = currentSection {
            sections.append(ConfigSection(
                name: section.name,
                lines: currentLines,
                startIndex: section.startIndex
            ))
        } else if !currentLines.isEmpty {
            // Handle content before first section (preamble)
            sections.append(ConfigSection(
                name: "",
                lines: currentLines,
                startIndex: 0
            ))
        }

        return sections
    }

    // MARK: - Section Updates

    /// Update general settings properties
    private func updateGeneralSettings(_ sections: inout [ConfigSection], config: Config) {
        // Find or create root section
        let rootIndex = sections.firstIndex { $0.name.isEmpty } ?? 0
        var lines = rootIndex < sections.count ? sections[rootIndex].lines : []

        // Update simple properties
        updateProperty(&lines, key: "start-at-login", value: config.startAtLogin)
        updateProperty(&lines, key: "automatically-unhide-macos-hidden-apps",
                      value: config.automaticallyUnhideMacosHiddenApps)
        updateProperty(&lines, key: "default-root-container-layout",
                      value: config.defaultRootContainerLayout.rawValue)
        updateProperty(&lines, key: "default-root-container-orientation",
                      value: config.defaultRootContainerOrientation.rawValue)
        updateProperty(&lines, key: "accordion-padding", value: config.accordionPadding)
        updateProperty(&lines, key: "enable-normalization-flatten-containers",
                      value: config.enableNormalizationFlattenContainers)
        updateProperty(&lines, key: "enable-normalization-opposite-orientation-for-nested-containers",
                      value: config.enableNormalizationOppositeOrientationForNestedContainers)
        updateProperty(&lines, key: "auto-move-workspaces-on-monitor-connect",
                      value: config.autoMoveWorkspacesOnMonitorConnect)

        // Update or insert section
        if rootIndex < sections.count {
            sections[rootIndex].lines = lines
        } else {
            sections.append(ConfigSection(name: "", lines: lines, startIndex: 0))
        }
    }

    /// Update gaps configuration section
    private func updateGapsSection(_ sections: inout [ConfigSection], config: Config) {
        // Remove existing gaps sections
        sections.removeAll { $0.name.starts(with: "gaps") }

        // Build new gaps section - extract constant values from DynamicConfigValue
        var gapsLines: [String] = []
        gapsLines.append("")
        gapsLines.append("[gaps]")
        gapsLines.append("[gaps.inner]")
        gapsLines.append("horizontal = \(extractConstantValue(config.gaps.inner.horizontal))")
        gapsLines.append("vertical = \(extractConstantValue(config.gaps.inner.vertical))")
        gapsLines.append("")
        gapsLines.append("[gaps.outer]")
        gapsLines.append("top = \(extractConstantValue(config.gaps.outer.top))")
        gapsLines.append("bottom = \(extractConstantValue(config.gaps.outer.bottom))")
        gapsLines.append("left = \(extractConstantValue(config.gaps.outer.left))")
        gapsLines.append("right = \(extractConstantValue(config.gaps.outer.right))")

        // Insert gaps section after root section
        let insertIndex = sections.firstIndex { !$0.name.isEmpty } ?? sections.count
        sections.insert(ConfigSection(name: "gaps", lines: gapsLines, startIndex: insertIndex),
                       at: insertIndex)
    }

    /// Extract constant value from DynamicConfigValue
    private func extractConstantValue<T>(_ dynamicValue: DynamicConfigValue<T>) -> T {
        switch dynamicValue {
        case .constant(let value):
            return value
        case .perMonitor(_, let defaultValue):
            return defaultValue
        }
    }

    /// Update workspace-to-monitor force assignment section
    private func updateWorkspaceAssignments(_ sections: inout [ConfigSection], config: Config) {
        // Remove existing workspace assignment sections
        sections.removeAll { $0.name.starts(with: "workspace-to-monitor-force-assignment") }

        guard !config.workspaceToMonitorForceAssignment.isEmpty else { return }

        // Build new assignments section
        var assignmentLines: [String] = []
        assignmentLines.append("")
        assignmentLines.append("[workspace-to-monitor-force-assignment]")

        for (workspace, monitors) in config.workspaceToMonitorForceAssignment.sorted(by: { $0.key < $1.key }) {
            guard let monitor = monitors.first else { continue }

            let value = formatMonitorDescription(monitor)
            assignmentLines.append("\(workspace) = \(value)")
        }

        // Insert assignments section
        let insertIndex = sections.count
        sections.append(ConfigSection(
            name: "workspace-to-monitor-force-assignment",
            lines: assignmentLines,
            startIndex: insertIndex
        ))
    }

    /// Update workspace profiles section
    private func updateWorkspaceProfiles(_ sections: inout [ConfigSection], config: Config) {
        // Remove existing workspace profile sections
        sections.removeAll { $0.name.starts(with: "workspace-profile") }

        // Remove active-profile if it exists (we'll add it back if needed)
        sections.removeAll { section in
            section.lines.contains(where: { $0.trimmingCharacters(in: .whitespaces).starts(with: "active-profile") })
        }

        guard !config.workspaceProfiles.isEmpty else { return }

        // Build profile sections - each profile is a [[workspace-profile]] array item
        for profile in config.workspaceProfiles {
            var profileLines: [String] = []
            profileLines.append("")
            profileLines.append("[[workspace-profile]]")
            profileLines.append("name = '\(profile.name)'")
            profileLines.append("")
            profileLines.append("[workspace-profile.assignments]")

            for assignment in profile.assignments.sorted(by: { $0.workspaceName < $1.workspaceName }) {
                let monitorValue: String
                switch assignment.monitorType {
                case .name(let name):
                    monitorValue = "'\(name)'"
                case .index(let idx):
                    monitorValue = "\(idx)"
                case .fingerprint(let fp):
                    // Format fingerprint as inline table
                    var parts: [String] = []
                    if let vendorId = fp.vendorId {
                        parts.append("vendor_id = '\(vendorId)'")
                    }
                    if let modelId = fp.modelId {
                        parts.append("model_id = '\(modelId)'")
                    }
                    if let serialNumber = fp.serialNumber {
                        parts.append("serial_number = '\(serialNumber)'")
                    }
                    if let displayName = fp.displayName {
                        parts.append("display_name = '\(displayName)'")
                    }
                    if let width = fp.width, let height = fp.height {
                        parts.append("width = \(width)")
                        parts.append("height = \(height)")
                    }
                    monitorValue = "{ fingerprint = { \(parts.joined(separator: ", ")) } }"
                }
                profileLines.append("\(assignment.workspaceName) = \(monitorValue)")
            }

            let insertIndex = sections.count
            sections.append(ConfigSection(
                name: "workspace-profile",
                lines: profileLines,
                startIndex: insertIndex
            ))
        }

        // Add active-profile setting if set
        if let activeProfile = config.activeProfileName {
            var activeProfileLines: [String] = []
            activeProfileLines.append("")
            activeProfileLines.append("active-profile = '\(activeProfile)'")

            let insertIndex = sections.count
            sections.append(ConfigSection(
                name: "active-profile-setting",
                lines: activeProfileLines,
                startIndex: insertIndex
            ))
        }
    }

    // MARK: - Property Updates

    /// Update a simple property in lines array
    private func updateProperty<T>(_ lines: inout [String], key: String, value: T) {
        let formattedValue: String
        if let boolValue = value as? Bool {
            formattedValue = boolValue ? "true" : "false"
        } else if let intValue = value as? Int {
            formattedValue = "\(intValue)"
        } else if let stringValue = value as? String {
            formattedValue = "'\(stringValue)'"
        } else {
            formattedValue = "\(value)"
        }

        // Try to find and update existing property
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            // Skip comments and section headers
            if trimmed.starts(with: "#") || trimmed.starts(with: "[") { continue }

            // Check if this line defines our property
            if trimmed.starts(with: "\(key) =") || trimmed.starts(with: "\(key)=") {
                // Preserve indentation
                let leadingWhitespace = lines[i].prefix(while: { $0.isWhitespace })
                lines[i] = "\(leadingWhitespace)\(key) = \(formattedValue)"
                return
            }
        }

        // Property not found, append it
        lines.append("\(key) = \(formattedValue)")
    }

    /// Format monitor description for TOML
    private func formatMonitorDescription(_ monitor: MonitorDescription) -> String {
        switch monitor {
        case .main:
            return "'main'"
        case .secondary:
            return "'secondary'"
        case .pattern(let pattern, _):
            return "'\(pattern)'"
        case .sequenceNumber(let idx):
            return "\(idx)"
        case .fingerprint(let fp):
            return formatFingerprint(fp)
        }
    }

    /// Format fingerprint as inline TOML table
    private func formatFingerprint(_ fp: MonitorFingerprintPatternData) -> String {
        var parts: [String] = []

        if let displayName = fp.displayNamePattern {
            parts.append("display_name = '\(displayName)'")
        }
        if let vendorID = fp.vendorID {
            parts.append("vendor_id = '0x\(String(format: "%04X", vendorID))'")
        }
        if let modelID = fp.modelID {
            parts.append("model_id = '0x\(String(format: "%04X", modelID))'")
        }
        if let serialNumber = fp.serialNumber {
            parts.append("serial_number = '\(serialNumber)'")
        }
        if let width = fp.widthPixels, let height = fp.heightPixels {
            parts.append("width = \(width)")
            parts.append("height = \(height)")
        }

        return "{ fingerprint = { \(parts.joined(separator: ", ")) } }"
    }

    // MARK: - Reassembly

    /// Reassemble sections into final TOML content
    private func reassemble(_ sections: [ConfigSection]) -> String {
        sections.map { section in
            section.lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }
}

// MARK: - Supporting Types

/// Represents a logical section of TOML configuration
private struct ConfigSection {
    var name: String
    var lines: [String]
    var startIndex: Int
}

/// Errors that can occur during configuration writing
enum ConfigurationWriteError: Error, LocalizedError {
    case fileNotFound(String)
    case permissionDenied(String)
    case invalidToml(String)
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Config file not found: \(path)"
        case .permissionDenied(let path):
            return "Permission denied writing to: \(path)"
        case .invalidToml(let message):
            return "Invalid TOML: \(message)"
        case .backupFailed(let message):
            return "Failed to create backup: \(message)"
        }
    }
}
