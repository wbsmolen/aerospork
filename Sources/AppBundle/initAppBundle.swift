import AppKit
import Common
import Foundation

@MainActor public func initAppBundle() {
    initTerminationHandler()
    isCli = false
    initServerArgs()
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
