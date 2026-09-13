import AppKit
import Common

@MainActor
var appForTests: (any AbstractApp)? = nil

@MainActor
private var focusedApp: (any AbstractApp)? {
    get async throws {
        if isUnitTest {
            return appForTests
        } else {
            check(appForTests == nil)
            return try await NSWorkspace.shared.frontmostApplication.flatMapAsyncMainActor(MacApp.getOrRegister)
        }
    }
}

/// The frontmost app did not answer the focused-window read inside `axMessagingTimeout`.
///
/// Not the same answer as `nil`, "no focused window". See `syncFocusFromMacOs`.
struct NativeFocusUnknown: Error {}

@MainActor
func getNativeFocusedWindow() async throws -> Window? {
    try await focusedApp?.getFocusedWindow()
}

/// Takes macOS's focused window into the model -- unless the app did not answer.
///
/// An unanswered read tells us nothing, so it must leave `updateFocusCache` untouched: passing it on
/// as `nil` recorded "macOS has no focused window" and expired any in-flight focus request, and the
/// app's next answer -- still naming the window it had before a workspace switch -- then counted as
/// macOS changing its mind and bounced the user back. Busy Chromium and Electron apps are the ones
/// that miss the timeout, which is issue #39's population exactly.
@MainActor
func syncFocusFromMacOs() async throws {
    let nativeFocused: Window?
    do {
        nativeFocused = try await getNativeFocusedWindow()
    } catch is NativeFocusUnknown {
        debugLog("focused-window read went unanswered; keeping the model's focus as it is")
        return
    }
    if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
    updateFocusCache(nativeFocused)
}
