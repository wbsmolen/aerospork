import AppKit
import Common

/// The CLI does exactly one request/response and closes, so nothing legitimate sits idle on the
/// socket. Anything that does is a stuck or hostile client holding a task hostage.
private let clientReadTimeoutSec = 30

func startUnixSocketServer() {
    DispatchQueue.global().async {
        let socketFile = "/tmp/\(aeroSporkAppId)-\(unixUserName).sock"
        guard let listener = UnixSocketListener.bind(to: socketFile) else {
            // Logged before dying: `die` shows a GUI dialog and exits, so without this the unified
            // log holds no record of the one failure that makes the whole CLI unusable.
            AppLog.server.fault("Can't bind CLI socket \(socketFile, privacy: .public) -- the AeroSpork CLI will not work")
            die("Can't listen to socket \(socketFile)")
        }
        AppLog.server.notice("CLI socket listening on \(socketFile, privacy: .public)")
        while true {
            guard let connection = listener.accept() else { continue }
            connection.setReadTimeout(seconds: clientReadTimeoutSec)
            Task { await newConnection(connection) }
        }
    }
}

/// The bundle id is the *debug* one in a debug build, but this talks to the release app, which
/// listens under the same id minus the `.debug` suffix (see Common/appMetadata.swift). Deriving it
/// keeps the two ids in sync instead of hardcoding a second literal that can rot.
var releaseServerSocketPath: String {
    check(isDebug && aeroSporkAppId.hasSuffix(".debug"))
    return "/tmp/\(aeroSporkAppId.dropLast(".debug".count))-\(unixUserName).sock"
}

func sendCommandToReleaseServer(args: [String]) {
    check(isDebug)
    guard let socket = UnixSocketConnection.connect(to: releaseServerSocketPath) else { return } // release server not running
    defer { socket.close() }
    guard let data = try? JSONEncoder().encode(ClientRequest(args: args, stdin: "")) else { return }
    socket.sendMessage(data)
    _ = try? socket.recvMessage()
}

private let serverVersionAndHash = "\(aeroSporkAppVersion) \(gitHash)"

func serverAnswer(_ exitCode: Int32, stdout: String = "", stderr: String = "") -> ServerAnswer {
    ServerAnswer(exitCode: exitCode, stdout: stdout, stderr: stderr, serverVersionAndHash: serverVersionAndHash)
}

/// The answers that need no window tree: help text, argument errors, and commands the socket
/// refuses. nil means the command has to actually run. Split out of `newConnection` so the
/// exit-code mapping is unit-testable without a live socket.
func nonRunningAnswer(command: (any Command)?, help: String?, err: String?) -> ServerAnswer? {
    if let help { return serverAnswer(ExitCode.success, stdout: help) }
    if let err { return serverAnswer(ExitCode.badArgs, stderr: err) }
    if command?.isExec == true { return serverAnswer(ExitCode.badArgs, stderr: "exec-and-forget is prohibited in CLI") }
    return nil
}

private func newConnection(_ socket: UnixSocketConnection) async {
    func answerToClient(_ ans: ServerAnswer) {
        if let data = try? JSONEncoder().encode(ans) { socket.sendMessage(data) }
    }
    defer {
        socket.close()
    }
    while true {
        let rawRequest: Data
        do {
            guard let received = try socket.recvMessage() else { return } // peer closed, or read timed out
            rawRequest = received
        } catch {
            // Framing is desynchronized after a rejected header, so answer once and hang up.
            answerToClient(serverAnswer(ExitCode.badArgs, stderr: "Rejected request: \(error)"))
            return
        }
        if rawRequest.isEmpty {
            answerToClient(serverAnswer(ExitCode.badArgs, stderr: "Empty request"))
            return
        }
        let _request = ClientRequest.decodeJson(rawRequest)
        guard let request: ClientRequest = _request.getOrNil() else {
            answerToClient(serverAnswer(
                ExitCode.badArgs,
                stderr: """
                    Can't parse request '\(String(describing: String(data: rawRequest, encoding: .utf8)).singleQuoted)'.
                    Error: \(_request.failureOrNil.prettyDescription)
                    """,
            ))
            continue
        }
        let (command, help, err) = parseCommand(request.args).unwrap()
        guard let token: RunSessionGuard = await .isServerEnabled(orIsEnableCommand: command) else {
            answerToClient(serverAnswer(
                ExitCode.failure,
                stderr: "\(aeroSporkAppName) server is disabled and doesn't accept commands. " +
                    "Run 'aerospork enable on' to enable it",
            ))
            continue
        }
        if let ans = nonRunningAnswer(command: command, help: help, err: err) {
            answerToClient(ans)
            continue
        }
        if let command {
            let _answer: Result<ServerAnswer, Error> = await Task { @MainActor in
                try await runSession(.socketServer, token) { () throws in
                    // Before doing the todo below: a daemon launched from a callback inherits the
                    // AEROSPORK_WINDOW_ID of the window that fired it, so forwarding the caller's
                    // environment would aim that daemon's later CLI calls at a window long gone.
                    let cmdResult = try await command.run(.defaultEnv, CmdStdin(request.stdin)) // todo pass AEROSPORK_ env vars from CLI instead of defaultEnv
                    return ServerAnswer(
                        exitCode: cmdResult.exitCode,
                        stdout: cmdResult.stdout.joined(separator: "\n"),
                        stderr: cmdResult.stderr.joined(separator: "\n"),
                        serverVersionAndHash: serverVersionAndHash,
                    )
                }
            }.result
            let answer = _answer.getOrNil() ??
                serverAnswer(ExitCode.failure, stderr: "Fail to await main thread. \(_answer.failureOrNil?.localizedDescription ?? "")")
            // Only failures, and only over the socket -- keybindings run in-process and never reach
            // here -- so this is bounded by how often the user's CLI actually breaks.
            if answer.exitCode != ExitCode.success {
                AppLog.server.error(
                    "'\(request.args.joined(separator: " "), privacy: .public)' exited \(answer.exitCode): \(answer.stderr, privacy: .public)",
                )
            }
            answerToClient(answer)
            continue
        }
        die("Unreachable")
    }
}
