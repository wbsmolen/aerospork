import AppKit
import Common
import Foundation

/// Which already-running copy this process should give way to, if any.
///
/// The older copy wins: earlier launch date, then lower pid when launch dates are equal or unknown.
/// Deciding by age, not by "someone else is running", is what keeps two copies started at the same
/// moment -- the login item and a hand launch -- from both yielding and leaving none.
func runningCopyToYieldTo(me: (pid: pid_t, launchDate: Date?), others: [(pid: pid_t, launchDate: Date?)]) -> pid_t? {
    func isOlder(_ a: (pid: pid_t, launchDate: Date?), than b: (pid: pid_t, launchDate: Date?)) -> Bool {
        if let aDate = a.launchDate, let bDate = b.launchDate, aDate != bDate { return aDate < bDate }
        return a.pid < b.pid
    }
    return others.filter { $0.pid != me.pid && isOlder($0, than: me) }.min { isOlder($0, than: $1) }?.pid
}

/// When the kernel started `pid`, or nil when it cannot say.
///
/// The one clock every copy can be compared on. LaunchServices' `launchDate` is not: this process has
/// none yet when the check runs.
func processStartDate(_ pid: pid_t) -> Date? {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
    let start = info.kp_proc.p_un.__p_starttime
    return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
}

/// This process, in the terms `runningCopyToYieldTo` compares.
///
/// Not `NSRunningApplication.current`. `initAppBundle` runs in `App.init`, before `NSApplication` exists,
/// and there `NSRunningApplication.current` reports pid -1 and no launch date. -1 sorts before every real
/// pid, so each new copy would judge itself the oldest, never yield, and two window managers would run
/// at once -- the very bug this guards.
func currentCopyIdentity() -> (pid: pid_t, launchDate: Date?) {
    let pid = ProcessInfo.processInfo.processIdentifier
    return (pid, processStartDate(pid))
}

/// One copy per build. Starting the binary from a shell while the login item was running (#40) gave
/// two window managers: the second took over the CLI socket -- `bind` unlinks the old one -- and both
/// fought over every window. Debug and release builds have different bundle ids, so they still run
/// side by side as designed.
@MainActor private func exitIfAnotherCopyIsRunning() {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: aeroSporkAppId)
        .filter { !$0.isTerminated }
        .map { (pid: $0.processIdentifier, launchDate: processStartDate($0.processIdentifier)) }
    guard let running = runningCopyToYieldTo(me: currentCopyIdentity(), others: others) else { return }
    let message = "\(aeroSporkAppName) is already running (pid \(running)), so this copy is exiting. Quit that one first to restart."
    AppLog.server.notice("\(message, privacy: .public)")
    printStderr(message)
    exit(0)
}

@MainActor public func initAppBundle() {
    initTerminationHandler()
    isCli = false
    initServerArgs()
    // Before anything with side effects: pausing the release server, the signal handlers, workspace
    // memory, and above all the CLI socket, which a second copy would take over.
    exitIfAnotherCopyIsRunning()
    if isDebug {
        sendCommandToReleaseServer(args: ["enable", "off"])
    }
    // Not `if isDebug`. Hidden workspaces are emulated by parking windows off screen, and
    // `beforeTermination` is what puts them back; a release build needs that at least as much as a
    // debug one, and until now it registered no handlers at all.
    //
    // SIGTERM, not SIGKILL: SIGKILL cannot be caught by anyone, so registering it only implied a
    // guarantee that never existed, while SIGTERM -- what `killall`, logout, restart and shut down
    // send -- went untrapped. AppKit-initiated quits are handled by `AeroSporkAppDelegate`.
    interceptTermination(SIGINT)
    interceptTermination(SIGTERM)
    if !reloadConfig() {
        check(reloadConfig(forceConfigUrl: defaultConfigUrl))
    }
    // The one record that answers "did my AEROSPORK_DEBUG_LOG take?".
    //
    // The verbose channel writes at `.debug`, which the unified log does not persist, so a switch
    // that did not take produces exactly nothing -- indistinguishable from a trace that found
    // nothing. `launchctl setenv` reaches only processes launched afterwards, which is easy to get
    // wrong, and until now there was no way to tell. This line is `.notice`, so `log show` finds it
    // after the fact. See https://github.com/wbsmolen/aerospork/issues/39.
    AppLog.config.notice(
        "AeroSpork \(aeroSporkAppVersion, privacy: .public) \(gitHash, privacy: .public) started, verbose tracing: \(isDebugLoggingEnabled ? "on" : "off", privacy: .public)",
    )

    // Before anything can register a window: `MacWindow.getOrRegister` consults it on the first
    // adoption of each window, and a miss there is permanent for that window.
    WorkspaceMemory.load()

    checkAccessibilityPermissions()
    startUnixSocketServer()
    GlobalObserver.initObserver()
    ConfigFileWatcher.start() // hot-reload config on external edits
    // After the observers are up, so a first-launch update prompt cannot race window adoption.
    Updater.shared.start()
    runDetached("appStartup") {
        Workspace.garbageCollectUnusedWorkspaces() // init workspaces
        _ = Workspace.all.first?.focusWorkspace()
        try await runRefreshSessionBlocking(.startup, layoutWorkspaces: false)
        try await runSession(.startup, .checkServerIsEnabledOrDie) {
            // Apply workspace-to-monitor force assignments at startup
            autoMoveWorkspacesToAssignedMonitors()
            smartLayoutAtStartup()
            _ = try await config.afterStartupCommand.runCmdSeq(.defaultEnv, .emptyStdin)
        }
    }
}

@MainActor
private func smartLayoutAtStartup() {
    let workspace = focus.workspace
    let root = workspace.rootTilingContainer
    if root.children.count <= 3 {
        root.layout = .tiles
    } else {
        root.layout = .accordion
    }
}

@TaskLocal
var _isStartup: Bool? = false
var isStartup: Bool { _isStartup ?? dieT("isStartup is not initialized") }

struct ServerArgs: Sendable {
    var configLocation: String? = nil
}

private let serverHelp = """
    USAGE: \(CommandLine.arguments.first ?? "AeroSpork.app/Contents/MacOS/aerospork") [<options>]

    OPTIONS:
      -h, --help              Print help
      -v, --version           Print AeroSpork.app version
      --config-path <path>    Config path. It will take priority over ~/.aerospork.toml
                              and ${XDG_CONFIG_HOME}/aerospork/aerospork.toml
    """

private nonisolated(unsafe) var _serverArgs = ServerArgs()
var serverArgs: ServerArgs { _serverArgs }
private func initServerArgs() {
    var args: [String] = Array(CommandLine.arguments.dropFirst())
    if args.contains(where: { $0 == "-h" || $0 == "--help" }) {
        print(serverHelp)
        exit(0)
    }
    while !args.isEmpty {
        switch args.first {
            case "--version", "-v":
                print("\(aeroSporkAppVersion) \(gitHash)")
                exit(0)
            case "--config-path":
                if let arg = args.getOrNil(atIndex: 1) {
                    _serverArgs.configLocation = arg
                } else {
                    cliError("Missing <path> in --config-path flag")
                }
                args = Array(args.dropFirst(2))
            case "-NSDocumentRevisionsDebugMode" where isDebug:
                printStderr("Running from Xcode. Skip args parsing...")
                return
            default:
                cliError("Unrecognized flag '\(args.first.orDie())'")
        }
    }
    if let path = serverArgs.configLocation, !FileManager.default.fileExists(atPath: path) {
        cliError("\(path) doesn't exist")
    }
}
