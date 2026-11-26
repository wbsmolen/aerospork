public struct SwapCmdArgs: CmdArgs {
    public let rawArgs: EquatableNoop<[String]>
    init(rawArgs: [String]) { self.rawArgs = .init(rawArgs) }
    public static let parser: CmdParser<Self> = cmdParser(
        kind: .swap,
        allowInConfig: true,
        help: swap_help_generated,
        options: [
            "--window-id": optionalWindowIdFlag(),
            "--swap-focus": trueBoolFlag(\.swapFocus),
            "--wrap-around": trueBoolFlag(\.wrapAround),
        ],
        arguments: [newArgParser(\.target, { arg, _ in parseEnum(arg, SwapTarget.self) }, mandatoryArgPlaceholder: SwapTarget.unionLiteral)],
    )

    public var target: Lateinit<SwapTarget> = .uninitialized
    public var swapFocus: Bool = false
    public var wrapAround: Bool = false
    /*conforms*/ public var windowId: UInt32?
    /*conforms*/ public var workspaceName: WorkspaceName?

    public init(rawArgs: [String], target: SwapTarget) {
        self.rawArgs = .init(rawArgs)
        self.target = .initialized(target)
    }
}

public enum SwapTarget: String, CaseIterable, Equatable, Sendable {
    case left, down, up, right
    case dfsNext = "dfs-next"
    case dfsPrev = "dfs-prev"

    public var direction: CardinalDirection? { CardinalDirection(rawValue: rawValue) }
}
