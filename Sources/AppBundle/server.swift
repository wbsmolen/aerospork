import AppKit
import Common

func startUnixSocketServer() {
    DispatchQueue.global().async {
        let socketFile = "/tmp/\(aeroSpaceAppId)-\(unixUserName).sock"
        guard let listener = UnixSocketListener.bind(to: socketFile) else {
            die("Can't listen to socket \(socketFile)")
        }
        while true {
            guard let connection = listener.accept() else { continue }
            Task { await newConnection(connection) }
        }
    }
}

func sendCommandToReleaseServer(args: [String]) {
    check(isDebug)
    let socketFile = "/tmp/bobko.aerospace-\(unixUserName).sock"
    guard let socket = UnixSocketConnection.connect(to: socketFile) else { return } // release server not running
    defer { socket.close() }
    guard let data = try? JSONEncoder().encode(ClientRequest(args: args, stdin: "")) else { return }
    socket.sendMessage(data)
    _ = socket.recvMessage()
}

private let serverVersionAndHash = "\(aeroSpaceAppVersion) \(gitHash)"

private func newConnection(_ socket: UnixSocketConnection) async { // todo add exit codes
    func answerToClient(exitCode: Int32, stdout: String = "", stderr: String = "") {
        let ans = ServerAnswer(exitCode: exitCode, stdout: stdout, stderr: stderr, serverVersionAndHash: serverVersionAndHash)
        answerToClient(ans)
    }
    func answerToClient(_ ans: ServerAnswer) {
        if let data = try? JSONEncoder().encode(ans) { socket.sendMessage(data) }
    }
    defer {
        socket.close()
    }
    while true {
        guard let rawRequest = socket.recvMessage() else { return } // peer closed the connection
        if rawRequest.isEmpty {
            answerToClient(exitCode: 1, stderr: "Empty request")
            return
        }
        let _request = ClientRequest.decodeJson(rawRequest)
        guard let request: ClientRequest = _request.getOrNil() else {
            answerToClient(
                exitCode: 1,
                stderr: """
                    Can't parse request '\(String(describing: String(data: rawRequest, encoding: .utf8)).singleQuoted)'.
                    Error: \(_request.failureOrNil.prettyDescription)
                    """,
            )
            continue
        }
        let (command, help, err) = parseCommand(request.args).unwrap()
        guard let token: RunSessionGuard = await .isServerEnabled(orIsEnableCommand: command) else {
            answerToClient(
                exitCode: 1,
                stderr: "\(aeroSpaceAppName) server is disabled and doesn't accept commands. " +
                    "You can use 'aerospace enable on' to enable the server",
            )
            continue
        }
        if let help {
            answerToClient(exitCode: 0, stdout: help)
            continue
        }
        if let err {
            answerToClient(exitCode: 1, stderr: err)
            continue
        }
        if command?.isExec == true {
            answerToClient(exitCode: 1, stderr: "exec-and-forget is prohibited in CLI")
            continue
        }
        if let command {
            let _answer: Result<ServerAnswer, Error> = await Task { @MainActor in
                try await runSession(.socketServer, token) { () throws in
                    let cmdResult = try await command.run(.defaultEnv, CmdStdin(request.stdin)) // todo pass AEROSPACE_ env vars from CLI instead of defaultEnv
                    return ServerAnswer(
                        exitCode: cmdResult.exitCode,
                        stdout: cmdResult.stdout.joined(separator: "\n"),
                        stderr: cmdResult.stderr.joined(separator: "\n"),
                        serverVersionAndHash: serverVersionAndHash,
                    )
                }
            }.result
            let answer = _answer.getOrNil() ??
                ServerAnswer(
                    exitCode: 1,
                    stderr: "Fail to await main thread. \(_answer.failureOrNil?.localizedDescription ?? "")",
                    serverVersionAndHash: serverVersionAndHash,
                )
            answerToClient(answer)
            continue
        }
        die("Unreachable")
    }
}
