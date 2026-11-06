import AppKit
import Common
import Sparkle

/// In-app updates.
///
/// AeroSpork cannot ship through the App Store: it drives other applications' windows through the
/// Accessibility APIs, which do not work in a sandbox, and it reads window ids through a private
/// symbol. So there is no store update mechanism to inherit. A window manager that silently goes
/// stale is worse than one that asks, so it checks a signed appcast itself.
///
/// The updater is only meaningful in a release build. A debug build has no `SUFeedURL` in its
/// Info.plist (`resources/Info-Debug.plist` deliberately omits it), so Sparkle would look up
/// nothing; `isEnabled` reflects that rather than showing a control that cannot work.
@MainActor
final class Updater {
    static let shared = Updater()
    private let reminder = UpdateReminder()

    /// `startingUpdater: false` because a menu-bar agent that pops an update window over whatever
    /// you are doing, seconds after login, is hostile. `start()` is called once the app is up.
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: reminder,
    )

    /// Whether this build can check at all. False in debug, and false in a release bundle whose
    /// Info.plist somehow lost the key, which is worth surfacing rather than failing silently.
    let isEnabled: Bool

    private init() {
        isEnabled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    }

    func start() {
        guard isEnabled else {
            debugLog("Updater: no SUFeedURL in this build, not starting Sparkle")
            return
        }
        controller.startUpdater()
    }

    /// Explicit check, from the menu bar or Settings. Shows progress and "you are up to date",
    /// which a background check deliberately does not.
    func checkForUpdates() {
        guard isEnabled else { return }
        controller.checkForUpdates(nil)
    }
}

/// A menu-bar agent has no Dock icon to bounce, so a scheduled update's alert opens behind whatever
/// you are working in and can sit there unseen. Bring it forward; it comes up at most once per release.
private final class UpdateReminder: NSObject, SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate, !state.userInitiated { NSApp.activate(ignoringOtherApps: true) }
    }
}
