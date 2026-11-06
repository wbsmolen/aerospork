public struct EnableCmdArgs: CmdArgs {
    public let rawArgs: EquatableNoop<[String]>
    fileprivate init(rawArgs: [String]) { self.rawArgs = .init(rawArgs) }
    public static let parser: CmdParser<Self> = cmdParser(
        kind: .enable,
        allowInConfig: true,
        help: enable_help_generated,
        options: [
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
        ],
        arguments: [newArgParser(\.targetState, parseState, mandatoryArgPlaceholder: ToggleEnum.unionLiteral)],
    )
    /*conforms*/ public var windowId: UInt32?
    /*conforms*/ public var workspaceName: WorkspaceName?
    public var targetState: Lateinit<ToggleEnum> = .uninitialized
    public var failIfNoop: Bool = false

    public init(rawArgs: [String], targetState: ToggleEnum) {
        self.rawArgs = .init(rawArgs)
        self.targetState = .initialized(targetState)
    }
}

public func parseEnableCmdArgs(_ args: [String]) -> ParsedCmd<EnableCmdArgs> {
    return parseSpecificCmdArgs(EnableCmdArgs(rawArgs: args), args)
        .filterNot("--fail-if-noop is incompatible with 'toggle' argument") { $0.targetState.val == .toggle && $0.failIfNoop }
}

private func parseState(arg: String, nextArgs: inout [String]) -> Parsed<ToggleEnum> {
    parseEnum(arg, ToggleEnum.self)
}
