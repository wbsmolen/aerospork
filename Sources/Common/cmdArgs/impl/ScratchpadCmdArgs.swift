public struct ScratchpadCmdArgs: CmdArgs {
    public let rawArgs: EquatableNoop<[String]>
    public init(rawArgs: [String]) { self.rawArgs = .init(rawArgs) }
    public static let parser: CmdParser<Self> = cmdParser(
        kind: .scratchpad,
        allowInConfig: true,
        help: scratchpad_help_generated,
        options: [
            "--app-bundle-id": singleValueOption(\.appBundleId, "<app-bundle-id>") { $0 },
        ],
        arguments: [],
    )

    public var appBundleId: String?
    /*conforms*/ public var windowId: UInt32?
    /*conforms*/ public var workspaceName: WorkspaceName?
}
