import Foundation
import Common

/// Validates configuration values before saving
@MainActor
struct ConfigurationValidator {

    /// Validate entire configuration
    /// - Parameter config: Configuration to validate
    /// - Returns: Array of validation errors (empty if valid)
    func validate(_ config: Config) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Validate basic settings
        errors.append(contentsOf: validateBasicSettings(config))

        // Validate gaps
        errors.append(contentsOf: validateGaps(config.gaps))

        // Validate workspace assignments
        errors.append(contentsOf: validateWorkspaceAssignments(config.workspaceToMonitorForceAssignment))

        // Validate performance config
        errors.append(contentsOf: validatePerformanceConfig(config.performanceConfig))

        return errors
    }

    // MARK: - Basic Settings Validation

    private func validateBasicSettings(_ config: Config) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Validate accordion padding
        if config.accordionPadding < 0 {
            errors.append(ValidationError(
                property: "accordion-padding",
                message: "Accordion padding must be non-negative (got \(config.accordionPadding))"
            ))
        }

        if config.accordionPadding > 1000 {
            errors.append(ValidationError(
                property: "accordion-padding",
                message: "Accordion padding is too large (got \(config.accordionPadding), max 1000)"
            ))
        }

        return errors
    }

    // MARK: - Gaps Validation

    private func validateGaps(_ gaps: Gaps) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Extract constant values for validation (UI doesn't support per-monitor gaps yet)
        let innerH = extractConstant(gaps.inner.horizontal)
        let innerV = extractConstant(gaps.inner.vertical)
        let outerT = extractConstant(gaps.outer.top)
        let outerB = extractConstant(gaps.outer.bottom)
        let outerL = extractConstant(gaps.outer.left)
        let outerR = extractConstant(gaps.outer.right)

        // Validate inner gaps
        if innerH < 0 {
            errors.append(ValidationError(
                property: "gaps.inner.horizontal",
                message: "Inner horizontal gap must be non-negative (got \(innerH))"
            ))
        }

        if innerV < 0 {
            errors.append(ValidationError(
                property: "gaps.inner.vertical",
                message: "Inner vertical gap must be non-negative (got \(innerV))"
            ))
        }

        // Validate outer gaps
        if outerT < 0 {
            errors.append(ValidationError(
                property: "gaps.outer.top",
                message: "Outer top gap must be non-negative (got \(outerT))"
            ))
        }

        if outerB < 0 {
            errors.append(ValidationError(
                property: "gaps.outer.bottom",
                message: "Outer bottom gap must be non-negative (got \(outerB))"
            ))
        }

        if outerL < 0 {
            errors.append(ValidationError(
                property: "gaps.outer.left",
                message: "Outer left gap must be non-negative (got \(outerL))"
            ))
        }

        if outerR < 0 {
            errors.append(ValidationError(
                property: "gaps.outer.right",
                message: "Outer right gap must be non-negative (got \(outerR))"
            ))
        }

        // Warn about large gaps
        let maxGap = max(innerH, innerV, outerT, outerB, outerL, outerR)

        if maxGap > 200 {
            errors.append(ValidationError(
                property: "gaps",
                message: "Very large gap detected (\(maxGap)px). This may significantly reduce usable window space.",
                severity: .warning
            ))
        }

        return errors
    }

    private func extractConstant<T>(_ dynamicValue: DynamicConfigValue<T>) -> T {
        switch dynamicValue {
        case .constant(let value):
            return value
        case .perMonitor(_, let defaultValue):
            return defaultValue
        }
    }

    // MARK: - Workspace Assignment Validation

    private func validateWorkspaceAssignments(
        _ assignments: [String: [MonitorDescription]]
    ) -> [ValidationError] {
        var errors: [ValidationError] = []

        for (workspace, monitors) in assignments {
            // Validate workspace name
            if let error = validateWorkspaceName(workspace) {
                errors.append(error)
            }

            // Check for empty monitor list
            if monitors.isEmpty {
                errors.append(ValidationError(
                    property: "workspace-to-monitor-force-assignment.\(workspace)",
                    message: "Workspace '\(workspace)' has no monitor assignment"
                ))
            }

            // Validate each monitor description
            for monitor in monitors {
                if let error = validateMonitorDescription(monitor, for: workspace) {
                    errors.append(error)
                }
            }
        }

        // Check for duplicate assignments
        var assignedWorkspaces = Set<String>()
        for workspace in assignments.keys {
            if !assignedWorkspaces.insert(workspace).inserted {
                errors.append(ValidationError(
                    property: "workspace-to-monitor-force-assignment",
                    message: "Duplicate assignment for workspace '\(workspace)'"
                ))
            }
        }

        return errors
    }

    private func validateWorkspaceName(_ name: String) -> ValidationError? {
        // Workspace names must be valid identifiers
        guard !name.isEmpty else {
            return ValidationError(
                property: "workspace",
                message: "Workspace name cannot be empty"
            )
        }

        // Check if name is parseable
        let result = WorkspaceName.parse(name)
        switch result {
        case .failure(let error):
            return ValidationError(
                property: "workspace",
                message: "Invalid workspace name '\(name)': \(error)"
            )
        case .success:
            return nil
        }
    }

    private func validateMonitorDescription(
        _ monitor: MonitorDescription,
        for workspace: String
    ) -> ValidationError? {
        switch monitor {
        case .fingerprint(let fp):
            // Validate fingerprint has at least one identifying property
            let hasIdentifier = fp.displayNamePattern != nil ||
                               fp.vendorID != nil ||
                               fp.modelID != nil ||
                               fp.serialNumber != nil

            if !hasIdentifier {
                return ValidationError(
                    property: "workspace-to-monitor-force-assignment.\(workspace)",
                    message: "Monitor fingerprint must have at least one identifying property (display name, vendor ID, model ID, or serial number)"
                )
            }

            // Validate resolution if provided
            if let width = fp.widthPixels, let height = fp.heightPixels {
                if width <= 0 || height <= 0 {
                    return ValidationError(
                        property: "workspace-to-monitor-force-assignment.\(workspace)",
                        message: "Invalid monitor resolution: \(width)x\(height)"
                    )
                }
            }

        case .pattern(let patternStr, _):
            // Pattern already compiled, just validate string is not empty
            if patternStr.isEmpty {
                return ValidationError(
                    property: "workspace-to-monitor-force-assignment.\(workspace)",
                    message: "Monitor pattern cannot be empty"
                )
            }

        case .sequenceNumber(let idx):
            if idx < 1 {
                return ValidationError(
                    property: "workspace-to-monitor-force-assignment.\(workspace)",
                    message: "Monitor sequence number must be positive (got \(idx))"
                )
            }

        case .main, .secondary:
            // These are always valid
            break
        }

        return nil
    }

    // MARK: - Performance Config Validation

    private func validatePerformanceConfig(_ perf: PerformanceConfig) -> [ValidationError] {
        var errors: [ValidationError] = []

        // Validate background layout threshold
        if perf.backgroundLayoutThreshold < 1 {
            errors.append(ValidationError(
                property: "performance.background-layout-threshold",
                message: "Background layout threshold must be at least 1 (got \(perf.backgroundLayoutThreshold))"
            ))
        }

        // Validate layout cache size
        if perf.layoutCacheSize < 0 {
            errors.append(ValidationError(
                property: "performance.layout-cache-size",
                message: "Layout cache size must be non-negative (got \(perf.layoutCacheSize))"
            ))
        }

        // Validate cache timeout
        if perf.layoutCacheTimeout < 0 {
            errors.append(ValidationError(
                property: "performance.layout-cache-timeout",
                message: "Layout cache timeout must be non-negative (got \(perf.layoutCacheTimeout))"
            ))
        }

        // Validate debouncing config
        let debounce = perf.debouncingConfig

        if debounce.baseDelay < 0 {
            errors.append(ValidationError(
                property: "performance.debouncing.base-delay",
                message: "Base delay must be non-negative (got \(debounce.baseDelay))"
            ))
        }

        if debounce.minimumDelay < 0 || debounce.minimumDelay > debounce.maximumDelay {
            errors.append(ValidationError(
                property: "performance.debouncing.minimum-delay",
                message: "Minimum delay must be between 0 and maximum delay (got \(debounce.minimumDelay), max: \(debounce.maximumDelay))"
            ))
        }

        if debounce.maximumDelay < debounce.minimumDelay {
            errors.append(ValidationError(
                property: "performance.debouncing.maximum-delay",
                message: "Maximum delay must be greater than minimum delay (got \(debounce.maximumDelay), min: \(debounce.minimumDelay))"
            ))
        }

        // Validate monitoring config
        let monitoring = perf.monitoringConfig

        if monitoring.metricsInterval < 0 {
            errors.append(ValidationError(
                property: "performance.monitoring.metrics-interval",
                message: "Metrics interval must be non-negative (got \(monitoring.metricsInterval))"
            ))
        }

        if monitoring.maxSamplesRetained < 0 {
            errors.append(ValidationError(
                property: "performance.monitoring.max-samples-retained",
                message: "Max samples retained must be non-negative (got \(monitoring.maxSamplesRetained))"
            ))
        }

        return errors
    }
}

// MARK: - Supporting Types

/// Represents a configuration validation error
struct ValidationError: Identifiable {
    let id = UUID()
    let property: String
    let message: String
    let severity: Severity

    init(property: String, message: String, severity: Severity = .error) {
        self.property = property
        self.message = message
        self.severity = severity
    }

    enum Severity {
        case error
        case warning

        var icon: String {
            switch self {
            case .error: return "❌"
            case .warning: return "⚠️"
            }
        }
    }

    var formattedMessage: String {
        "\(severity.icon) \(property): \(message)"
    }
}
