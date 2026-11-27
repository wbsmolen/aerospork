@testable import AppBundle
import Common
import XCTest

@MainActor
final class ListModesTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParseListModesCommand() {
        testParseCommandSucc("list-modes", ListModesCmdArgs(rawArgs: []))
        testParseCommandSucc("list-modes --current", ListModesCmdArgs(rawArgs: []).copy(\.current, true))
        testParseCommandSucc("list-modes --json", ListModesCmdArgs(rawArgs: []).copy(\.json, true))
        testParseCommandSucc("list-modes --current --json", ListModesCmdArgs(rawArgs: []).copy(\.current, true).copy(\.json, true))
    }

    func testJsonIsAnArrayOfTheModeNames() async throws {
        config.modes["resize"] = .zero
        defer { config.modes["resize"] = nil }
        let plain = try await parseCommand("list-modes").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let json = try await parseCommand("list-modes --json").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(json.exitCode, 0)
        let names = try JSONDecoder().decode([String].self, from: Data(json.stdout.joined().utf8))
        assertEquals(Set(names), Set(plain.stdout))
        XCTAssertTrue(names.contains("resize"))
    }

    func testCurrentJsonIsAnArrayOfOne() async throws {
        let json = try await parseCommand("list-modes --current --json").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try JSONDecoder().decode([String].self, from: Data(json.stdout.joined().utf8)), [activeMode ?? mainModeId])
    }
}
