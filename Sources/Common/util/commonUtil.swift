import AppKit
import Darwin
import Foundation
import os

public let unixUserName = NSUserName()
public let mainModeId = "main"

public let potentialBugsUrl = "https://github.com/wbsmolen/aerospork/discussions/categories/potential-bugs"

@TaskLocal
public var refreshSessionEvent: RefreshSessionEvent? = nil

@TaskLocal
private var recursionDetectorDuringTermination = false

public func dieT<T>(
    _ __message: String = "",
    file: String = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> T {
    let _message = __message.contains("\n") ? "\n" + __message.prefixLines(with: "    ") : __message
    let thread = Thread.current
    let message =
        """
        Please report to:
            \(potentialBugsUrl)
            Please describe what you did to trigger this error

        Message: \(_message)
        Version: \(aeroSporkAppVersion)
        Git hash: \(gitHash)
        refreshSessionEvent: \(refreshSessionEvent.prettyDescription)
        Date: \(Date.now)
        Thread name: \(thread.name.prettyDescription)
        Is main thread: \(thread.isMainThread)
        axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken.prettyDescription)
        macOS version: \(ProcessInfo().operatingSystemVersionString)
        Coordinate: \(file):\(line):\(column) \(function)
        recursionDetectorDuringTermination: \(recursionDetectorDuringTermination)
        cli: \(isCli)
        Monitor count: \(NSScreen.screens.count)
        Displays have separate spaces: \(NSScreen.screensHaveSeparateSpaces)

        Stacktrace:
        \(getStringStacktrace())
        """
    if !isUnitTest && isServer {
        showMessageInGui(
            filenameIfConsoleApp: recursionDetectorDuringTermination
                ? "aerospork-runtime-error-recursion.txt"
                : "aerospork-runtime-error.txt",
            title: "AeroSpork Runtime Error",
            message: message,
        )
    } else if isUnitTest {
        // No dialog, and `fatalError` under XCTest kills the bundle with a one-line summary.
        // stderr is the only place the report survives.
        printStderr("##### AeroSpork Runtime Error #####\n\n" + message)
    }
    if !recursionDetectorDuringTermination {
        // Only the running server has windows to un-hide, and only it has a GUI worth keeping alive
        // for a moment. Headlessly (unit test, CLI, CI) there is nothing to wait for.
        awaitTerminationHandler(timeout: !isUnitTest && isServer ? .seconds(5) : nil)
    }
    fatalError("\n" + message)
}

/// Runs `terminationHandler.beforeTermination()` and blocks for at most `timeout`; `nil` means
/// "don't run it at all". Returns whether it finished.
///
/// The bound is the whole point. `beforeTermination()` is `@MainActor` and `die()` is almost always
/// called ON the main actor, so the task below cannot start until this thread stops waiting: the
/// unbounded `semaphore.wait()` this replaces was a guaranteed deadlock on that path. That is what
/// turned "the bundled default config doesn't parse" into a silent forever-hang at 100% CPU instead
/// of a reported crash -- twice in one day, both times misread as a SwiftPM lock.
@discardableResult
public func awaitTerminationHandler(timeout: DispatchTimeInterval?) -> Bool {
    guard let timeout else { return false }
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        defer { semaphore.signal() }
        do {
            try await $recursionDetectorDuringTermination.withValue(true) {
                try await terminationHandler.beforeTermination()
            }
        } catch {
            // `defer` signals regardless, so without this the wait below returns `.success` and we
            // report a clean shutdown for a handler that actually threw.
            printStderr("Termination handler threw: \(error)")
        }
    }
    if semaphore.wait(timeout: .now() + timeout) == .success { return true }
    printStderr("Termination handler did not finish in time. Exiting anyway.")
    return false
}

public enum RefreshSessionEvent: Sendable, CustomStringConvertible {
    case globalObserver(String)
    case globalObserverLeftMouseUp
    case menuBarButton
    case hotkeyBinding
    case startup
    case socketServer
    case resetManipulatedWithMouse
    case ax(String)
    case onFocusedMonitorChanged
    case onFocusedWorkspaceChanged
    case onFocusChanged

    public var isStartup: Bool {
        if case .startup = self { return true } else { return false }
    }

    /// Did a person ask for this session, or did the world just move?
    ///
    /// Only used to decide what is worth an always-on log record: a focus change under a hotkey, a
    /// CLI command or a menu click is the user getting what they asked for, while one under an
    /// accessibility notification is the window manager acting on its own -- which is the half a
    /// bug report needs. Callbacks are not user-initiated: `on-focus-changed` fires *because*
    /// focus already moved.
    public var isUserInitiated: Bool {
        switch self {
            // `.ax` counts. It looks like the world moving, but the only two places that tag a
            // *session* with it are `movedObs` and `resizedObs`, and both take that branch only when
            // `isManipulatedWithMouse` -- i.e. the user has the window under the pointer right now.
            // The `.ax` notifications that are genuinely involuntary go to `runRefreshSession`, which
            // never reaches this. `resetManipulatedWithMouse` is the end of that same drag.
            case .hotkeyBinding, .socketServer, .menuBarButton, .globalObserverLeftMouseUp,
                 .resetManipulatedWithMouse, .ax: true
            case .globalObserver, .startup,
                 .onFocusedMonitorChanged, .onFocusedWorkspaceChanged, .onFocusChanged: false
        }
    }

    public var description: String {
        switch self {
            case .ax(let str): "ax(\(str))"
            case .globalObserver(let str): "globalObserver(\(str))"
            case .globalObserverLeftMouseUp: "globalObserverLeftMouseUp"
            case .hotkeyBinding: "hotkeyBinding"
            case .menuBarButton: "menuBarButton"
            case .resetManipulatedWithMouse: "resetManipulatedWithMouse"
            case .socketServer: "socketServer"
            case .startup: "startup"
            case .onFocusedMonitorChanged: "onFocusedMonitorChanged"
            case .onFocusedWorkspaceChanged: "onFocusedWorkspaceChanged"
            case .onFocusChanged: "onFocusChanged"
        }
    }
}

public func getStringStacktrace() -> String { Thread.callStackSymbols.joined(separator: "\n") }

@inlinable public func die(
    _ message: String = "",
    file: String = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) -> Never {
    dieT(message, file: file, line: line, column: column, function: function)
}

public func check(
    _ condition: Bool,
    _ message: @autoclosure () -> String = "",
    file: String = #fileID,
    line: Int = #line,
    column: Int = #column,
    function: String = #function,
) {
    if !condition {
        die(message(), file: file, line: line, column: column, function: function)
    }
}

/// Whether XCTest is loaded. A `let`, not a computed `var`: this was an ObjC runtime class lookup
/// **by string** re-executed on every read, and it is read from `monitors`, `mainMonitor`,
/// `Window.get(byId:)` and `castToAxUiElementMock` -- dozens of times per refresh. Whether XCTest is
/// in the process cannot change after launch, so the lookup belongs at first use, not at every use.
public let isUnitTest: Bool = NSClassFromString("XCTestCase") != nil

extension CaseIterable where Self: RawRepresentable, RawValue == String {
    public static var cliArgsCases: [String] { allCases.map(\.rawValue) }
    public static var unionLiteral: String { cliArgsCases.joinedCliArgs }
}

extension [String] {
    public var joinedCliArgs: String { "(" + self.joined(separator: "|") + ")" }
}

extension Int {
    public func toDouble() -> Double { Double(self) }
}

public func + <K, V>(lhs: [K: V], rhs: [K: V]) -> [K: V] {
    lhs.merging(rhs) { _, r in r }
}

extension String {
    public func removePrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}

extension Bool {
    /// Implication
    /// | a     | b     | a.implies(b) |
    /// |-------|-------|--------------|
    /// | false | false | true         |
    /// | false | true  | true         |
    /// | true  | false | false        |
    /// | true  | true  | true         |
    public func implies(_ mustHold: @autoclosure () -> Bool) -> Bool { !self || mustHold() }
}

extension Double {
    public var squared: Double { self * self }
}

extension Slice {
    public func toArray() -> [Base.Element] { Array(self) }
}

extension URL {
    public func open(with url: URL) {
        NSWorkspace.shared.open([self], withApplicationAt: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

public func printStderr(_ msg: String) {
    fputs(msg + "\n", stderr)
}

public func cliError(_ message: String = "") -> Never {
    cliErrorT(message)
}

public func cliErrorT<T>(_ message: String = "") -> T {
    printStderr(message)
    exit(1)
}

@inlinable
public func allowOnlyCancellationError<T>(isolation: isolated (any Actor)? = #isolation, _ block: () async throws -> sending T) async throws -> sending T {
    do {
        return try await block()
    } catch let e as CancellationError {
        throw e
    } catch {
        die("throws must only be used for CancellationError")
    }
}

// Debug logging infrastructure
private let debugLogger = OSLog(subsystem: aeroSporkAppId, category: "Debug")

/// Opt-in at runtime, not compile time: a build that ships to users can still be compiled with DEBUG, so an
/// `#if DEBUG` gate would leave this on for everyone. Set AEROSPORK_DEBUG_LOG=1 to enable.
public let isDebugLoggingEnabled = ProcessInfo.processInfo.environment["AEROSPORK_DEBUG_LOG"] != nil

/// `message` is an @autoclosure so the interpolation is never built when logging is off -- this is
/// called several times per refresh and once per command parse, so eager evaluation was the bulk of
/// the cost. `#fileID` is already just "Module/File.swift", so no URL parsing is needed, and os_log
/// timestamps its own records, so no DateFormatter either (that was the single most expensive part).
public func debugLog(_ message: @autoclosure () -> String, file: String = #fileID, function: String = #function, line: Int = #line) {
    guard isDebugLoggingEnabled else { return }
    let logMessage = "\(file):\(line) \(function) - \(message())"
    os_log(.debug, log: debugLogger, "%{public}s", logMessage)
    printStderr("[DEBUG] \(logMessage)")
}
