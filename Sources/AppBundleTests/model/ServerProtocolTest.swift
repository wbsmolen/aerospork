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
