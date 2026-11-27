import AppKit
import Common

private let disclaimer =
    """
    !!! DISCLAIMER !!!
    !!! 'debug-windows' command is not stable API. Please don't rely on the command existence and output format !!!
    !!! The only intended use case is to report bugs about incorrect windows handling !!!
    """

@MainActor private var debugWindowsState: DebugWindowsState = .notRecording
// TRADEOFF: insertion-ordered, capped at debugWindowsLimit entries; plain pair array beats an OrderedDictionary dep here
@MainActor private var debugWindowsLog: [(id: UInt32, dump: String)] = []
private let debugWindowsLimit = 10

enum DebugWindowsState {
    case recording
    case notRecording
    case recordingAborted
}

struct DebugWindowsCommand: Command {
    let args: DebugWindowsCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        if args.tree {
            return io.out((JSONEncoder.aeroSporkDefault.encodeToString(treeDump()) ?? "null") + "\n")
        }
        if let windowId = args.windowId {
            guard let window = Window.get(byId: windowId) else {
                return io.err("Can't find window with the specified window-id: \(windowId)")
            }
            io.out(try await dumpWindowDebugInfo(window) + "\n")
            io.out(disclaimer)
            return true
        }
        switch debugWindowsState {
            case .recording:
                debugWindowsState = .notRecording
                io.out(debugWindowsLog.map { $0.dump }.joined(separator: "\n\n"))
                io.out("\n" + disclaimer + "\n")
                io.out("Debug session finished" + "\n")
                debugWindowsLog = []
                return true
            case .notRecording:
                debugWindowsState = .recording
                debugWindowsLog = []
                io.out(
                    """
                    Debug windows session has started
                    1. Focus the problematic window
                    2. Run 'aerospork debug-windows' once again to finish the session and get the results
                    """,
                )
                // Make sure that the Terminal window that started the recording is recorded first
                guard let target = args.resolveTargetOrReportError(env, io) else { return false }
                if let window = target.windowOrNil {
                    try await debugWindowsIfRecording(window)
                }
                return true
            case .recordingAborted:
                io.out(
                    """
                    Recording of the previous session was aborted after \(debugWindowsLimit) windows has been focused
                    Run the command one more time to start new debug session
                    """,
                )
                debugWindowsState = .notRecording
                debugWindowsLog = []
                return false
        }
    }
}

@MainActor
private func dumpWindowDebugInfo(_ window: Window) async throws -> String {
    let window = window as! MacWindow
    let appInfoDic = window.macApp.nsApp.bundleURL.flatMap { Bundle.init(url: $0) }?.infoDictionary ?? [:]

    var result: [String: Json] = try await window.dumpAxInfo()

    result["Aero.axWindowId"] = .newOrDie(window.windowId)
    result["Aero.workspace"] = .string(window.nodeWorkspace?.name ?? "nil")
    result["Aero.treeNodeParent"] = .newOrDie(String(describing: window.parent))
    result["Aero.macOS.version"] = .string(ProcessInfo().operatingSystemVersionString) // because built-in apps might behave differently depending on the OS version
    result["Aero.App.appBundleId"] = .newOrDie(window.app.bundleId)
    result["Aero.App.versionShort"] = .newOrDie(appInfoDic["CFBundleShortVersionString"])
    result["Aero.App.version"] = .newOrDie(appInfoDic["CFBundleVersion"])
    result["Aero.App.nsApp.activationPolicy"] = .string(window.macApp.nsApp.activationPolicy.prettyDescription)
    result["Aero.App.nsApp.execPath"] = .string(window.macApp.nsApp.executableURL.prettyDescription)
    result["Aero.AXApp"] = .dict(try await window.macApp.dumpAppAxInfo())

    let isDialog = try await window.isDialogHeuristic()
    let isWindow = try await window.isWindowHeuristic()
    result["Aero.AxUiElementWindowType"] = .newOrDie(AxUiElementWindowType.new(isWindow: isWindow, isDialog: { isDialog }).rawValue)
    result["Aero.AxUiElementWindowType_isDialogHeuristic"] = .newOrDie(isDialog)

    var matchingCallbacks: [Json] = []
    for callback in config.onWindowDetected where try await callback.matches(window, title: { try await window.title }) {
        matchingCallbacks.append(callback.debugJson)
    }
    result["Aero.on-window-detected"] = .array(matchingCallbacks)

    return JSONEncoder.aeroSporkDefault.encodeToString(result).prettyDescription
        .prefixLines(with: "\(window.app.bundleId ?? "nil-bundle-id").\(window.windowId) ||| ")
}

@MainActor
func debugWindowsIfRecording(_ window: Window) async throws {
    switch debugWindowsState {
        case .recording: break
        case .notRecording, .recordingAborted: return
    }
    if debugWindowsLog.count > debugWindowsLimit {
        debugWindowsState = .recordingAborted
        debugWindowsLog = []
    }
    if debugWindowsLog.contains(where: { $0.id == window.windowId }) {
        return
    }
    debugWindowsLog.append((id: window.windowId, dump: try await dumpWindowDebugInfo(window)))
}

/// The state AeroSpork holds, for `debug-windows --tree`. Reads memory only: no AX call, so a hung app
/// cannot hang the dump, and nothing that creates a workspace or a container (`get(byName:)`,
/// `rootTilingContainer`, `Monitor.activeWorkspace` all can).
@MainActor
func treeDump() -> Json {
    var apps: [pid_t: any AbstractApp] = MacApp.allAppsMap.mapValues { $0 }
    func dump(_ node: TreeNode) -> Json {
        func container(_ kind: String) -> Json { .dict(["container": .string(kind), "children": .array(node.children.map(dump))]) }
        switch node.nodeCases {
            case .window(let window):
                apps[window.app.pid] = window.app
                return .dict([
                    "window": .uint32(window.windowId),
                    "pid": .int(Int(window.app.pid)),
                    "bundleId": window.app.bundleId.map(Json.string) ?? .null,
                    "layoutReason": .string(window.layoutReason.debugDescription),
                    "backgroundTab": .bool(window.isBackgroundTab),
                ])
            case .tilingContainer(let tiling):
                return .dict([
                    "container": .string("tiling"),
                    "layout": .string(tiling.layout.rawValue),
                    "orientation": .string(tiling.orientation.rawValue),
                    "away": .array(tiling.awayWindows.map { .uint32($0.id) }),
                    "children": .array(tiling.children.map(dump)),
                ])
            case .workspace(let workspace):
                return .dict([
                    "workspace": .string(workspace.name),
                    "visibleAt": workspace.visibleScreenPoint.map(\.debugJson) ?? .null,
                    "children": .array(workspace.children.map(dump)),
                ])
            case .macosMinimizedWindowsContainer: return container("macos-minimized")
            case .macosHiddenAppsWindowsContainer: return container("macos-hidden-app")
            case .macosFullscreenWindowsContainer: return container("macos-fullscreen")
            case .macosPopupWindowsContainer: return container("macos-popups")
            case .scratchpadContainer: return container("scratchpad")
        }
    }

    let workspaces = Workspace.all
    let tree = workspaces.map(dump) + [dump(macosMinimizedWindowsContainer), dump(macosPopupWindowsContainer), dump(scratchpadContainer)]
    let monitorPoints = monitors.map(\.rect.topLeftCorner)
    var inconsistencies: [Json] = []
    for workspace in workspaces {
        if let point = workspace.visibleScreenPoint, !monitorPoints.contains(point) {
            inconsistencies.append(.string("workspace '\(workspace.name)' is visible at \(point), where no monitor is"))
        }
    }
    let appsJson: [Json] = apps.values.sorted { $0.pid < $1.pid }.map { app in
        var result: [String: Json] = ["pid": .int(Int(app.pid)), "bundleId": app.bundleId.map(Json.string) ?? .null]
        if let macApp = app as? MacApp {
            result["isTerminated"] = .bool(macApp.nsApp.isTerminated)
            result["processIsGone"] = .bool(processIsGone(macApp.pid))
            if macApp.nsApp.isGone {
                inconsistencies.append(.string("app \(app.bundleId ?? "?") (\(app.pid)) is gone but still registered"))
            }
        }
        return .dict(result)
    }
    return .dict([
        "monitors": .array(monitors.map { monitor in
            let point = monitor.rect.topLeftCorner
            return .dict([
                "name": .string(monitor.name),
                "uuid": monitor.fingerprint?.displayUUID.map(Json.string) ?? .null,
                "origin": point.debugJson,
                "visibleWorkspace": workspaces.first { $0.visibleScreenPoint == point }.map { .string($0.name) } ?? .null,
            ])
        }),
        "tree": .array(tree),
        "apps": .array(appsJson),
        "inconsistencies": .array(inconsistencies),
    ])
}

extension CGPoint {
    fileprivate var debugJson: Json { .dict(["x": .int(Int(x)), "y": .int(Int(y))]) }
}

extension LayoutReason {
    fileprivate var debugDescription: String {
        switch self {
            case .standard: "standard"
            case .macos(let kind, let workspace): "macos(from: \(kind), workspace: \(workspace ?? "nil"))"
        }
    }
}
