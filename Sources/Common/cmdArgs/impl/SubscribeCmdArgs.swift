public struct SubscribeCmdArgs: CmdArgs {
    public let rawArgs: EquatableNoop<[String]>
    public init(rawArgs: [String]) { self.rawArgs = .init(rawArgs) }
    public static let parser: CmdParser<Self> = cmdParser(
        kind: .subscribe,
        allowInConfig: false,
        help: subscribe_help_generated,
        options: [
            "--all": trueBoolFlag(\.all),
        ],
        arguments: [ArgParser(\.events, parseSubscribeEvents)],
    )

    public var all: Bool = false
    public var events: [SubscribeEvent] = []
    /*conforms*/ public var windowId: UInt32?
    /*conforms*/ public var workspaceName: WorkspaceName?

    public var subscribedEvents: Set<SubscribeEvent> { all ? Set(SubscribeEvent.allCases) : Set(events) }
}

/// The first event and every one after it, up to the next flag.
private func parseSubscribeEvents(arg: String, nextArgs: inout [String]) -> Parsed<[SubscribeEvent]> {
    var events: [SubscribeEvent] = []
    for raw in [arg] + nextArgs.allNextNonFlagArgs() {
        switch parseEnum(raw, SubscribeEvent.self) {
            case .success(let event): events.append(event)
            case .failure(let error): return .failure(error)
        }
    }
    return .success(events)
}

public func parseSubscribeCmdArgs(_ args: [String]) -> ParsedCmd<SubscribeCmdArgs> {
    parseSpecificCmdArgs(SubscribeCmdArgs(rawArgs: args), args)
        .filter("Name the events to stream, or pass --all.\nPossible events: \(SubscribeEvent.unionLiteral)") { $0.all || !$0.events.isEmpty }
        .filterNot("--all streams every event, so it takes no list of events") { $0.all && !$0.events.isEmpty }
}

/// The events `aerospork subscribe` streams. Their names and fields are a public contract, documented in
/// docs/aerospork-subscribe.adoc.
public enum SubscribeEvent: String, CaseIterable, Equatable, Sendable {
    case focusChanged = "focus-changed"
    case focusedWorkspaceChanged = "focused-workspace-changed"
    case focusedMonitorChanged = "focused-monitor-changed"
    case modeChanged = "mode-changed"
    case windowDetected = "window-detected"
    case workspaceWindowsChanged = "workspace-windows-changed"
}
