@testable import AppBundle
import Common
import Darwin
import Foundation
import XCTest

@MainActor
final class CliConnectionTest: XCTestCase {
    private func connectedPair() -> (client: UnixSocketConnection, server: UnixSocketConnection) {
        var fds: [Int32] = [0, 0]
        check(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        return (UnixSocketConnection(fd: fds[0]), UnixSocketConnection(fd: fds[1]))
    }

    /// The cooperative pool is as wide as the core count, and every async task in the app shares it.
    /// One stuck client per thread used to stop all of them, the tree's included, until the clients
    /// timed out.
    func testSilentClientsDoNotPinTheCooperativePool() async throws {
        var clients: [UnixSocketConnection] = []
        for _ in 0 ..< ProcessInfo.processInfo.activeProcessorCount * 2 {
            let (client, server) = connectedPair()
            clients.append(client)
            server.setFrameTimeout(seconds: 3)
            Task.detached { await newConnection(server) }
        }
        defer { clients.forEach { $0.close() } }
        try await Task.sleep(for: .milliseconds(200)) // long enough for each to reach its blocking read

        let start = ContinuousClock.now
        await Task.detached {}.value // cannot start without a free cooperative thread
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
    }

    func testARequestIsAnsweredOverItsConnection() async throws {
        TrayMenuModel.shared.isEnabled = true
        let (client, server) = connectedPair()
        defer { client.close() }
        client.setFrameTimeout(seconds: 5)
        Task.detached { await newConnection(server) }

        client.sendMessage(try JSONEncoder().encode(ClientRequest(args: ["no-such-command"], stdin: "")))
        // Off the main actor, which the connection has to reach before it can answer.
        let reply = try await Task.detached { try client.recvMessage() }.value

        let answer = try JSONDecoder().decode(ServerAnswer.self, from: try XCTUnwrap(reply))
        assertEquals(answer.exitCode, ExitCode.badArgs)
    }

    /// A subscriber is quiet for as long as nothing happens. The frame timeout, which ends any other connection
    /// that stays silent, must not end its stream.
    func testAnIdleSubscriberOutlivesTheFrameTimeout() async throws {
        setUpWorkspacesForTests()
        TrayMenuModel.shared.isEnabled = true
        defer { EventBroadcaster.shared.removeAll(sending: serverAnswer(ExitCode.failure)) }
        let client = serverConnectionForTests(frameTimeout: .milliseconds(300))
        defer { client.close() }
        try sendRequest(client, ["subscribe", "mode-changed"])
        assertEquals(eventJson(try await nextAnswer(client))["event"] as? String, "snapshot")

        try await Task.sleep(for: .seconds(1))
        EventBroadcaster.shared.emit(.modeChanged, ["mode": .string("resize"), "prev-mode": .string("main")])
        assertEquals(eventJson(try await nextAnswer(client))["event"] as? String, "mode-changed")
    }

    /// `sendMessage` refuses a frame over the limit, so an oversize answer used to reach the client as
    /// silence: "No response from AeroSpork server".
    func testAnOversizeAnswerBecomesAFailureThatSaysSo() throws {
        // Decoded, not compared as bytes: JSONEncoder's key order changes from one run to the next.
        let small = try JSONDecoder().decode(ServerAnswer.self, from: try XCTUnwrap(encodedAnswer(serverAnswer(ExitCode.success, stdout: "ok"))))
        assertEquals(small.exitCode, ExitCode.success)
        assertEquals(small.stdout, "ok")

        let huge = serverAnswer(ExitCode.success, stdout: String(repeating: "x", count: Int(UnixSocketConnection.maxFrameSize)))
        let data = try XCTUnwrap(encodedAnswer(huge))
        XCTAssertLessThan(data.count, 1000)
        let answer = try JSONDecoder().decode(ServerAnswer.self, from: data)
        assertEquals(answer.exitCode, ExitCode.failure)
        XCTAssertTrue(answer.stderr.contains("too large"), answer.stderr)
    }

    /// `main()` exits, so its order can only be read. Whatever feeds the pipe can take as long as it
    /// likes, and the server hangs up on a connection that says nothing.
    func testTheCliReadsStdinBeforeItConnects() throws {
        let source = try String(contentsOf: projectRoot.appending(path: "Sources/Cli/_main.swift"), encoding: .utf8)
        let read = try XCTUnwrap(source.range(of: "readStdin().orExit()"))
        let connect = try XCTUnwrap(source.range(of: "UnixSocketConnection.connect(to:"))
        XCTAssertLessThan(read.lowerBound, connect.lowerBound)
    }

    /// Nothing else fills a stdin the CLI no longer sends, so a new reader here would silently see an
    /// empty list. It has to be added to `readsStdin` in `Cli/_main.swift` as well.
    func testOnlyTheCommandsTheCliSendsStdinForReadIt() throws {
        let impl = projectRoot.appending(path: "Sources/AppBundle/command/impl")
        let readers = try FileManager.default.contentsOfDirectory(at: impl, includingPropertiesForKeys: nil)
            .filter { try String(contentsOf: $0, encoding: .utf8).contains("io.readStdin()") }
            .map(\.lastPathComponent)
            .sorted()
        assertEquals(readers, ["MoveNodeToWorkspaceCommand.swift", "WorkspaceCommand.swift"])
    }
}
