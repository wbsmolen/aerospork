@testable import Common
import XCTest

/// `parseCmdArgs` runs in *both* processes: the CLI validates before it opens a socket, and the
/// server re-parses what arrives. Everything here is pure -- no window tree, no AX, no monitors.
final class CmdArgsParsingTest: XCTestCase {
    func testEmptyInputIsRejected() {
        assertFailure(parseCmdArgs([]), "Can't parse empty string command")
        assertFailure(parseCmdArgs([""]), "Can't parse empty string command")
    }

    /// Asserts the contract, not the exact sentence: the name is echoed back and the user is told
    /// where to look next. Pinning the literal string made a *better* message a test failure, which
    /// is the wrong incentive -- `CliSuggestionTest` covers the suggestion behaviour itself.
    func testUnknownSubcommandIsRejected() {
        guard case .failure(let msg) = parseCmdArgs(["no-such-command"]) else {
            return XCTFail("expected a failure")
        }
        XCTAssertTrue(msg.contains("Unrecognized subcommand 'no-such-command'"), msg)
        XCTAssertTrue(msg.contains("--help"), "no next step offered: \(msg)")
    }

    /// Structural: a `CmdKind` added to the manifest enum without a parser entry is a subcommand
    /// that documents itself, appears in help, and then fails at the prompt.
    func testEveryCmdKindHasAParser() {
        let missing = CmdKind.allCases.map(\.rawValue).filter { subcommandParsers[$0] == nil }
        assertEquals(missing, [CmdKind.execAndForget.rawValue])
    }

    /// `exec-and-forget` is deliberately the one exception: it is config-only, and its "argument" is
    /// a whole bash script that the generic tokenizer must never see. Reaching it over the socket is
    /// answered with `badArgs`, so the absent parser is the enforcement, not an oversight.
    ///
    /// Asserts the contract, not the exact sentence: the message must not claim the command does not
    /// exist -- it does, in the config -- and must point at where it belongs. `ConfigOnlyCommandTest`
    /// covers the wording.
    func testExecAndForgetIsNotReachableFromTheCli() {
        guard case .failure(let msg) = parseCmdArgs(["exec-and-forget", "echo", "hi"]) else {
            return XCTFail("exec-and-forget must not parse as a CLI subcommand")
        }
        XCTAssertFalse(msg.contains("Unrecognized"), msg)
        XCTAssertTrue(msg.contains("config file"), msg)
    }

    func testHelpFlagShortCircuitsBeforeValidation() {
        // `-h` wins even though the mandatory argument is absent, otherwise `--help` is unusable
        // exactly when the user most needs it.
        assertTrue(parseCmdArgs(["workspace", "-h"]).isHelp)
        assertTrue(parseCmdArgs(["workspace", "--help"]).isHelp)
    }

    func testMandatoryArgumentIsReported() {
        assertFailure(parseCmdArgs(["workspace"]), "ERROR: Argument '(<workspace>|next|prev)' is mandatory")
    }

    /// The flag is named back, and the command's real flags are listed -- pinning the exact string
    /// made a more helpful message a test failure.
    func testUnknownFlagIsReported() {
        guard case .failure(let msg) = parseCmdArgs(["list-workspaces", "--nope"]) else {
            return XCTFail("expected a failure")
        }
        XCTAssertTrue(msg.contains("Unknown flag '--nope'"), msg)
        XCTAssertTrue(msg.contains("Supported flags:"), "no recovery hint: \(msg)")
    }

    func testDuplicatedOptionIsReported() {
        assertFailure(parseCmdArgs(["list-workspaces", "--all", "--all"]), "ERROR: Duplicated option '--all'")
    }

    func testConflictingOptionsAreReported() {
        assertFailure(parseCmdArgs(["list-workspaces", "--all", "--focused"]), "ERROR: Conflicting options: --all, --focused")
        assertFailure(parseCmdArgs(["list-workspaces", "--count", "--json"]), "ERROR: Conflicting options: --count, --json")
    }

    /// Only the *first* conflicting set is reported (`break` in `parseSpecificCmdArgs`). Pinned so
    /// the message stays one line rather than a wall of overlapping complaints.
    func testOnlyTheFirstConflictIsReported() {
        let failure = errorOrNil(parseCmdArgs(["list-workspaces", "--all", "--focused", "--count", "--json"]))
        assertEquals(failure?.split(separator: "\n").count, 1)
    }

    /// `boolFlag` consumes a following literal `no`. Without that, `--empty no` parses as
    /// "--empty true" plus a stray positional argument, i.e. the inverse of what was asked.
    func testBoolFlagConsumesExplicitNo() {
        assertEquals(parse(["list-workspaces", "--monitor", "all", "--empty", "no"], as: ListWorkspacesCmdArgs.self)?.filteringOptions.empty, false)
        assertEquals(parse(["list-workspaces", "--monitor", "all", "--empty"], as: ListWorkspacesCmdArgs.self)?.filteringOptions.empty, true)
    }

    /// Validation that runs *after* the generic tokenizer, in `parseListWorkspacesCmdArgs`.
    func testPostParseValidationAndAliasExpansion() {
        assertFailure(parseCmdArgs(["list-workspaces"]), "Mandatory option is not specified (--all|--focused|--monitor)")
        assertFailure(parseCmdArgs(["list-workspaces", "--all", "--empty"]), "--all conflicts with any other \"filtering\" options")
        // `--all` is an alias, expanded away before the command ever runs.
        let all = parse(["list-workspaces", "--all"], as: ListWorkspacesCmdArgs.self)
        assertEquals(all?.filteringOptions.onMonitors, [.all])
    }

    /// Negative numbers must survive the "starts with -" flag test, or `resize smart -50` becomes
    /// "unknown flag".
    func testResizeAcceptsNegativeUnits() {
        assertNotNil(parse(["resize", "smart", "-50"], as: ResizeCmdArgs.self))
    }

    func testSingleValueOptionReportsAMissingValue() {
        assertFailure(parseCmdArgs(["list-workspaces", "--monitor", "all", "--format"]), "ERROR: <output-format> is mandatory")
    }
}

// MARK: helpers

private func parse<T: CmdArgs>(_ args: [String], as: T.Type) -> T? {
    if case .cmd(let cmd) = parseCmdArgs(args) { return cmd as? T }
    return nil
}

private func errorOrNil(_ parsed: ParsedCmd<some Any>) -> String? {
    if case .failure(let e) = parsed { return e }
    return nil
}

extension ParsedCmd {
    fileprivate var isHelp: Bool {
        if case .help = self { return true }
        return false
    }
}

private func assertFailure(_ parsed: ParsedCmd<some Any>, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
    switch parsed {
        case .failure(let actual): XCTAssertEqual(actual, expected, file: file, line: line)
        case .cmd(let cmd): XCTFail("Expected failure, got \(cmd)", file: file, line: line)
        case .help: XCTFail("Expected failure, got help", file: file, line: line)
    }
}

func assertEquals<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(actual, expected, file: file, line: line)
}

func assertTrue(_ actual: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(actual, file: file, line: line)
}

func assertNotNil(_ actual: Any?, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNotNil(actual, file: file, line: line)
}
