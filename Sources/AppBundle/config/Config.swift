import AppKit
import Common

/// Nearest ancestor of `start` that contains `.git`, or nil.
///
/// Bounded by the component count on purpose: `deleteLastPathComponent()` does not stop at "/", it
/// starts appending "..", so the plain `while !exists(.git)` loop this replaces spun forever at
/// 100% CPU -- no error, no output -- for any checkout without a `.git` ancestor (a source tarball,
/// or the sources copied elsewhere).
func gitRootAbove(_ start: URL) -> URL? {
    var url = start.standardizedFileURL
    for _ in 0 ..< url.pathComponents.count {
        url.deleteLastPathComponent()
        if FileManager.default.fileExists(atPath: url.appending(component: ".git").path) { return url }
    }
    return nil
}

/// Locates `docs/config-examples/default-config.toml` in a source checkout, for builds that are not
/// app bundles (debug binaries, unit tests).
///
/// **Must not trap.** It used to `die()` when no `.git` ancestor existed, on the reasoning that this
/// path is unreachable in a bundled build. But `defaultConfigUrl` reaches it via `??` whenever
/// `Bundle.main.url(forResource: "default-config")` returns nil — a missing or damaged resource in a
/// shipped `.app` — and `#filePath` is a *build-time* path, so no user's machine has a `.git` above
/// it. The result was that one missing bundle resource crashed the app at startup for every user,
/// with a message about a missing `.git` directory they never had.
///
/// A missing default config is recoverable and already handled: `defaultConfig` falls back to the
/// hardcoded `Config()` when this URL is unreadable. So return a URL that simply does not exist and
/// let that path do its job. (Same failure mode as Lander's top crasher — a trapping lookup where a
/// defaulted one was correct.)
func getDefaultConfigUrlFromProject(startingAt path: URL = URL(filePath: #filePath)) -> URL {
    guard let projectRoot = gitRootAbove(path) else {
        debugLog("No '.git' ancestor above \(path.path); falling back to hardcoded default config")
        return URL(filePath: "/nonexistent/aerospork-default-config-unavailable.toml")
    }
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
        let result = parseConfig(configString, isUserConfig: false)
        switch result {
            case .success(let config):
                return config
            case .failure(let errors):
                die("Can't parse default config: \(errors)")
        }
    } else {
        // Use hardcoded fallback config - all Config fields have sensible defaults
        // Users can override these by creating ~/.aerospork.toml or ~/.aerospork-debug.toml
        return Config()
    }
}()
/// Global, and `@MainActor` is what keeps that honest: every reader of `config` is already on the
/// main actor. There is no `Ctx`/dependency-injection type in this codebase to move it into, and
/// introducing one would mean threading a parameter through every command -- so this stays global
/// until something actually needs two configs alive at once (a config preview would).
@MainActor var config: Config = defaultConfig
@MainActor var configUrl: URL = defaultConfigUrl

/// Why the last read of the user's config failed, or nil. Retained deliberately: the startup error
/// dialog is modal-and-gone, and dismissing it left NOTHING on screen saying the config had not
/// loaded -- while the app quietly ran the bundled default keymap instead of the user's.
@MainActor var configLoadFailure: String? = nil

/// Non-fatal findings (deprecated keys) from the last successful load. Reported, never fatal.
@MainActor var configWarnings: [String] = []

/// The app is running the bundled default because the user's config would not parse.
///
/// Recovery is automatic and needs no separate signal: fixing the file makes `reloadConfig()`
/// succeed, which points `configUrl` back at the user's file and clears `configLoadFailure`.
@MainActor var isRunningFallbackDefaults: Bool { configUrl == defaultConfigUrl && configLoadFailure != nil }

struct Config: ConvenienceCopyable {
    var afterStartupCommand: [any Command] = []
    /// Sink for keys the generic table walker must not write: deprecated no-ops, and the v2 keys
    /// that are desugared by hand in `applyConfigV2`.
    var _deprecatedNoOp: Void = ()
    var enableNormalizationFlattenContainers: Bool = true
    var defaultRootContainerLayout: Layout = .tiles
    var defaultRootContainerOrientation: DefaultContainerOrientation = .auto
    var startAtLogin: Bool = false
    var automaticallyUnhideMacosHiddenApps: Bool = false
    var accordionPadding: Int = 30
    var enableNormalizationOppositeOrientationForNestedContainers: Bool = true
    /// Deprecated, but honoured -- `focus.swift` spawns it on every workspace change.
    var execOnWorkspaceChange: [String] = []
    var keyMapping = KeyMapping()
    var execConfig: ExecConfig = ExecConfig()

    var onFocusChanged: [any Command] = []
    var onFocusedWorkspaceChanged: [any Command] = []
    var onFocusedMonitorChanged: [any Command] = []

    var gaps: Gaps = .zero
    var workspaceToMonitorForceAssignment: [String: [MonitorDescription]] = [:]
    var modes: [String: Mode] = [:]
    var onWindowDetected: [WindowDetectedCallback] = []

    /// Names bound by keybindings, plus force-assigned ones. Only steers `getStubWorkspace` away from
    /// hijacking a name the user can reach -- these workspaces are NOT kept alive.
    var preservedWorkspaceNames: [String] = []
    /// Workspaces that always exist, empty or not: `workspaces`, `persistent-workspaces`, and every
    /// force-assigned name. See `Workspace.garbageCollectUnusedWorkspaces`.
    var persistentWorkspaces: Set<String> = []
    var autoMoveWorkspacesOnMonitorConnect: Bool = true

    /// Where the app is visible from. Defaults match what the bundle's `LSUIElement` used to hard
    /// code: menu bar yes, Dock no. See `AppVisibility` for why they cannot both be off.
    var showMenuBarIcon: Bool = true
    var showDockIcon: Bool = false
}

/// `CaseIterable` so `parseEnum` can list the accepted values in the error message.
enum DefaultContainerOrientation: String, CaseIterable {
    case horizontal, vertical, auto
}
