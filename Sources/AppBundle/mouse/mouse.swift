import AppKit

@MainActor var currentlyManipulatedWithMouseWindowId: UInt32? = nil
var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

/// How many left mouse-downs the system has seen. A new physical press changes it; a drag does not. No permission
/// needed, and about 0.02 µs.
var leftMouseDownCount: UInt32 { CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown) }

/// The window the focus check below last passed for, and the press it passed during.
@MainActor private var lastVerifiedPress: (windowId: UInt32, press: UInt32)? = nil

@MainActor
func isManipulatedWithMouse(_ window: Window, buttonDown: Bool = isLeftMouseButtonDown, press: UInt32 = leftMouseDownCount) async throws -> Bool {
    guard !window.isHiddenInCorner, // Don't allow to resize/move windows of hidden workspaces
          buttonDown,
          currentlyManipulatedWithMouseWindowId == nil || window.windowId == currentlyManipulatedWithMouseWindowId
    else { return false }
    // An established drag sends about 60 events a second, each of which read the focused window. Skipped only
    // within the press the check passed in: the drag id alone can be stale after a missed mouse-up, and then a
    // later press elsewhere plus this window moving itself would swap it to the mouse.
    if window.windowId == currentlyManipulatedWithMouseWindowId, lastVerifiedPress?.windowId == window.windowId, lastVerifiedPress?.press == press {
        return true
    }
    let focused: Bool
    do {
        focused = try await getNativeFocusedWindow() == window
    } catch is NativeFocusUnknown {
        focused = false // what an unanswered read meant before it could be told apart from "none"
    }
    if focused { lastVerifiedPress = (window.windowId, press) }
    return focused
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint {
    let mainMonitorHeight: CGFloat = mainMonitor.height
    let location = NSEvent.mouseLocation
    return location.copy(\.y, mainMonitorHeight - location.y)
}
