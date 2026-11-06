import AppKit
import Common

public class TrayMenuModel: ObservableObject {
    @MainActor public static let shared = TrayMenuModel()

    private init() {}

    @Published var trayText: String = ""
    @Published var trayItems: [TrayItem] = []
    /// Is "layouting" enabled
    @Published var isEnabled: Bool = true
    @Published var workspaces: [WorkspaceViewModel] = []
    /// Drives `MenuBarExtra(isInserted:)`. Defaults to the same value `AppVisibility` derives from a
    /// default `Config`, so the very first `syncAppVisibility()` publishes nothing.
    @Published var showsMenuBarIcon: Bool = true
}

/// Which of the two ways into the GUI are on screen.
///
/// **The considered decision: the combination "no menu bar icon AND no Dock icon" is refused.**
///
/// A window manager has no windows of its own, so those two icons are the only self-service routes
/// to Settings. Turning both off in the TOML would leave the GUI reachable *only* by hand-editing
/// the very file the GUI exists to edit, or by knowing that `aerospork open-settings` exists — a
/// setting that can permanently hide the thing that undoes it is a trap, not a preference.
///
/// Of the two ways to refuse it, this one honours the request that was actually made: whoever asked
/// for a clean menu bar gets a clean menu bar, and pays for it with a Dock icon. Forcing the *menu
/// bar* icon back instead would silently ignore the only toggle they touched. The GUI says so next
/// to the toggle, and `aerospork open-settings` is documented there as the escape hatch either way.
///
/// A pure value rather than a branch inside the sync function, because "what the two config keys
/// mean together" is the part worth pinning with a test.
struct AppVisibility: Equatable {
    let showsMenuBarIcon: Bool
    let showsDockIcon: Bool
    /// True only when the Dock icon is on screen *because* the rule above put it there — not when
    /// the user asked for a Dock-only setup, which is a perfectly ordinary thing to want.
    let dockIconIsForced: Bool

    init(showMenuBarIcon: Bool, showDockIcon: Bool) {
        showsMenuBarIcon = showMenuBarIcon
        showsDockIcon = showDockIcon || !showMenuBarIcon
        dockIconIsForced = !showDockIcon && !showMenuBarIcon
    }
}

/// Push `show-menu-bar-icon` / `show-dock-icon` at AppKit and at the menu bar scene.
///
/// Called from `updateTrayText()` (so every refresh — which covers `reload-config`, hot-reload and
/// startup) and from the settings window's own save, which reloads the config without running a
/// refresh session. Both are guarded assignments, so the steady state costs one comparison. The policy
/// is compared with what was last applied, not read back: `NSApp.activationPolicy()` is a LaunchServices
/// round trip, and nothing else changes it.
///
/// TRADEOFF: `runRefreshSessionBlocking` returns early while tiling is paused, so an edit made in an
/// external editor during a pause only lands when tiling resumes or any command runs (`runSession`
/// always reaches here). Upgrade path if that ever matters: call this from `reloadConfig` instead.
///
/// Skipped under XCTest: `setActivationPolicy` mutates the *test runner's* process, and there is
/// nothing to assert about it from a headless bundle. `AppVisibility` is the testable part.
@MainActor private var appliedActivationPolicy: NSApplication.ActivationPolicy?

@MainActor func syncAppVisibility() {
    guard !isUnitTest else { return }
    let visibility = AppVisibility(showMenuBarIcon: config.showMenuBarIcon, showDockIcon: config.showDockIcon)
    setIfChanged(\.showsMenuBarIcon, visibility.showsMenuBarIcon)
    let policy: NSApplication.ActivationPolicy = visibility.showsDockIcon ? .regular : .accessory
    if appliedActivationPolicy != policy {
        NSApp.setActivationPolicy(policy)
        appliedActivationPolicy = policy
    }
}

/// Assign only when the value actually changed. Every `@Published` write invalidates
/// `MenuBarExtra`, and `MenuBarLabel` then re-rasterizes the whole label through `ImageRenderer`
/// on the main thread. `updateTrayText` runs on every refresh, so unguarded assignment meant a
/// full SwiftUI-to-CGImage pass at up to 20Hz producing a byte-identical image nearly every time.
@MainActor private func setIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<TrayMenuModel, T>, _ value: T) {
    if TrayMenuModel.shared[keyPath: keyPath] != value {
        TrayMenuModel.shared[keyPath: keyPath] = value
    }
}

@MainActor func updateTrayText() {
    syncAppVisibility()
    let sortedMonitors = sortedMonitors
    let focus = focus
    setIfChanged(\.trayText, (activeMode?.takeIf { $0 != mainModeId }?.first.map { "[\($0.uppercased())] " } ?? "") +
        sortedMonitors
        .map {
            ($0.activeWorkspace == focus.workspace && sortedMonitors.count > 1 ? "*" : "") + $0.activeWorkspace.name
        }
        .joined(separator: " │ "))
    let workspaces = Workspace.all.map {
        let apps = $0.allLeafWindowsRecursive.map { $0.app.name?.takeIf { !$0.isEmpty } }.filterNotNil().toSet()
        let dash = " - "
        let suffix = switch () {
            case _ where !apps.isEmpty: dash + apps.sorted().joinTruncating(separator: ", ", length: 25)
            case _ where $0.isVisible: dash + $0.workspaceMonitor.name
            default: ""
        }
        return WorkspaceViewModel(name: $0.name, suffix: suffix, isFocused: focus.workspace == $0)
    }
    setIfChanged(\.workspaces, workspaces)
    var items = sortedMonitors.map {
        TrayItem(type: .workspace, name: $0.activeWorkspace.name, isActive: $0.activeWorkspace == focus.workspace)
    }
    let mode = activeMode?.takeIf { $0 != mainModeId }?.first.map { TrayItem(type: .mode, name: $0.uppercased(), isActive: true) }
    if let mode {
        items.insert(mode, at: 0)
    }
    setIfChanged(\.trayItems, items)
}

struct WorkspaceViewModel: Hashable {
    let name: String
    /// " - Safari, Terminal" or " - Built-in Display". Kept out of `name` so the menu can render
    /// the name monospaced and the context in the system font.
    let suffix: String
    let isFocused: Bool
}

enum TrayItemType: String, Hashable {
    case mode
    case workspace
}

struct TrayItem: Hashable, Identifiable {
    let type: TrayItemType
    let name: String
    let isActive: Bool
    var id: String { type.rawValue + name }
}
