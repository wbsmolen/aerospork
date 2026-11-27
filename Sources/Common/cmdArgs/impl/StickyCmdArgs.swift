public struct StickyCmdArgs: CmdArgs {
    public let rawArgs: EquatableNoop<[String]>
    fileprivate init(rawArgs: [String]) { self.rawArgs = .init(rawArgs) }
    public static let parser: CmdParser<Self> = cmdParser(
        kind: .sticky,
        allowInConfig: true,
        help: sticky_help_generated,
        options: [
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--window-id": optionalWindowIdFlag(),
        ],
        arguments: [ArgParser(\.toggle, parseToggleEnum)],
    )

    public var toggle: ToggleEnum = .toggle
    public var failIfNoop: Bool = false
    /*conforms*/ public var windowId: UInt32?
    /*conforms*/ public var workspaceName: WorkspaceName?
}

public func parseStickyCmdArgs(_ args: [String]) -> ParsedCmd<StickyCmdArgs> {
    parseSpecificCmdArgs(StickyCmdArgs(rawArgs: args), args)
        .filter("--fail-if-noop requires 'on' or 'off' argument") { $0.failIfNoop.implies($0.toggle == .on || $0.toggle == .off) }
}
