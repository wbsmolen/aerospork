import SwiftUI
import Common
import TOMLKit
import AppKit
import os.log

private let viewModelLogger = Logger(subsystem: "com.wbs.aerospork", category: "config-viewmodel")

@MainActor
class ConfigurationViewModel: ObservableObject {
    // Service layer
    private let configService: ConfigurationService = DefaultConfigurationService()

    // General settings
    @Published var startAtLogin: Bool = false
    @Published var automaticallyUnhideMacosHiddenApps: Bool = false
    @Published var defaultRootContainerLayout: String = "tiles"
    @Published var defaultRootContainerOrientation: String = "auto"
    @Published var accordionPadding: Int = 30
    @Published var enableNormalizationFlattenContainers: Bool = true
    @Published var enableNormalizationOppositeOrientation: Bool = true
    
    // Workspace assignments
    @Published var workspaceAssignments: [Config.WorkspaceAssignment] = []
    @Published var autoMoveWorkspacesOnMonitorConnect: Bool = true
    @Published var connectedMonitors: [MonitorInfo] = []
    @Published var allWorkspaces: [String] = []

    // Workspace profiles
    @Published var workspaceProfiles: [Config.WorkspaceProfile] = []
    @Published var activeProfileName: String? = nil

    // Gaps - split inner gaps into separate horizontal and vertical fields
    @Published var innerGapsHorizontal: Int = 5
    @Published var innerGapsVertical: Int = 5
    @Published var outerGapsTop: Int = 20
    @Published var outerGapsBottom: Int = 20
    @Published var outerGapsLeft: Int = 20
    @Published var outerGapsRight: Int = 20

    // Performance settings
    @Published var useBackgroundLayoutCalculation: Bool = true
    @Published var useLayoutMemoization: Bool = true
    @Published var useAdaptiveDebouncing: Bool = true
    @Published var backgroundLayoutThreshold: Int = 10
    @Published var layoutCacheSize: Int = 100
    @Published var layoutCacheTimeout: Double = 30.0
    @Published var debounceBaseDelay: Double = 50.0
    @Published var debounceMinDelay: Double = 10.0
    @Published var debounceMaxDelay: Double = 200.0
    @Published var debounceCpuLoadFactor: Double = 1.5
    @Published var debounceFrequencyFactor: Double = 1.2
    @Published var enablePerformanceMetrics: Bool = false
    @Published var enablePerformanceDebugLogging: Bool = false
    @Published var metricsInterval: Double = 60.0
    @Published var maxPerformanceSamples: Int = 1000

    // Key bindings (read-only display)
    @Published var keyBindings: [(mode: String, bindings: [(key: String, command: String)])] = []

    // Advanced settings (read-only display)
    @Published var preservedWorkspaceNames: [String] = []
    @Published var keyMappingPreset: String = "qwerty"
    @Published var afterLoginCommands: [String] = []
    @Published var afterStartupCommands: [String] = []
    @Published var onFocusChangedCommands: [String] = []
    @Published var onMonitorChangedCommands: [String] = []
    @Published var windowDetectionRules: [WindowDetectionRule] = []

    struct WindowDetectionRule: Identifiable {
        let id = UUID()
        var appId: String?
        var appNamePattern: String?
        var windowTitlePattern: String?
        var workspace: String?
        var duringStartup: Bool = false
        var checkFurtherRules: Bool = false
        var commands: [String] = []
    }

    // State management
    @Published var hasUnsavedChanges: Bool = false
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var isSaving: Bool = false
    
    private var originalTomlTable: TOMLTable?
    private var configFilePath: String?
    
    struct MonitorInfo: Identifiable {
        let id = UUID()
        let name: String
        let index: Int
        let fingerprint: MonitorFingerprint
        let isMain: Bool
        let width: Int
        let height: Int
        let positionX: CGFloat
        let positionY: CGFloat
        
        struct MonitorFingerprint: Equatable {
            let vendorId: String?
            let modelId: String?
            let serialNumber: String?
            let displayName: String
            let widthPixels: Int
            let heightPixels: Int
            
            var displayString: String {
                var parts: [String] = []
                if let vendorId = vendorId {
                    parts.append("vendor:\(vendorId)")
                }
                if let modelId = modelId {
                    parts.append("model:\(modelId)")
                }
                if let serial = serialNumber, !serial.isEmpty {
                    parts.append("serial:\(serial)")
                }
                parts.append("\(widthPixels)×\(heightPixels)")
                return parts.joined(separator: " ")
            }
        }
    }
    
    
    
    func loadConfiguration() async {
        isLoading = true
        errorMessage = nil

        do {
            // Get config file path
            let configFile = findCustomConfigUrl()

            if let configUrl = configFile.urlOrNil {
                // Config file exists - load from file
                configFilePath = configUrl.path
                let content = try String(contentsOfFile: configUrl.path)
                let tomlTable = try TOMLTable(string: content)
                originalTomlTable = tomlTable

                // Load settings from TOML
                loadSettingsFromToml(tomlTable)

                viewModelLogger.info("Configuration loaded from file: \(configUrl.path)")
            } else {
                // No config file exists - use hardcoded defaults
                // This matches the fallback behavior in Config.swift
                let fileName = isDebug ? ".aerospork-debug.toml" : ".aerospork.toml"
                let defaultPath = FileManager.default.homeDirectoryForCurrentUser
                    .appending(path: fileName).path
                configFilePath = defaultPath
                originalTomlTable = nil

                // Populate UI with hardcoded defaults from Config()
                let defaultConfig = Config()
                loadSettingsFromConfig(defaultConfig)

                viewModelLogger.info("No config file found. Using hardcoded defaults. Config will be created at: \(defaultPath)")
            }

            // Load current monitor information
            loadConnectedMonitors()

            hasUnsavedChanges = false
        } catch {
            errorMessage = "Failed to load configuration: \(error.localizedDescription)"
            viewModelLogger.error("Error loading configuration: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func loadSettingsFromToml(_ tomlTable: TOMLTable) {
        // Load general settings
        if let startAtLoginValue = tomlTable["start-at-login"]?.bool {
            startAtLogin = startAtLoginValue
        }
        if let autoUnhide = tomlTable["automatically-unhide-macos-hidden-apps"]?.bool {
            automaticallyUnhideMacosHiddenApps = autoUnhide
        }
        if let layout = tomlTable["default-root-container-layout"]?.string {
            defaultRootContainerLayout = layout
        }
        if let orientation = tomlTable["default-root-container-orientation"]?.string {
            defaultRootContainerOrientation = orientation
        }
        if let padding = tomlTable["accordion-padding"]?.int {
            accordionPadding = padding
        }
        if let flatten = tomlTable["enable-normalization-flatten-containers"]?.bool {
            enableNormalizationFlattenContainers = flatten
        }
        if let opposite = tomlTable["enable-normalization-opposite-orientation-for-nested-containers"]?.bool {
            enableNormalizationOppositeOrientation = opposite
        }
        if let autoMove = tomlTable["auto-move-workspaces-on-monitor-connect"]?.bool {
            autoMoveWorkspacesOnMonitorConnect = autoMove
        }

        // Load gaps - now loads horizontal and vertical separately
        if let gaps = tomlTable["gaps"]?.table {
            if let innerTable = gaps["inner"]?.table {
                innerGapsHorizontal = innerTable["horizontal"]?.int ?? 0
                innerGapsVertical = innerTable["vertical"]?.int ?? 0
            }
            if let outer = gaps["outer"]?.table {
                if let top = outer["top"]?.int { outerGapsTop = top }
                if let bottom = outer["bottom"]?.int { outerGapsBottom = bottom }
                if let left = outer["left"]?.int { outerGapsLeft = left }
                if let right = outer["right"]?.int { outerGapsRight = right }
            }
        }

        // Load performance settings from TOML
        if let performance = tomlTable["performance"]?.table {
            if let useBgLayout = performance["use-background-layout-calculation"]?.bool {
                useBackgroundLayoutCalculation = useBgLayout
            }
            if let useMemo = performance["use-layout-memoization"]?.bool {
                useLayoutMemoization = useMemo
            }
            if let useAdaptive = performance["use-adaptive-debouncing"]?.bool {
                useAdaptiveDebouncing = useAdaptive
            }
            if let threshold = performance["background-layout-threshold"]?.int {
                backgroundLayoutThreshold = threshold
            }
            if let cacheSize = performance["layout-cache-size"]?.int {
                layoutCacheSize = cacheSize
            }
            if let cacheTimeout = performance["layout-cache-timeout"]?.double {
                layoutCacheTimeout = cacheTimeout
            }

            // Debouncing config
            if let debouncing = performance["debouncing"]?.table {
                if let baseDelay = debouncing["base-delay"]?.double {
                    debounceBaseDelay = baseDelay
                }
                if let minDelay = debouncing["min-delay"]?.double {
                    debounceMinDelay = minDelay
                }
                if let maxDelay = debouncing["max-delay"]?.double {
                    debounceMaxDelay = maxDelay
                }
                if let cpuFactor = debouncing["cpu-load-factor"]?.double {
                    debounceCpuLoadFactor = cpuFactor
                }
                if let freqFactor = debouncing["frequency-factor"]?.double {
                    debounceFrequencyFactor = freqFactor
                }
            }

            // Monitoring config
            if let monitoring = performance["monitoring"]?.table {
                if let enableMetrics = monitoring["enable-metrics"]?.bool {
                    enablePerformanceMetrics = enableMetrics
                }
                if let enableDebug = monitoring["enable-debug-logging"]?.bool {
                    enablePerformanceDebugLogging = enableDebug
                }
                if let interval = monitoring["metrics-interval"]?.double {
                    metricsInterval = interval
                }
                if let maxSamples = monitoring["max-samples-retained"]?.int {
                    maxPerformanceSamples = maxSamples
                }
            }
        }

        // Load workspace assignments directly from TOML
        workspaceAssignments = []
        viewModelLogger.info("Loading workspace assignments from TOML")

        if let wsAssignments = tomlTable["workspace-to-monitor-force-assignment"]?.table {
            viewModelLogger.info("Found workspace-to-monitor-force-assignment with \(wsAssignments.count) entries")
            for (workspace, value) in wsAssignments {
                viewModelLogger.debug("Processing workspace '\(workspace)' with value type: \(String(describing: type(of: value)))")

                // Parse the monitor assignment
                if let stringValue = value.string {
                    // Simple string like "main" or "secondary"
                    let assignment = Config.WorkspaceAssignment(
                        workspaceName: workspace,
                        monitorDescription: stringValue,
                        monitorType: .name(stringValue),
                        isForceAssignment: true
                    )
                    workspaceAssignments.append(assignment)
                    viewModelLogger.debug("Added assignment for workspace \(workspace) to monitor \(stringValue)")
                } else if let tableValue = value.table, let fingerprintTable = tableValue["fingerprint"]?.table {
                    // Fingerprint format
                    let displayName = fingerprintTable["display_name"]?.string ?? "Unknown"
                    let width = fingerprintTable["width"]?.int
                    let height = fingerprintTable["height"]?.int

                    let fingerprint = Config.WorkspaceAssignment.MonitorFingerprint(
                        vendorId: fingerprintTable["vendor_id"]?.string,
                        modelId: fingerprintTable["model_id"]?.string,
                        serialNumber: fingerprintTable["serial_number"]?.string,
                        displayName: displayName,
                        width: width,
                        height: height
                    )

                    let assignment = Config.WorkspaceAssignment(
                        workspaceName: workspace,
                        monitorDescription: displayName,
                        monitorType: .fingerprint(fingerprint),
                        isForceAssignment: true
                    )
                    workspaceAssignments.append(assignment)
                    viewModelLogger.debug("Added fingerprint assignment for workspace \(workspace) to monitor \(displayName)")
                } else if let intValue = value.int {
                    // Sequence number
                    let assignment = Config.WorkspaceAssignment(
                        workspaceName: workspace,
                        monitorDescription: "Monitor \(intValue)",
                        monitorType: .index(intValue),
                        isForceAssignment: true
                    )
                    workspaceAssignments.append(assignment)
                    viewModelLogger.debug("Added assignment for workspace \(workspace) to monitor index \(intValue)")
                }
            }
        } else {
            viewModelLogger.debug("No workspace-to-monitor-force-assignment found in TOML")
        }

        // Sort assignments by workspace name for consistent display
        workspaceAssignments.sort { $0.workspaceName < $1.workspaceName }
        viewModelLogger.info("Loaded \(self.workspaceAssignments.count) total workspace assignments")

        // Load workspace profiles
        workspaceProfiles = []
        if let profilesArray = tomlTable["workspace-profile"]?.array {
            viewModelLogger.info("Found \(profilesArray.count) workspace profiles in TOML")
            for profileItem in profilesArray {
                if let profileTable = profileItem.table,
                   let name = profileTable["name"]?.string {

                    var assignments: [Config.WorkspaceAssignment] = []

                    // Parse assignments for this profile
                    if let assignmentsTable = profileTable["assignments"]?.table {
                        for (workspace, value) in assignmentsTable {
                            if let stringValue = value.string {
                                let assignment = Config.WorkspaceAssignment(
                                    workspaceName: workspace,
                                    monitorDescription: stringValue,
                                    monitorType: .name(stringValue),
                                    isForceAssignment: true
                                )
                                assignments.append(assignment)
                            } else if let tableValue = value.table, let fingerprintTable = tableValue["fingerprint"]?.table {
                                let displayName = fingerprintTable["display_name"]?.string ?? "Unknown"
                                let fingerprint = Config.WorkspaceAssignment.MonitorFingerprint(
                                    vendorId: fingerprintTable["vendor_id"]?.string,
                                    modelId: fingerprintTable["model_id"]?.string,
                                    serialNumber: fingerprintTable["serial_number"]?.string,
                                    displayName: displayName,
                                    width: fingerprintTable["width"]?.int,
                                    height: fingerprintTable["height"]?.int
                                )
                                let assignment = Config.WorkspaceAssignment(
                                    workspaceName: workspace,
                                    monitorDescription: displayName,
                                    monitorType: .fingerprint(fingerprint),
                                    isForceAssignment: true
                                )
                                assignments.append(assignment)
                            } else if let intValue = value.int {
                                let assignment = Config.WorkspaceAssignment(
                                    workspaceName: workspace,
                                    monitorDescription: "Monitor \(intValue)",
                                    monitorType: .index(intValue),
                                    isForceAssignment: true
                                )
                                assignments.append(assignment)
                            }
                        }
                    }

                    let profile = Config.WorkspaceProfile(name: name, assignments: assignments)
                    workspaceProfiles.append(profile)
                    viewModelLogger.debug("Loaded profile '\(name)' with \(assignments.count) assignments")
                }
            }
        }

        // Load active profile name
        if let activeProfile = tomlTable["active-profile"]?.string {
            activeProfileName = activeProfile
            viewModelLogger.info("Active profile: \(activeProfile)")
        } else {
            activeProfileName = nil
        }

        // Load key bindings for display
        loadKeyBindings(from: tomlTable)

        // Load advanced settings
        loadAdvancedSettings(from: tomlTable)

        // Extract all workspace names from keybindings and assignments
        extractAllWorkspaces(from: tomlTable)
    }

    private func loadSettingsFromConfig(_ config: Config) {
        // Load general settings from Config struct defaults
        startAtLogin = config.startAtLogin
        automaticallyUnhideMacosHiddenApps = config.automaticallyUnhideMacosHiddenApps
        defaultRootContainerLayout = String(describing: config.defaultRootContainerLayout)
        defaultRootContainerOrientation = String(describing: config.defaultRootContainerOrientation)
        accordionPadding = config.accordionPadding
        enableNormalizationFlattenContainers = config.enableNormalizationFlattenContainers
        enableNormalizationOppositeOrientation = config.enableNormalizationOppositeOrientationForNestedContainers
        autoMoveWorkspacesOnMonitorConnect = config.autoMoveWorkspacesOnMonitorConnect

        // Load gaps - extract constant values from DynamicConfigValue, separate H/V
        innerGapsHorizontal = extractConstantValue(config.gaps.inner.horizontal)
        innerGapsVertical = extractConstantValue(config.gaps.inner.vertical)
        outerGapsTop = extractConstantValue(config.gaps.outer.top)
        outerGapsBottom = extractConstantValue(config.gaps.outer.bottom)
        outerGapsLeft = extractConstantValue(config.gaps.outer.left)
        outerGapsRight = extractConstantValue(config.gaps.outer.right)

        // Load performance settings
        useBackgroundLayoutCalculation = config.performanceConfig.useBackgroundLayoutCalculation
        useLayoutMemoization = config.performanceConfig.useLayoutMemoization
        useAdaptiveDebouncing = config.performanceConfig.useAdaptiveDebouncing
        backgroundLayoutThreshold = config.performanceConfig.backgroundLayoutThreshold
        layoutCacheSize = config.performanceConfig.layoutCacheSize
        layoutCacheTimeout = config.performanceConfig.layoutCacheTimeout
        debounceBaseDelay = config.performanceConfig.debouncingConfig.baseDelay
        debounceMinDelay = config.performanceConfig.debouncingConfig.minimumDelay
        debounceMaxDelay = config.performanceConfig.debouncingConfig.maximumDelay
        debounceCpuLoadFactor = config.performanceConfig.debouncingConfig.cpuLoadFactor
        debounceFrequencyFactor = config.performanceConfig.debouncingConfig.frequencyFactor
        enablePerformanceMetrics = config.performanceConfig.monitoringConfig.enableMetrics
        enablePerformanceDebugLogging = config.performanceConfig.monitoringConfig.enableDebugLogging
        metricsInterval = config.performanceConfig.monitoringConfig.metricsInterval
        maxPerformanceSamples = config.performanceConfig.monitoringConfig.maxSamplesRetained

        // Convert workspace assignments
        workspaceAssignments = config.workspaceToMonitorForceAssignment.flatMap { (workspace, monitors) in
            monitors.map { monitor in
                Config.WorkspaceAssignment(
                    workspaceName: workspace,
                    monitorDescription: descriptionString(for: monitor),
                    monitorType: convertMonitorDescription(monitor),
                    isForceAssignment: true
                )
            }
        }.sorted { $0.workspaceName < $1.workspaceName }

        // Load workspace profiles
        workspaceProfiles = config.workspaceProfiles
        activeProfileName = config.activeProfileName

        // Load advanced settings from config
        preservedWorkspaceNames = config.preservedWorkspaceNames
        keyMappingPreset = "qwerty" // Default preset (actual preset is read from TOML)
        // Commands will be empty for default config
        afterLoginCommands = []
        afterStartupCommands = []
        onFocusChangedCommands = []
        onMonitorChangedCommands = []
        windowDetectionRules = []

        // No key bindings in default config
        keyBindings = []
        allWorkspaces = []

        viewModelLogger.info("Loaded settings from hardcoded Config() defaults")
    }

    private func extractConstantValue(_ dynamicValue: DynamicConfigValue<Int>) -> Int {
        switch dynamicValue {
        case .constant(let value):
            return value
        case .perMonitor(_, let defaultValue):
            return defaultValue
        }
    }

    // MARK: - Validation Methods

    /// Validate gaps configuration
    func validateGaps() -> [String] {
        var errors: [String] = []

        // Inner gaps validation (0-500 pixels is reasonable)
        if innerGapsHorizontal < 0 {
            errors.append("Inner horizontal gap cannot be negative")
        } else if innerGapsHorizontal > 500 {
            errors.append("Inner horizontal gap is unusually large (>500px). Consider reducing.")
        }

        if innerGapsVertical < 0 {
            errors.append("Inner vertical gap cannot be negative")
        } else if innerGapsVertical > 500 {
            errors.append("Inner vertical gap is unusually large (>500px). Consider reducing.")
        }

        // Outer gaps validation
        if outerGapsTop < 0 {
            errors.append("Outer top gap cannot be negative")
        } else if outerGapsTop > 500 {
            errors.append("Outer top gap is unusually large (>500px). Consider reducing.")
        }

        if outerGapsBottom < 0 {
            errors.append("Outer bottom gap cannot be negative")
        } else if outerGapsBottom > 500 {
            errors.append("Outer bottom gap is unusually large (>500px). Consider reducing.")
        }

        if outerGapsLeft < 0 {
            errors.append("Outer left gap cannot be negative")
        } else if outerGapsLeft > 500 {
            errors.append("Outer left gap is unusually large (>500px). Consider reducing.")
        }

        if outerGapsRight < 0 {
            errors.append("Outer right gap cannot be negative")
        } else if outerGapsRight > 500 {
            errors.append("Outer right gap is unusually large (>500px). Consider reducing.")
        }

        return errors
    }

    /// Validate general settings
    func validateGeneral() -> [String] {
        var errors: [String] = []

        // Accordion padding validation (0-1000 pixels)
        if accordionPadding < 0 {
            errors.append("Accordion padding cannot be negative")
        } else if accordionPadding > 1000 {
            errors.append("Accordion padding is unusually large (>1000px). Consider reducing.")
        }

        // Layout validation
        let validLayouts = ["tiles", "accordion"]
        if !validLayouts.contains(defaultRootContainerLayout) {
            errors.append("Invalid layout '\(defaultRootContainerLayout)'. Must be 'tiles' or 'accordion'.")
        }

        // Orientation validation
        let validOrientations = ["auto", "horizontal", "vertical"]
        if !validOrientations.contains(defaultRootContainerOrientation) {
            errors.append("Invalid orientation '\(defaultRootContainerOrientation)'. Must be 'auto', 'horizontal', or 'vertical'.")
        }

        return errors
    }

    /// Validate all settings
    func validateAll() -> [String] {
        var allErrors: [String] = []
        allErrors.append(contentsOf: validateGaps())
        allErrors.append(contentsOf: validateGeneral())
        return allErrors
    }

    // MARK: - Performance Preset Methods

    /// Apply a performance preset
    func applyPerformancePreset(_ preset: PerformanceConfig) {
        useBackgroundLayoutCalculation = preset.useBackgroundLayoutCalculation
        useLayoutMemoization = preset.useLayoutMemoization
        useAdaptiveDebouncing = preset.useAdaptiveDebouncing
        backgroundLayoutThreshold = preset.backgroundLayoutThreshold
        layoutCacheSize = preset.layoutCacheSize
        layoutCacheTimeout = preset.layoutCacheTimeout
        debounceBaseDelay = preset.debouncingConfig.baseDelay
        debounceMinDelay = preset.debouncingConfig.minimumDelay
        debounceMaxDelay = preset.debouncingConfig.maximumDelay
        debounceCpuLoadFactor = preset.debouncingConfig.cpuLoadFactor
        debounceFrequencyFactor = preset.debouncingConfig.frequencyFactor
        enablePerformanceMetrics = preset.monitoringConfig.enableMetrics
        enablePerformanceDebugLogging = preset.monitoringConfig.enableDebugLogging
        metricsInterval = preset.monitoringConfig.metricsInterval
        maxPerformanceSamples = preset.monitoringConfig.maxSamplesRetained
        markAsModified()
    }



    private func loadKeyBindings(from toml: TOMLTable) {
        keyBindings = []
        
        if let modes = toml["mode"]?.table {
            for (modeName, modeTable) in modes {
                if let bindings = modeTable.table?["binding"]?.table {
                    var modeBindings: [(key: String, command: String)] = []
                    for (key, command) in bindings {
                        if let cmdString = command.string {
                            modeBindings.append((key: key, command: cmdString))
                        } else if let cmdArray = command.array {
                            let cmdString = cmdArray.compactMap { $0.string }.joined(separator: " ")
                            modeBindings.append((key: key, command: cmdString))
                        }
                    }
                    keyBindings.append((mode: modeName, bindings: modeBindings))
                }
            }
        }
    }

    private func loadAdvancedSettings(from toml: TOMLTable) {
        // Load preserved workspaces
        if let preserved = toml["preserve-workspace-name"]?.array {
            preservedWorkspaceNames = preserved.compactMap { $0.string }
        } else {
            preservedWorkspaceNames = []
        }

        // Load key mapping preset
        if let keyMappingTable = toml["key-mapping"]?.table,
           let preset = keyMappingTable["preset"]?.string {
            keyMappingPreset = preset
        } else {
            keyMappingPreset = "qwerty"
        }

        // Load after-login-command
        if let afterLogin = toml["after-login-command"]?.array {
            afterLoginCommands = afterLogin.compactMap { item in
                if let str = item.string {
                    return str
                } else if let arr = item.array {
                    return arr.compactMap { $0.string }.joined(separator: " ")
                }
                return nil
            }
        } else {
            afterLoginCommands = []
        }

        // Load after-startup-command
        if let afterStartup = toml["after-startup-command"]?.array {
            afterStartupCommands = afterStartup.compactMap { item in
                if let str = item.string {
                    return str
                } else if let arr = item.array {
                    return arr.compactMap { $0.string }.joined(separator: " ")
                }
                return nil
            }
        } else {
            afterStartupCommands = []
        }

        // Load on-focus-changed
        if let onFocus = toml["on-focus-changed"]?.array {
            onFocusChangedCommands = onFocus.compactMap { item in
                if let str = item.string {
                    return str
                } else if let arr = item.array {
                    return arr.compactMap { $0.string }.joined(separator: " ")
                }
                return nil
            }
        } else {
            onFocusChangedCommands = []
        }

        // Load on-focused-monitor-changed
        if let onMonitor = toml["on-focused-monitor-changed"]?.array {
            onMonitorChangedCommands = onMonitor.compactMap { item in
                if let str = item.string {
                    return str
                } else if let arr = item.array {
                    return arr.compactMap { $0.string }.joined(separator: " ")
                }
                return nil
            }
        } else {
            onMonitorChangedCommands = []
        }

        // Load window detection rules
        windowDetectionRules = []
        if let rulesArray = toml["on-window-detected"]?.array {
            for ruleItem in rulesArray {
                if let ruleTable = ruleItem.table {
                    var rule = WindowDetectionRule()

                    // Parse matchers
                    if let appId = ruleTable["app-id"]?.string {
                        rule.appId = appId
                    }
                    if let appName = ruleTable["app-name-regex-substring"]?.string {
                        rule.appNamePattern = appName
                    }
                    if let windowTitle = ruleTable["window-title-regex-substring"]?.string {
                        rule.windowTitlePattern = windowTitle
                    }
                    if let workspace = ruleTable["workspace"]?.string {
                        rule.workspace = workspace
                    }
                    if let duringStartup = ruleTable["during-aerospace-startup"]?.bool {
                        rule.duringStartup = duringStartup
                    }

                    // Parse check-further-callbacks
                    if let checkFurther = ruleTable["check-further-callbacks"]?.bool {
                        rule.checkFurtherRules = checkFurther
                    }

                    // Parse run commands
                    if let runCommands = ruleTable["run"]?.array {
                        rule.commands = runCommands.compactMap { item in
                            if let str = item.string {
                                return str
                            } else if let arr = item.array {
                                return arr.compactMap { $0.string }.joined(separator: " ")
                            }
                            return nil
                        }
                    }

                    windowDetectionRules.append(rule)
                }
            }
        }
    }

    private func extractAllWorkspaces(from toml: TOMLTable) {
        var workspaceSet = Set<String>()
        
        // Add workspaces from assignments
        for assignment in workspaceAssignments {
            workspaceSet.insert(assignment.workspaceName)
        }
        
        // Extract workspaces from keybindings
        if let modes = toml["mode"]?.table {
            for (_, modeTable) in modes {
                if let bindings = modeTable.table?["binding"]?.table {
                    for (_, command) in bindings {
                        let cmdString: String
                        if let str = command.string {
                            cmdString = str
                        } else if let cmdArray = command.array {
                            cmdString = cmdArray.compactMap { $0.string }.joined(separator: " ")
                        } else {
                            continue
                        }
                        
                        // Look for workspace commands
                        let components = cmdString.split(separator: " ").map { String($0) }
                        if components.count >= 2 {
                            if components[0] == "workspace" || 
                               components[0] == "move-node-to-workspace" ||
                               components[0] == "move-workspace-to-monitor" {
                                let workspace = components[1]
                                // Validate workspace name
                                if case .success = WorkspaceName.parse(workspace) {
                                    workspaceSet.insert(workspace)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        allWorkspaces = Array(workspaceSet).sorted()
    }
    
    func saveConfiguration() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        errorMessage = nil

        do {
            // Build configuration data from current state
            let configData = buildConfigurationData()

            // Validate before saving
            let validationErrors = configService.validate(configData)
            let criticalErrors = validationErrors.filter { $0.severity == .error }

            if !criticalErrors.isEmpty {
                errorMessage = criticalErrors.map(\.formattedMessage).joined(separator: "\n")
                return
            }

            // Show warnings but allow save
            let warnings = validationErrors.filter { $0.severity == .warning }
            if !warnings.isEmpty {
                viewModelLogger.warning("Configuration has warnings: \(warnings.map(\.message).joined(separator: "; "))")
            }

            // Save using service (this preserves keybindings and comments)
            try await configService.saveConfiguration(configData)

            hasUnsavedChanges = false
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
        }
    }

    /// Build ConfigurationData from current ViewModel state
    private func buildConfigurationData() -> ConfigurationData {
        let general = GeneralSettings(
            startAtLogin: startAtLogin,
            automaticallyUnhideMacosHiddenApps: automaticallyUnhideMacosHiddenApps,
            defaultRootContainerLayout: defaultRootContainerLayout,
            defaultRootContainerOrientation: defaultRootContainerOrientation,
            accordionPadding: accordionPadding,
            enableNormalizationFlattenContainers: enableNormalizationFlattenContainers,
            enableNormalizationOppositeOrientation: enableNormalizationOppositeOrientation,
            autoMoveWorkspacesOnMonitorConnect: autoMoveWorkspacesOnMonitorConnect
        )

        let gaps = GapsSettings(
            innerHorizontal: innerGapsHorizontal,
            innerVertical: innerGapsVertical,
            outerTop: outerGapsTop,
            outerBottom: outerGapsBottom,
            outerLeft: outerGapsLeft,
            outerRight: outerGapsRight
        )

        // Convert workspace assignments to DTO format
        let assignments = workspaceAssignments.filter { $0.isForceAssignment }.map { assignment in
            convertToWorkspaceAssignmentData(assignment)
        }

        // Get original content from file (needed for preservation)
        let originalContent: String
        if let path = configFilePath {
            originalContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        } else {
            originalContent = ""
        }

        return ConfigurationData(
            general: general,
            gaps: gaps,
            workspaceAssignments: assignments,
            workspaceProfiles: workspaceProfiles,
            activeProfileName: activeProfileName,
            originalContent: originalContent
        )
    }

    /// Convert Config.WorkspaceAssignment to WorkspaceAssignmentData
    private func convertToWorkspaceAssignmentData(_ assignment: Config.WorkspaceAssignment) -> WorkspaceAssignmentData {
        let monitorType: WorkspaceAssignmentData.MonitorTypeData

        switch assignment.monitorType {
        case .name(let name):
            monitorType = .name(name)
        case .index(let idx):
            monitorType = .index(idx)
        case .fingerprint(let fp):
            let fingerprintData = MonitorFingerprintData(
                displayName: fp.displayName,
                vendorId: fp.vendorId.flatMap { hexString in
                    let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
                    return UInt32(cleanHex, radix: 16)
                },
                modelId: fp.modelId.flatMap { hexString in
                    let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
                    return UInt32(cleanHex, radix: 16)
                },
                serialNumber: fp.serialNumber,
                width: fp.width,
                height: fp.height
            )
            monitorType = .fingerprint(fingerprintData)
        }

        return WorkspaceAssignmentData(
            workspaceName: assignment.workspaceName,
            monitorDescription: assignment.monitorDescription,
            monitorType: monitorType,
            isForceAssignment: assignment.isForceAssignment
        )
    }
    
    func revertChanges() {
        Task {
            await loadConfiguration()
        }
    }
    
    func markAsModified() {
        hasUnsavedChanges = true
    }
    
    // Helper functions for converting MonitorDescription to assignment format
    private func descriptionString(for desc: MonitorDescription) -> String {
        switch desc {
        case .main:
            return "main"
        case .secondary:
            return "secondary"
        case .sequenceNumber(let num):
            return "Monitor \(num)"
        case .pattern(let name, _):
            return name
        case .fingerprint(let data):
            return data.displayNamePattern ?? "Fingerprint"
        }
    }
    
    private func convertMonitorDescription(_ desc: MonitorDescription) -> Config.WorkspaceAssignment.MonitorType {
        switch desc {
        case .main:
            return .name("main")
        case .secondary:
            return .name("secondary")
        case .sequenceNumber(let num):
            return .index(num)
        case .pattern(let name, _):
            return .name(name)
        case .fingerprint(let data):
            return .fingerprint(Config.WorkspaceAssignment.MonitorFingerprint(
                vendorId: data.vendorID.map { String(format: "0x%04X", $0) },
                modelId: data.modelID.map { String(format: "0x%04X", $0) },
                serialNumber: data.serialNumber,
                displayName: data.displayNamePattern,
                width: data.widthPixels,
                height: data.heightPixels
            ))
        }
    }
    
    // Helper function to match monitor fingerprints comprehensively
    func matchesFingerprint(_ monitor: MonitorInfo, _ fingerprint: Config.WorkspaceAssignment.MonitorFingerprint) -> Bool {
        // Check display name match (highest priority)
        if let fpDisplayName = fingerprint.displayName {
            let monDisplayName = monitor.fingerprint.displayName
            if fpDisplayName.localizedCaseInsensitiveCompare(monDisplayName) != .orderedSame {
                return false
            }
        }
        
        // Check resolution match
        if let fpWidth = fingerprint.width, let fpHeight = fingerprint.height {
            if fpWidth != monitor.fingerprint.widthPixels || fpHeight != monitor.fingerprint.heightPixels {
                return false
            }
        }
        
        // Check vendor/model if available
        if let fpVendorId = fingerprint.vendorId, !fpVendorId.isEmpty,
           let monVendorId = monitor.fingerprint.vendorId {
            if fpVendorId != monVendorId {
                return false
            }
        }
        
        if let fpModelId = fingerprint.modelId, !fpModelId.isEmpty,
           let monModelId = monitor.fingerprint.modelId {
            if fpModelId != monModelId {
                return false
            }
        }
        
        // If we have a display name match, that's sufficient
        if fingerprint.displayName != nil {
            return true
        }
        
        // Otherwise require at least one matching field
        return (fingerprint.vendorId != nil && fingerprint.vendorId == monitor.fingerprint.vendorId) ||
               (fingerprint.modelId != nil && fingerprint.modelId == monitor.fingerprint.modelId) ||
               (fingerprint.width != nil && fingerprint.width == monitor.fingerprint.widthPixels &&
                fingerprint.height != nil && fingerprint.height == monitor.fingerprint.heightPixels)
    }
    
    func addWorkspaceAssignment() {
        let newAssignment = Config.WorkspaceAssignment(
            workspaceName: findNextAvailableWorkspaceName(),
            monitorDescription: "main",
            monitorType: .name("main"),
            isForceAssignment: true
        )
        viewModelLogger.info("Adding new workspace assignment: \(newAssignment.workspaceName)")
        workspaceAssignments.append(newAssignment)
        objectWillChange.send()
        markAsModified()
    }
    
    func removeWorkspaceAssignment(at index: Int) {
        guard index < workspaceAssignments.count else { return }
        let removed = workspaceAssignments[index]
        viewModelLogger.info("Removing workspace assignment: \(removed.workspaceName)")
        workspaceAssignments.remove(at: index)
        objectWillChange.send()
        markAsModified()
    }
    
    private func findNextAvailableWorkspaceName() -> String {
        let existingNames = Set(workspaceAssignments.map { $0.workspaceName })
            .union(allWorkspaces)
        var counter = 1
        while existingNames.contains(String(counter)) {
            counter += 1
        }
        return String(counter)
    }
    
    func loadConnectedMonitors() {
        connectedMonitors = sortedMonitors.enumerated().compactMap { (index, monitor) in
            if let lazyMonitor = monitor as? LazyMonitor,
               let fp = lazyMonitor.fingerprint {
                return MonitorInfo(
                    name: monitor.name,
                    index: index + 1,
                    fingerprint: MonitorInfo.MonitorFingerprint(
                        vendorId: fp.vendorID.map { String(format: "0x%04X", $0) },
                        modelId: fp.modelID.map { String(format: "0x%04X", $0) },
                        serialNumber: fp.serialNumber,
                        displayName: fp.displayName ?? monitor.name,
                        widthPixels: fp.widthPixels ?? Int(monitor.width),
                        heightPixels: fp.heightPixels ?? Int(monitor.height)
                    ),
                    isMain: monitor.rect.minX == 0 && monitor.rect.minY == 0,
                    width: Int(monitor.width),
                    height: Int(monitor.height),
                    positionX: monitor.rect.minX,
                    positionY: monitor.rect.minY
                )
            }
            return nil
        }
    }
    
    func addWorkspaceAssignment(forMonitor monitor: MonitorInfo? = nil, isForce: Bool = true) {
        var newAssignment = Config.WorkspaceAssignment(
            workspaceName: findNextAvailableWorkspaceName(),
            monitorDescription: monitor?.name ?? "main",
            monitorType: .name(monitor?.name ?? "main"),
            isForceAssignment: isForce
        )
        
        if let monitor = monitor {
            // Create fingerprint from the selected monitor
            newAssignment.monitorType = .fingerprint(Config.WorkspaceAssignment.MonitorFingerprint(
                vendorId: monitor.fingerprint.vendorId,
                modelId: monitor.fingerprint.modelId,
                serialNumber: monitor.fingerprint.serialNumber,
                displayName: monitor.fingerprint.displayName,
                width: monitor.fingerprint.widthPixels,
                height: monitor.fingerprint.heightPixels
            ))
            newAssignment.monitorDescription = monitor.name
        }
        
        workspaceAssignments.append(newAssignment)
        markAsModified()
    }
    
    // Workspace management methods
    func addWorkspace(_ workspace: String) {
        if !allWorkspaces.contains(workspace) {
            allWorkspaces.append(workspace)
            allWorkspaces.sort()
            markAsModified()
        }
    }
    
    func removeWorkspace(_ workspace: String) {
        allWorkspaces.removeAll { $0 == workspace }
        workspaceAssignments.removeAll { $0.workspaceName == workspace }
        markAsModified()
    }
    
    func updateWorkspaceAssignment(workspace: String, assignment: Config.WorkspaceAssignment?) {
        viewModelLogger.info("Updating workspace assignment for: \(workspace)")
        // Remove existing assignment for this workspace
        workspaceAssignments.removeAll { $0.workspaceName == workspace }

        // Add new assignment if provided
        if let assignment = assignment {
            workspaceAssignments.append(assignment)
            viewModelLogger.debug("New assignment: \(assignment.monitorDescription)")
        }
        
        objectWillChange.send()
        markAsModified()
    }
    
    
    enum ConfigError: LocalizedError {
        case noConfigFile
        
        var errorDescription: String? {
            switch self {
            case .noConfigFile:
                return "No configuration file path available"
            }
        }
    }
    
    private func convertAssignmentToMonitorDescription(_ assignment: Config.WorkspaceAssignment) -> MonitorDescription {
        switch assignment.monitorType {
        case .name(let name):
            if name == "main" {
                return .main
            } else if name == "secondary" {
                return .secondary
            } else {
                // Try to create regex pattern; fallback to literal match if invalid
                guard let regex = try? SendableRegex(name) else {
                    // Use a safe regex that matches the exact string
                    let escapedName = NSRegularExpression.escapedPattern(for: name)
                    return .pattern(name, try! SendableRegex(escapedName))
                }
                return .pattern(name, regex)
            }
        case .index(let index):
            return .sequenceNumber(index)
        case .fingerprint(let fp):
            let data = MonitorFingerprintPatternData(
                vendorID: fp.vendorId.flatMap { hexString in
                    let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
                    return UInt32(cleanHex, radix: 16)
                },
                modelID: fp.modelId.flatMap { hexString in
                    let cleanHex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
                    return UInt32(cleanHex, radix: 16)
                },
                serialNumber: fp.serialNumber,
                displayNamePattern: fp.displayName,
                widthPixels: fp.width,
                heightPixels: fp.height
            )
            return .fingerprint(data)
        }
    }
    
}


extension String {
    func matches(regex: String) -> Bool {
        return self.range(of: regex, options: .regularExpression) != nil
    }
}