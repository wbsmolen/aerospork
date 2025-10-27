import Foundation
import Common
import TOMLKit
import os.log

private let serviceLogger = Logger(subsystem: "com.wbs.j4", category: "config-service")

/// Service layer for configuration management
/// Provides clean API for UI to read/write configuration
@MainActor
protocol ConfigurationService {
    /// Load current configuration
    func loadConfiguration() async throws -> ConfigurationData

    /// Save configuration changes
    func saveConfiguration(_ data: ConfigurationData) async throws

    /// Validate configuration without saving
    func validate(_ data: ConfigurationData) -> [ValidationError]

    /// Reload configuration (triggers app refresh)
    func reloadConfiguration() async throws
}

/// Default implementation of ConfigurationService
@MainActor
class DefaultConfigurationService: ConfigurationService {
    private let writer = ConfigurationWriter()
    private let validator = ConfigurationValidator()

    func loadConfiguration() async throws -> ConfigurationData {
        serviceLogger.info("Loading configuration")

        // Read config file
        let configFile = findCustomConfigUrl()
        guard let configURL = configFile.urlOrNil else {
            throw ConfigurationServiceError.configNotFound
        }
        let configPath = configURL.path

        let content = try String(contentsOfFile: configPath, encoding: .utf8)

        // Parse TOML
        let tomlTable = try TOMLTable(string: content)

        // Convert to ConfigurationData
        let data = try parseConfigurationData(from: tomlTable, originalContent: content)

        serviceLogger.info("Configuration loaded successfully")
        return data
    }

    func saveConfiguration(_ data: ConfigurationData) async throws {
        serviceLogger.info("Saving configuration")

        // Validate first
        let errors = validate(data)
        let criticalErrors = errors.filter { $0.severity == .error }

        guard criticalErrors.isEmpty else {
            let message = criticalErrors.map(\.formattedMessage).joined(separator: "\n")
            throw ConfigurationServiceError.validationFailed(message)
        }

        // Log warnings but allow save
        let warnings = errors.filter { $0.severity == .warning }
        if !warnings.isEmpty {
            serviceLogger.warning("Configuration has warnings: \(warnings.map(\.message).joined(separator: "; "))")
        }

        // Convert ConfigurationData to Config
        let config = data.toConfig()

        // Get config path and original content
        let configFile = findCustomConfigUrl()
        guard let configURL = configFile.urlOrNil else {
            throw ConfigurationServiceError.configNotFound
        }
        let configPath = configURL.path

        let originalContent = try String(contentsOfFile: configPath, encoding: .utf8)

        // Write using ConfigurationWriter (preserves formatting)
        try writer.writeConfig(config, toFile: configPath, preservingOriginal: originalContent)

        // Reload configuration
        try await reloadConfiguration()

        serviceLogger.info("Configuration saved and reloaded successfully")
    }

    func validate(_ data: ConfigurationData) -> [ValidationError] {
        let config = data.toConfig()
        return validator.validate(config)
    }

    func reloadConfiguration() async throws {
        serviceLogger.info("Reloading configuration")

        // Call existing reloadConfig function
        let success = reloadConfig()

        guard success else {
            throw ConfigurationServiceError.reloadFailed
        }

        serviceLogger.info("Configuration reloaded successfully")
    }

    // MARK: - Private Helpers

    private func extractConstantValue<T>(_ dynamicValue: DynamicConfigValue<T>) -> T {
        switch dynamicValue {
        case .constant(let value):
            return value
        case .perMonitor(_, let defaultValue):
            // UI doesn't support per-monitor values yet, return default
            return defaultValue
        }
    }

    private func parseHexID(_ value: TOMLValueConvertible?) -> UInt32? {
        // Try as string with "0x" prefix
        if let stringValue = value?.string {
            if stringValue.hasPrefix("0x") || stringValue.hasPrefix("0X") {
                let hexString = String(stringValue.dropFirst(2))
                return UInt32(hexString, radix: 16)
            }
            // Try parsing as decimal
            return UInt32(stringValue)
        }
        // Try as direct integer
        if let intValue = value?.int {
            return UInt32(exactly: intValue)
        }
        return nil
    }

    private func parseConfigurationData(
        from tomlTable: TOMLTable,
        originalContent: String
    ) throws -> ConfigurationData {
        // Parse general settings
        let general = GeneralSettings(
            startAtLogin: tomlTable["start-at-login"]?.bool ?? config.startAtLogin,
            automaticallyUnhideMacosHiddenApps: tomlTable["automatically-unhide-macos-hidden-apps"]?.bool ?? config.automaticallyUnhideMacosHiddenApps,
            defaultRootContainerLayout: tomlTable["default-root-container-layout"]?.string ?? config.defaultRootContainerLayout.rawValue,
            defaultRootContainerOrientation: tomlTable["default-root-container-orientation"]?.string ?? config.defaultRootContainerOrientation.rawValue,
            accordionPadding: tomlTable["accordion-padding"]?.int ?? config.accordionPadding,
            enableNormalizationFlattenContainers: tomlTable["enable-normalization-flatten-containers"]?.bool ?? config.enableNormalizationFlattenContainers,
            enableNormalizationOppositeOrientation: tomlTable["enable-normalization-opposite-orientation-for-nested-containers"]?.bool ?? config.enableNormalizationOppositeOrientationForNestedContainers,
            autoMoveWorkspacesOnMonitorConnect: tomlTable["auto-move-workspaces-on-monitor-connect"]?.bool ?? config.autoMoveWorkspacesOnMonitorConnect
        )

        // Parse gaps (extract constant values, UI doesn't support per-monitor gaps yet)
        var gaps = GapsSettings(
            innerHorizontal: extractConstantValue(config.gaps.inner.horizontal),
            innerVertical: extractConstantValue(config.gaps.inner.vertical),
            outerTop: extractConstantValue(config.gaps.outer.top),
            outerBottom: extractConstantValue(config.gaps.outer.bottom),
            outerLeft: extractConstantValue(config.gaps.outer.left),
            outerRight: extractConstantValue(config.gaps.outer.right)
        )

        if let gapsTable = tomlTable["gaps"]?.table {
            if let inner = gapsTable["inner"]?.table {
                gaps.innerHorizontal = inner["horizontal"]?.int ?? gaps.innerHorizontal
                gaps.innerVertical = inner["vertical"]?.int ?? gaps.innerVertical
            }
            if let outer = gapsTable["outer"]?.table {
                gaps.outerTop = outer["top"]?.int ?? gaps.outerTop
                gaps.outerBottom = outer["bottom"]?.int ?? gaps.outerBottom
                gaps.outerLeft = outer["left"]?.int ?? gaps.outerLeft
                gaps.outerRight = outer["right"]?.int ?? gaps.outerRight
            }
        }

        // Parse workspace assignments
        var assignments: [WorkspaceAssignmentData] = []

        if let assignmentsTable = tomlTable["workspace-to-monitor-force-assignment"]?.table {
            for (workspace, value) in assignmentsTable {
                let assignment = parseWorkspaceAssignment(workspace: workspace, value: value)
                assignments.append(assignment)
            }
        }

        return ConfigurationData(
            general: general,
            gaps: gaps,
            workspaceAssignments: assignments,
            workspaceProfiles: [],
            activeProfileName: nil,
            originalContent: originalContent
        )
    }

    private func parseWorkspaceAssignment(
        workspace: String,
        value: TOMLValueConvertible
    ) -> WorkspaceAssignmentData {
        // Try to parse as string (monitor name/pattern)
        if let stringValue = value.string {
            return WorkspaceAssignmentData(
                workspaceName: workspace,
                monitorDescription: stringValue,
                monitorType: .name(stringValue),
                isForceAssignment: true
            )
        }

        // Try to parse as int (monitor index)
        if let intValue = value.int {
            return WorkspaceAssignmentData(
                workspaceName: workspace,
                monitorDescription: "\(intValue)",
                monitorType: .index(intValue),
                isForceAssignment: true
            )
        }

        // Try to parse as fingerprint table
        if let table = value.table,
           let fingerprintTable = table["fingerprint"]?.table {

            // Parse hex IDs (format: "0x1234" or as int)
            let vendorId = parseHexID(fingerprintTable["vendor_id"])
            let modelId = parseHexID(fingerprintTable["model_id"])

            let fp = MonitorFingerprintData(
                displayName: fingerprintTable["display_name"]?.string,
                vendorId: vendorId,
                modelId: modelId,
                serialNumber: fingerprintTable["serial_number"]?.string,
                width: fingerprintTable["width"]?.int,
                height: fingerprintTable["height"]?.int
            )

            return WorkspaceAssignmentData(
                workspaceName: workspace,
                monitorDescription: fp.description,
                monitorType: .fingerprint(fp),
                isForceAssignment: true
            )
        }

        // Fallback to string representation
        return WorkspaceAssignmentData(
            workspaceName: workspace,
            monitorDescription: "unknown",
            monitorType: .name("unknown"),
            isForceAssignment: true
        )
    }
}

// MARK: - Data Transfer Objects

/// Configuration data for UI layer
struct ConfigurationData {
    var general: GeneralSettings
    var gaps: GapsSettings
    var workspaceAssignments: [WorkspaceAssignmentData]
    var workspaceProfiles: [Config.WorkspaceProfile]
    var activeProfileName: String?

    // Keep original content for preservation
    var originalContent: String

    /// Convert to Config struct
    @MainActor func toConfig() -> Config {
        var config = config // Use global config as base

        // Apply general settings
        config.startAtLogin = general.startAtLogin
        config.automaticallyUnhideMacosHiddenApps = general.automaticallyUnhideMacosHiddenApps
        config.defaultRootContainerLayout = Layout(rawValue: general.defaultRootContainerLayout) ?? .tiles
        config.defaultRootContainerOrientation = DefaultContainerOrientation(rawValue: general.defaultRootContainerOrientation) ?? .auto
        config.accordionPadding = general.accordionPadding
        config.enableNormalizationFlattenContainers = general.enableNormalizationFlattenContainers
        config.enableNormalizationOppositeOrientationForNestedContainers = general.enableNormalizationOppositeOrientation
        config.autoMoveWorkspacesOnMonitorConnect = general.autoMoveWorkspacesOnMonitorConnect

        // Apply gaps (note: parameter order is vertical, horizontal for inner, and left, bottom, top, right for outer)
        config.gaps = Gaps(
            inner: .init(vertical: gaps.innerVertical, horizontal: gaps.innerHorizontal),
            outer: .init(left: gaps.outerLeft, bottom: gaps.outerBottom, top: gaps.outerTop, right: gaps.outerRight)
        )

        // Apply workspace assignments
        var assignments: [String: [MonitorDescription]] = [:]
        for assignment in workspaceAssignments {
            let monitor = assignment.toMonitorDescription()
            assignments[assignment.workspaceName] = [monitor]
        }
        config.workspaceToMonitorForceAssignment = assignments

        // Apply workspace profiles
        config.workspaceProfiles = workspaceProfiles
        config.activeProfileName = activeProfileName

        return config
    }
}

struct GeneralSettings {
    var startAtLogin: Bool
    var automaticallyUnhideMacosHiddenApps: Bool
    var defaultRootContainerLayout: String
    var defaultRootContainerOrientation: String
    var accordionPadding: Int
    var enableNormalizationFlattenContainers: Bool
    var enableNormalizationOppositeOrientation: Bool
    var autoMoveWorkspacesOnMonitorConnect: Bool
}

struct GapsSettings {
    var innerHorizontal: Int
    var innerVertical: Int
    var outerTop: Int
    var outerBottom: Int
    var outerLeft: Int
    var outerRight: Int
}

struct WorkspaceAssignmentData: Identifiable {
    let id = UUID()
    var workspaceName: String
    var monitorDescription: String
    var monitorType: MonitorTypeData
    var isForceAssignment: Bool

    enum MonitorTypeData {
        case name(String)
        case index(Int)
        case fingerprint(MonitorFingerprintData)
    }

    func toMonitorDescription() -> MonitorDescription {
        switch monitorType {
        case .name(let name):
            if name == "main" {
                return .main
            } else if name == "secondary" {
                return .secondary
            } else {
                return MonitorDescription.pattern(name) ?? .pattern(name, try! SendableRegex(name))
            }
        case .index(let idx):
            return .sequenceNumber(idx)
        case .fingerprint(let fp):
            return .fingerprint(MonitorFingerprintPatternData(
                vendorID: fp.vendorId,
                modelID: fp.modelId,
                serialNumber: fp.serialNumber,
                displayNamePattern: fp.displayName,
                widthPixels: fp.width,
                heightPixels: fp.height
            ))
        }
    }
}

struct MonitorFingerprintData: CustomStringConvertible {
    var displayName: String?
    var vendorId: UInt32?
    var modelId: UInt32?
    var serialNumber: String?
    var width: Int?
    var height: Int?

    var description: String {
        var parts: [String] = []
        if let name = displayName {
            parts.append(name)
        }
        if let resolution = width.flatMap({ w in height.map { h in "\(w)×\(h)" } }) {
            parts.append(resolution)
        }
        return parts.isEmpty ? "Monitor" : parts.joined(separator: " ")
    }
}

// MARK: - Errors

enum ConfigurationServiceError: Error, LocalizedError {
    case configNotFound
    case validationFailed(String)
    case reloadFailed
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "Configuration file not found"
        case .validationFailed(let message):
            return "Validation failed:\n\(message)"
        case .reloadFailed:
            return "Failed to reload configuration"
        case .parseFailed(let message):
            return "Failed to parse configuration: \(message)"
        }
    }
}
