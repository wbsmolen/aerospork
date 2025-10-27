import AppKit
import Common
import HotKey

func getDefaultConfigUrlFromProject() -> URL {
    var url = URL(filePath: #filePath)
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    let projectRoot: URL = url
    return projectRoot.appending(component: "docs/config-examples/default-config.toml")
}

var defaultConfigUrl: URL {
    if isUnitTest {
        return getDefaultConfigUrlFromProject()
    } else {
        return Bundle.main.url(forResource: "default-config", withExtension: "toml")
            // Useful for debug builds that are not app bundles
            ?? getDefaultConfigUrlFromProject()
    }
}
@MainActor let defaultConfig: Config = {
    // Try to load default config from file, but use hardcoded defaults if not available
    if let configString = try? String(contentsOf: defaultConfigUrl) {
        let parsedConfig = parseConfig(configString, isUserConfig: false)
        if !parsedConfig.errors.isEmpty {
            die("Can't parse default config: \(parsedConfig.errors)")
        }
        return parsedConfig.config
    } else {
        // Use hardcoded fallback config - all Config fields have sensible defaults
        // Users can override these by creating ~/.aerospork.toml or ~/.aerospork-debug.toml
        return Config()
    }
}()
@MainActor var config: Config = defaultConfig // todo move to Ctx?
@MainActor var configUrl: URL = defaultConfigUrl

struct Config: ConvenienceCopyable {
    var afterLoginCommand: [any Command] = []
    var afterStartupCommand: [any Command] = []
    var _indentForNestedContainersWithTheSameOrientation: Void = ()
    var enableNormalizationFlattenContainers: Bool = true
    var _nonEmptyWorkspacesRootContainersLayoutOnStartup: Void = ()
    var defaultRootContainerLayout: Layout = .tiles
    var defaultRootContainerOrientation: DefaultContainerOrientation = .auto
    var startAtLogin: Bool = false
    var automaticallyUnhideMacosHiddenApps: Bool = false
    var accordionPadding: Int = 30
    var enableNormalizationOppositeOrientationForNestedContainers: Bool = true
    var execOnWorkspaceChange: [String] = [] // todo deprecate
    var keyMapping = KeyMapping()
    var execConfig: ExecConfig = ExecConfig()

    var onFocusChanged: [any Command] = []
    // var onFocusedWorkspaceChanged: [any Command] = []
    var onFocusedMonitorChanged: [any Command] = []

    var gaps: Gaps = .zero
    var workspaceToMonitorForceAssignment: [String: [MonitorDescription]] = [:]
    var modes: [String: Mode] = [:]
    var onWindowDetected: [WindowDetectedCallback] = []

    var preservedWorkspaceNames: [String] = []
    var performanceConfig: PerformanceConfig = PerformanceConfig()
    var autoMoveWorkspacesOnMonitorConnect: Bool = true

    var workspaceProfiles: [WorkspaceProfile] = [] // New
    var activeProfileName: String? = nil // New

    struct WorkspaceAssignment: Identifiable, Codable, Equatable {
        let id = UUID()
        var workspaceName: String
        var monitorDescription: String
        var monitorType: MonitorType
        var isForceAssignment: Bool = false

        enum MonitorType: Codable, Equatable {
            case name(String)
            case index(Int)
            case fingerprint(MonitorFingerprint)
        }

        struct MonitorFingerprint: Codable, Equatable {
            var vendorId: String?
            var modelId: String?
            var serialNumber: String?
            var displayName: String?
            var width: Int?
            var height: Int?
        }
    }

    struct WorkspaceProfile: Identifiable, Codable, Equatable {
        let id = UUID()
        var name: String
        var assignments: [WorkspaceAssignment]

        static func == (lhs: WorkspaceProfile, rhs: WorkspaceProfile) -> Bool {
            lhs.id == rhs.id
        }
    }
}

enum DefaultContainerOrientation: String {
    case horizontal, vertical, auto
}
