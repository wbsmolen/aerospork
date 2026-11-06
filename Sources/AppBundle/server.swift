import AppKit
import Common

/// The CLI reads stdin before it connects, then does exactly one request/response and closes, so
/// nothing legitimate is ever slow on the socket. Anything that is, is a stuck or hostile client
/// holding a thread hostage. Applies to each frame, in each direction.
private let clientFrameTimeoutSec = 30

func startUnixSocketServer(socketFile: String = "/tmp/\(aeroSporkAppId)-\(unixUserName).sock") {
    DispatchQueue.global().async {
        guard let listener = UnixSocketListener.bind(to: socketFile) else {
            // Not `die`. /tmp is world-writable and sticky, so another account can create this path
            // before us, and then we can neither remove it nor bind it. Dying here would let it stop
            // the window manager from starting, and everything but the CLI works without the socket.
            AppLog.server.fault("Can't bind CLI socket \(socketFile, privacy: .public) -- running without the AeroSpork CLI")
            return
        }
        AppLog.server.notice("CLI socket listening on \(socketFile, privacy: .public)")
        while true {
            guard let connection = listener.accept() else { continue }
            connection.setFrameTimeout(seconds: clientFrameTimeoutSec)
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

/// Runs a blocking socket call on `queue` and suspends until it returns.
///
/// Called directly it would block a thread of the cooperative pool, which is only as wide as the core
/// count and shared by every async task in the app: that many stuck clients stop all of them. A
/// private serial queue gets a thread of its own while it blocks; `DispatchQueue.global()` is another
/// limited pool.
private func blockingSocketCall<T: Sendable>(on queue: DispatchQueue, _ body: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        queue.async { continuation.resume(returning: body()) }
    }
}

/// Holds nothing while it waits on the client. The main actor is only taken to run the command, and
/// the reply is written after `runSession` has returned and left `sessionGate`, so a client that
/// stops reading delays itself and not the session queued behind it.
func newConnection(_ socket: UnixSocketConnection) async {
    let ioQueue = DispatchQueue(label: "\(aeroSporkAppId).cli-connection")
    func answerToClient(_ ans: ServerAnswer) async {
        guard let data = try? JSONEncoder().encode(ans) else { return }
        _ = await blockingSocketCall(on: ioQueue) { socket.sendMessage(data) }
    }
    defer {
        socket.close()
    }
    while true {
        let rawRequest: Data
        do {
            let result = await blockingSocketCall(on: ioQueue) { Result { try socket.recvMessage() } }
            guard let received = try result.get() else { return } // peer closed, or the frame timed out
            rawRequest = received
        } catch {
            // Framing is desynchronized after a rejected header, so answer once and hang up.
            await answerToClient(serverAnswer(ExitCode.badArgs, stderr: "Rejected request: \(error)"))
            return
        }
        if rawRequest.isEmpty {
            await answerToClient(serverAnswer(ExitCode.badArgs, stderr: "Empty request"))
            return
        }
        let _request = ClientRequest.decodeJson(rawRequest)
        guard let request: ClientRequest = _request.getOrNil() else {
            await answerToClient(serverAnswer(
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
            await answerToClient(serverAnswer(
                ExitCode.failure,
                stderr: "\(aeroSporkAppName) server is disabled and doesn't accept commands. " +
                    "Run 'aerospork enable on' to enable it",
            ))
            continue
        }
        if let ans = nonRunningAnswer(command: command, help: help, err: err) {
            await answerToClient(ans)
            continue
        }
        if let command {
            let _answer: Result<ServerAnswer, Error> = await Task { @MainActor in
                try await runSession(.socketServer, token) { () throws in
                    if !command.isQuery { WorkspaceMemory.stopRestoringLayouts() }
                    // `defaultEnv`, not the caller's AEROSPORK_ variables. A daemon launched from a callback
                    // inherits the AEROSPORK_WINDOW_ID of the window that fired it, so forwarding them would
                    // aim that daemon's later CLI calls at a window long gone.
                    let cmdResult = try await command.run(.defaultEnv, CmdStdin(request.stdin))
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
            await answerToClient(answer)
            continue
        }
        die("Unreachable")
    }
}
