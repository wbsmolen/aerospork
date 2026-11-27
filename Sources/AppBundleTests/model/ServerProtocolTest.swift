@testable import AppBundle
import Common
import XCTest

@MainActor
final class ServerProtocolTest: XCTestCase {
    private func answer(_ command: String) -> ServerAnswer? {
        let (cmd, help, err) = parseCommand(command).unwrap()
        return nonRunningAnswer(command: cmd, help: help, err: err)
    }

    func testExitCodesAreDistinct() {
        let all = [ExitCode.success, ExitCode.failure, ExitCode.badArgs, ExitCode.serverUnreachable]
        assertEquals(Set(all).count, all.count)
    }

    func testMalformedArgsGetBadArgs() {
        assertEquals(answer("list-workspaces --all --focused")?.exitCode, ExitCode.badArgs)
        assertEquals(answer("no-such-subcommand")?.exitCode, ExitCode.badArgs)
    }

    /// The socket sends an args array, and the args parser does not register `exec-and-forget`, so it
    /// fails to parse before `nonRunningAnswer` ever sees a command.
    func testExecOverSocketGetsBadArgs() {
        let (cmd, help, err) = parseCommand(["exec-and-forget", "echo", "hi"]).unwrap()
        assertNil(cmd)
        assertEquals(nonRunningAnswer(command: cmd, help: help, err: err)?.exitCode, ExitCode.badArgs)
    }

    /// Only the string parser, which the config uses, builds an `ExecAndForgetCommand`. The socket never
    /// reaches this refusal; it is defence in depth in case a later path hands one over.
    func testAnExecCommandIsStillRefusedIfOneReachesTheServer() {
        assertEquals(answer("exec-and-forget echo hi")?.exitCode, ExitCode.badArgs)
    }

    /// A status bar polling a failing query wrote one always-on record per poll.
    func testOnlyTheFirstOfARunOfIdenticalFailuresIsLogged() {
        let empty = CliFailureKey(args: ["list-windows", "--focused"], exitCode: ExitCode.failure, stderr: "No window is focused")
        assertTrue(shouldLogCliFailure(empty, last: nil))
        assertFalse(shouldLogCliFailure(empty, last: empty))
        let other = CliFailureKey(args: empty.args, exitCode: empty.exitCode, stderr: "Something else")
        assertTrue(shouldLogCliFailure(other, last: empty))
        assertTrue(shouldLogCliFailure(empty, last: nil)) // a success in between clears `last`
    }

    func testHelpSucceeds() {
        let ans = answer("list-workspaces --help")
        assertEquals(ans?.exitCode, ExitCode.success)
        assertTrue(!(ans?.stdout ?? "").isEmpty)
    }

    func testRunnableCommandIsNotAnsweredEarly() {
        assertNil(answer("list-workspaces --all"))
    }

    func testVersionMismatchIsReportedRegardlessOfSuccess() {
        assertNil(versionMismatchWarning(client: "1.0 abc", server: "1.0 abc"))
        let warning = versionMismatchWarning(client: "1.0 abc", server: "1.1 def")
        assertNotNil(warning)
        assertTrue(warning?.contains("1.1 def") == true)
    }

    func testReleaseSocketPathUsesThisProjectsBundleId() {
        // The fork inherited the upstream project's bundle id in this socket name.
        assertEquals(releaseServerSocketPath, "/tmp/com.wbs.aerospork-\(unixUserName).sock")
    }

    /// The whole request used to come back, wrapped as `Optional("...")`, so a malformed request near the
    /// frame limit made an answer over it.
    func testAMalformedRequestIsEchoedShortAndUnwrapped() async throws {
        var fds: [Int32] = [0, 0]
        check(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        let (client, server) = (UnixSocketConnection(fd: fds[0]), UnixSocketConnection(fd: fds[1]))
        defer { client.close() }
        client.setFrameTimeout(seconds: 5)
        Task.detached { await newConnection(server) }

        client.sendMessage(Data(String(repeating: "x", count: 100_000).utf8))
        let reply = try await Task.detached { try client.recvMessage() }.value

        let answer = try JSONDecoder().decode(ServerAnswer.self, from: try XCTUnwrap(reply))
        assertEquals(answer.exitCode, ExitCode.badArgs)
        XCTAssertTrue(answer.stderr.hasPrefix("Can't parse request '\(String(repeating: "x", count: 200))'.\n"), answer.stderr)
    }

    // MARK: - subscribe

    private func subscribe(_ args: [String], frameTimeout: Duration = .seconds(5)) async throws -> (UnixSocketConnection, ServerAnswer?) {
        let client = serverConnectionForTests(frameTimeout: frameTimeout)
        try sendRequest(client, ["subscribe"] + args)
        return (client, try await nextAnswer(client))
    }

    private func tearDownSubscribers() {
        EventBroadcaster.shared.removeAll(sending: serverAnswer(ExitCode.failure))
        TrayMenuModel.shared.isEnabled = true
    }

    func testSubscribeGetsTheSnapshotThenEvents() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        defer { tearDownSubscribers() }
        let (client, snapshot) = try await subscribe(["mode-changed"])
        assertEquals(snapshot?.exitCode, ExitCode.success)
        assertEquals(eventJson(snapshot)["event"] as? String, "snapshot")
        assertEquals(eventJson(snapshot)["version"] as? Int, 1)
        assertEquals(eventJson(snapshot)["focused-workspace"] as? String, focus.workspace.name)

        EventBroadcaster.shared.emit(.modeChanged, ["mode": .string("resize"), "prev-mode": .string("main")])
        let event = eventJson(try await nextAnswer(client))
        assertEquals(event["event"] as? String, "mode-changed")
        assertEquals(event["mode"] as? String, "resize")
        assertEquals(event["version"] as? Int, 1)

        client.close()
        try await waitUntil { EventBroadcaster.shared.subscribers.isEmpty } // the server saw the hang-up
    }

    /// A client that stops reading is dropped once its queue is full. It must not slow the other subscriber,
    /// or the commands on other connections.
    func testAClientThatStopsReadingIsDroppedAndOthersAreNot() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        defer { tearDownSubscribers() }
        let (stuck, _) = try await subscribe(["mode-changed"], frameTimeout: .seconds(30))
        defer { stuck.close() }
        let (reader, _) = try await subscribe(["mode-changed"])
        defer { reader.close() }
        let batches = 20
        let perBatch = 50
        let read = Task.detached {
            var count = 0
            while count < batches * perBatch, (try? reader.recvMessage()) != nil { count += 1 }
            return count
        }

        // In batches, as events come: a burst of more than the queue holds would drop a reader too.
        for _ in 0 ..< batches {
            for _ in 0 ..< perBatch { EventBroadcaster.shared.emit(.modeChanged, ["mode": .string(String(repeating: "m", count: 100))]) }
            try await Task.sleep(for: .milliseconds(20))
        }
        assertEquals(await read.value, batches * perBatch)
        assertEquals(EventBroadcaster.shared.subscribers.count, 1)

        let other = serverConnectionForTests()
        defer { other.close() }
        try sendRequest(other, ["no-such-command"])
        assertEquals(try await nextAnswer(other)?.exitCode, ExitCode.badArgs)
    }

    func testADisabledServerRefusesSubscribe() async throws {
        TrayMenuModel.shared.isEnabled = false
        defer { tearDownSubscribers() }
        let (client, answer) = try await subscribe(["--all"])
        defer { client.close() }
        assertEquals(answer?.exitCode, ExitCode.failure)
        assertEquals(answer?.stderr, serverDisabledMessage)
        assertTrue(EventBroadcaster.shared.subscribers.isEmpty)
    }

    /// A disabled server answers nothing but `enable`, so its streams end with the reason, instead of going quiet.
    func testEnableOffEndsEveryStream() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        defer {
            tearDownSubscribers()
            activateMode(mainModeId)
        }
        let (client, _) = try await subscribe(["--all"])
        defer { client.close() }

        let io = CmdIo(stdin: .emptyStdin)
        assertTrue(try await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .off)).run(.defaultEnv, io))

        let last = try await nextAnswer(client)
        assertEquals(last?.exitCode, ExitCode.failure)
        XCTAssertTrue(last?.stderr.contains("disabled") == true, last?.stderr ?? "")
        assertNil(try await nextAnswer(client)) // and the server hung up
        assertTrue(EventBroadcaster.shared.subscribers.isEmpty)
    }

    /// A release server that is running but wedged: it takes the connection into its backlog and never
    /// answers. Without a frame timeout the debug build hangs at launch and at quit.
    func testTalkingToAWedgedReleaseServerGivesUp() throws {
        let path = "/tmp/aerospork-test-\(getpid())-\(UInt32.random(in: 0 ... .max)).sock"
        let listener = try XCTUnwrap(UnixSocketListener.bind(to: path))
        defer { listener.close(); unlink(path) }
        let gaveUp = expectation(description: "sendCommandToReleaseServer returned")
        Thread.detachNewThread {
            sendCommandToReleaseServer(args: ["enable", "off"], socketPath: path, timeout: .milliseconds(200))
            gaveUp.fulfill()
        }
        wait(for: [gaveUp], timeout: 3)
    }
}
