import Common
import Darwin
import Foundation

let usage =
    """
    USAGE: \(CommandLine.arguments.first ?? "aerospork") [-h|--help] [-v|--version] <subcommand> [<args>...]

    SUBCOMMANDS:
    \(subcommandDescriptions.sortedBy { $0[0] }.toPaddingTable(columnSeparator: "   ").joined(separator: "\n"))
    """

/// What the CLI has decided to do, decided before any I/O happens.
///
/// Split out so the argument handling can be asserted on: every branch of `main()` ends in
/// `exit()`, which terminates the test process instead of returning a value, so the decisions have
/// to leave the function before they can be tested at all.
enum CliAction: Equatable {
    /// No arguments: usage belongs on stderr, and the exit code is non-zero.
    case usageError
    /// `-h` / `--help`.
    case usage
    /// A subcommand's own `--help` text.
    case help(String)
    case badArgs(String)
    /// `-v` / `--version`. Answered by the client alone when the server is unreachable.
    case version
    case send([String], readsStdin: Bool)
}

/// Whether the command takes its `next`/`prev` list from stdin. Nothing else may touch it: in a
/// `while read` loop the first call would swallow the loop's input, and a pipe that never closes
/// would hang a command that has no use for it.
func readsStdin(_ cmd: any CmdArgs) -> Bool {
    switch cmd {
        case let cmd as WorkspaceCmdArgs: cmd.target.val.isRelatve
        case let cmd as MoveNodeToWorkspaceCmdArgs: cmd.target.val.isRelatve
        default: false
    }
}

/// The whole argument-handling decision. Pure: no I/O, no `exit()`, no globals but the parser.
func plan(args: [String]) -> CliAction {
    if args.isEmpty { return .usageError }
    if args.first == "--help" || args.first == "-h" { return .usage }
    // Deliberately not run through `parseCmdArgs`: `--version` is not a subcommand, and it must
    // still answer when there is no server to ask.
    if args.first == "--version" || args.first == "-v" { return .version }
    return switch parseCmdArgs(args) {
        case .cmd(let cmd): .send(args, readsStdin: readsStdin(cmd))
        case .help(let help): .help(help)
        case .failure(let e): .badArgs(e)
    }
}

/// A message for stderr and the code to exit with. `run` returns these instead of exiting itself.
struct CliFailure: Equatable, Error {
    let message: String
    let exitCode: Int32
}

/// stdin, or the failure to report. Bounded because the server holds the whole request in memory.
func readStdin(limitLines: Int = 1000) -> Result<String, CliFailure> {
    guard hasStdin() else { return .success("") }
    var stdin = ""
    var index = 0
    while let line = readLine(strippingNewline: false) {
        stdin += line
        index += 1
        if index > limitLines {
            return .failure(CliFailure(message: "stdin number of lines limit is exceeded", exitCode: ExitCode.badArgs))
        }
    }
    return .success(stdin)
}

func run(_ socket: UnixSocketConnection, _ args: [String], stdin: String) -> Result<ServerAnswer, CliFailure> {
    guard let request = try? JSONEncoder().encode(ClientRequest(args: args, stdin: stdin)) else {
        return .failure(CliFailure(message: "Can't encode the request", exitCode: ExitCode.badArgs))
    }
    guard socket.sendMessage(request) else {
        return .failure(CliFailure(message: "Can't send request to AeroSpork server", exitCode: ExitCode.serverUnreachable))
    }
    guard let answer = try? socket.recvMessage() else {
        return .failure(CliFailure(message: "No response from AeroSpork server", exitCode: ExitCode.serverUnreachable))
    }
    guard let decoded = try? JSONDecoder().decode(ServerAnswer.self, from: answer) else {
        // This used to be `getOrDie()` -- a fatalError with a twenty-line "please report a bug"
        // dump. The realistic cause is a server built from different sources than the client, which
        // is the version mismatch we already warn about, not a defect worth a bug report.
        return .failure(CliFailure(
            message: """
                Can't decode the answer from AeroSpork server. The server is probably a different
                version than this client (client: \(cliClientVersionAndHash)).
                Restart AeroSpork.app -- a server restart is required after each update.
                """,
            exitCode: ExitCode.failure,
        ))
    }
    return .success(decoded)
}

@main
struct Main {
    /// A thin shell: turn an action into I/O and an exit code. Everything that decides anything
    /// lives in `plan` and `run`.
    static func main() {
        let args: [String] = Array(CommandLine.arguments.dropFirst())
        let action = plan(args: args)
        var stdin = ""
        switch action {
            case .usageError: printStderr(usage); exit(ExitCode.badArgs)
            case .usage: print(usage); exit(ExitCode.success)
            case .help(let help): print(help); exit(ExitCode.success)
            case .badArgs(let e): printStderr(e); exit(ExitCode.badArgs)
            // Before connecting: whatever feeds the pipe can take as long as it likes, and the server
            // hangs up on a connection that says nothing.
            case .send(_, readsStdin: true): stdin = readStdin().orExit()
            case .version, .send: break
        }

        let socketFile = "/tmp/\(aeroSporkAppId)-\(unixUserName).sock"
        guard let socket = UnixSocketConnection.connect(to: socketFile) else {
            if action == .version { printVersionAndExit(serverVersion: nil) }
            printStderr("Can't connect to AeroSpork server. Is AeroSpork.app running?")
            exit(ExitCode.serverUnreachable)
        }
        defer { socket.close() }

        // `--version` carries no subcommand, so the server is asked for nothing but its version.
        let ans = run(socket, action == .version ? [] : args, stdin: stdin).orExit()
        if action == .version { printVersionAndExit(serverVersion: ans.serverVersionAndHash) }

        if !ans.stdout.isEmpty { print(ans.stdout) }
        if !ans.stderr.isEmpty { printStderr(ans.stderr) }
        // Unconditional: a mismatched client that happens to succeed is exactly the case that
        // silently does the wrong thing, so it needs the warning most.
        if let warning = versionMismatchWarning(client: cliClientVersionAndHash, server: ans.serverVersionAndHash) {
            printStderr(warning)
        }
        exit(ans.exitCode)
    }
}

extension Result where Failure == CliFailure {
    fileprivate func orExit() -> Success {
        switch self {
            case .success(let value): return value
            case .failure(let f): printStderr(f.message); exit(f.exitCode)
        }
    }
}

func printVersionAndExit(serverVersion: String?) -> Never {
    print(
        """
        AeroSpork CLI client version: \(cliClientVersionAndHash)
        AeroSpork.app server version: \(serverVersion ?? "Unknown. The server is not running")
        """,
    )
    exit(ExitCode.success)
}
