import Common
import Darwin
import Foundation

let usage =
    """
    USAGE: \(CommandLine.arguments.first ?? "aerospork") [-h|--help] [-v|--version] <subcommand> [<args>...]

    SUBCOMMANDS:
    \(subcommandDescriptions.sortedBy { $0[0] }.toPaddingTable(columnSeparator: "   ").joined(separator: "\n"))
    """

@main
struct Main {
    static func main() {
        let args: [String] = Array(CommandLine.arguments.dropFirst())

        if args.isEmpty {
            printStderr(usage)
            exit(1)
        }
        if args.first == "--help" || args.first == "-h" {
            print(usage)
            exit(0)
        }

        let isVersion: Bool = args.first == "--version" || args.first == "-v"

        if !isVersion {
            switch parseCmdArgs(args) {
                case .cmd:
                    break
                case .help(let help):
                    print(help)
                    exit(0)
                case .failure(let e):
                    cliError(e)
            }
        }

        let socketFile = "/tmp/\(aeroSpaceAppId)-\(unixUserName).sock"

        guard let socket = UnixSocketConnection.connect(to: socketFile) else {
            if isVersion {
                printVersionAndExit(serverVersion: nil)
            }
            cliError("Can't connect to aerospork server. Is aerospork.app running?")
        }
        defer {
            socket.close()
        }

        var stdin = ""
        if hasStdin() {
            var index = 0
            while let line = readLine(strippingNewline: false) {
                stdin += line
                index += 1
                if index > 1000 {
                    cliError("stdin number of lines limit is exceeded")
                }
            }
        }

        let ans = isVersion ? run(socket, [], stdin: stdin) : run(socket, args, stdin: stdin)
        if isVersion {
            printVersionAndExit(serverVersion: ans.serverVersionAndHash)
        }

        if !ans.stdout.isEmpty { print(ans.stdout) }
        if !ans.stderr.isEmpty { printStderr(ans.stderr) }
        if ans.exitCode != 0 && ans.serverVersionAndHash != cliClientVersionAndHash {
            printStderr(
                """
                Warning: aerospork client/server versions don't match
                    - aerospork CLI client version: \(cliClientVersionAndHash)
                    - aerospork.app server version: \(ans.serverVersionAndHash)
                    Possible fixes:
                    - Restart aerospork.app (server restart is required after each update)
                    - Reinstall and restart aerospork (corrupted installation)
                """,
            )
        }
        exit(ans.exitCode)
    }
}

func printVersionAndExit(serverVersion: String?) -> Never {
    print(
        """
        aerospork CLI client version: \(cliClientVersionAndHash)
        aerospork.app server version: \(serverVersion ?? "Unknown. The server is not running")
        """,
    )
    exit(0)
}

func run(_ socket: UnixSocketConnection, _ args: [String], stdin: String) -> ServerAnswer {
    let request = Result { try JSONEncoder().encode(ClientRequest(args: args, stdin: stdin)) }.getOrDie()
    guard socket.sendMessage(request) else { cliError("Can't send request to aerospork server") }
    guard let answer = socket.recvMessage() else { cliError("No response from aerospork server") }
    return Result { try JSONDecoder().decode(ServerAnswer.self, from: answer) }.getOrDie()
}
