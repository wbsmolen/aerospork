import AppKit
import Common

/// Runs the pre-quit cleanup for the ways of stopping the app that AppKit owns rather than POSIX:
/// an AppleEvent quit (`osascript -e 'tell application "AeroSpork" to quit'`), Force Quit's polite
/// first attempt, and logout / restart / shut down.
///
/// The cleanup is `makeAllWindowsVisibleAndRestoreSize()`. Hidden workspaces are emulated by parking
/// their windows off screen, so skipping it leaves them there: the next launch re-detects them at
/// those coordinates and files them under whatever workspace covers that area. Windows come back on
/// the wrong workspace, which reads as the app losing the layout.
///
/// Until this existed, only the menu bar's Quit item ran it. The signal handlers did not cover the
/// gap: they were registered `if isDebug`, so a release build trapped nothing at all; one of the two
/// was `SIGKILL`, which POSIX does not permit anyone to catch, so it never ran either; and `SIGTERM`
/// -- what logout, restart and `killall` actually send -- was not among them.
@MainActor
public final class AeroSporkAppDelegate: NSObject, NSApplicationDelegate {
    /// The menu bar's Quit reaches `NSApp.terminate` too, so this can be entered twice. Restoring an
    /// already-restored window is harmless but slow, and the second pass would run while the first
    /// is still moving windows.
    private var cleanupStarted = false

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if cleanupStarted { return .terminateNow }
        cleanupStarted = true
        // `.terminateLater` rather than doing this synchronously: the cleanup is a batch of
        // Accessibility writes across every hidden window, and blocking the main thread through it
        // is what makes a logout appear to hang.
        Task {
            defer { sender.reply(toApplicationShouldTerminate: true) }
            do {
                try await terminationHandler.beforeTermination()
            } catch {
                AppLog.session.error("Cleanup before quit failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return .terminateLater
    }
}
