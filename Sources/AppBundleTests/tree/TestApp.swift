@testable import AppBundle
import Common

final class TestApp: AbstractApp {
    let pid: Int32
    let bundleId: String?
    let name: String?
    let execPath: String? = nil
    let bundlePath: String? = nil
    @MainActor
    static let shared = TestApp()

    private init() {
        self.pid = 0
        self.bundleId = "com.bsmolen.aerospork.test-app"
        self.name = bundleId
    }

    var _windows: [Window] = []
    var windows: [Window] {
        get { _windows }
        set {
            if let focusedWindow {
                check(newValue.contains(focusedWindow))
            }
            _windows = newValue
        }
    }
    private var _focusedWindow: Window? = nil
    var focusedWindow: Window? {
        get { _focusedWindow }
        set {
            if let window = newValue {
                check(windows.contains(window))
            }
            _focusedWindow = newValue
        }
    }
    /// Fail the focused-window read the way an app that misses `axMessagingTimeout` does.
    @MainActor var focusedWindowReadTimesOut = false
    /// On a real app, each read is an AX round trip.
    @MainActor var focusedWindowReads = 0
    @MainActor func getFocusedWindow() throws -> Window? {
        focusedWindowReads += 1
        if focusedWindowReadTimesOut { throw NativeFocusUnknown() }
        return _focusedWindow
    }
}
