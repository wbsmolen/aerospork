@testable import Cli
@testable import Common
import XCTest

/// `exec-and-forget` is config-only by design (see CmdArgsParsingTest), so it is neither parseable
/// nor listed in `--help`. Everything else must be both.
private let cliReachableCmdKinds = CmdKind.allCases.map(\.rawValue).filter { $0 != CmdKind.execAndForget.rawValue }

/// What can be asserted about `Sources/Cli` without running it.
final class CliSurfaceTest: XCTestCase {
    /// This is the C1 regression. `subcommandDescriptionsGenerated.swift` was literally
    /// `[["  *", ""]]` because `generate.sh` globbed `docs/aerospork-*.adoc` after those files had
    /// been deleted, and bash passes an unmatched glob through literally. `--help` listed no
    /// subcommands at all and nothing failed.
    func testEverySubcommandIsDescribedInHelp() {
        let described = Set(subcommandDescriptions.map { $0[0].trimmingCharacters(in: .whitespaces) })
        let missing = cliReachableCmdKinds.filter { !described.contains($0) }
        XCTAssertEqual(missing, [])
        // And the mirror: an orphan docs/aerospork-*.adoc page with no matching command would
        // list a nonexistent subcommand in --help and ship a man page for it, with nothing failing.
        let orphans = described.subtracting(cliReachableCmdKinds)
        XCTAssertEqual(orphans, [])
    }

    func testNoSubcommandDescriptionIsBlank() {
        XCTAssertEqual(subcommandDescriptions.filter { $0[1].trimmingCharacters(in: .whitespaces).isEmpty }, [])
    }

    /// The usage screen is built by `toPaddingTable`, so a description column that doesn't line up
    /// is a `toPaddingTable` bug, not a docs bug.
    func testUsageListsSubcommandsInAnAlignedTable() {
        XCTAssertTrue(usage.contains("SUBCOMMANDS:"))
        for kind in cliReachableCmdKinds {
            XCTAssertTrue(usage.contains(kind), "usage is missing \(kind)")
        }
    }

    func testPaddingTablePadsEveryColumnButTheLast() {
        let table = [["a", "x"], ["bbb", "y"]].toPaddingTable()
        XCTAssertEqual(table, ["a   | x", "bbb | y"])
    }

    /// Version negotiation. The CLI prints this unconditionally now; the old code only reached it
    /// when the command had already failed, so a mismatched client that *succeeded* -- the case
    /// that silently does the wrong thing -- was never warned about.
    func testVersionMismatchWarning() {
        XCTAssertNil(versionMismatchWarning(client: "1.0.0 abc", server: "1.0.0 abc"))
        let warning = versionMismatchWarning(client: "1.0.0 abc", server: "1.0.0 def")
        XCTAssertTrue(warning?.contains("1.0.0 abc") == true)
        XCTAssertTrue(warning?.contains("1.0.0 def") == true)
        XCTAssertTrue(warning?.contains("Restart") == true)
    }

    func testExitCodesAreDistinct() {
        let all = [ExitCode.success, ExitCode.failure, ExitCode.badArgs, ExitCode.serverUnreachable]
        XCTAssertEqual(Set(all).count, all.count)
    }

    // MARK: - Argument handling

    func testNoArgsIsAUsageError() {
        assertEquals(plan(args: []), .usageError)
    }

    /// `--help` on stdout with a zero exit, no arguments at all on stderr with a non-zero one. Same
    /// text, opposite outcomes, and `main()` used to be the only place that said so.
    func testHelpFlagsAskForUsage() {
        assertEquals(plan(args: ["-h"]), .usage)
        assertEquals(plan(args: ["--help"]), .usage)
        assertEquals(plan(args: ["--help", "list-windows"]), .usage)
    }

    func testVersionFlagsShortCircuitTheParser() {
        assertEquals(plan(args: ["-v"]), .version)
        assertEquals(plan(args: ["--version"]), .version)
    }

    /// The args are forwarded verbatim -- the client does not rewrite what the user typed.
    func testValidSubcommandIsSent() {
        assertEquals(plan(args: ["focus", "left"]), .send(["focus", "left"], readsStdin: false))
    }

    /// Only `next`/`prev` take a list from stdin. Anything else reading it swallows the input of the
    /// `while read` loop it runs in, and hangs if the pipe never closes.
    func testOnlyNextAndPrevReadStdin() {
        for args in [["workspace", "next"], ["workspace", "prev"], ["move-node-to-workspace", "next"], ["move-node-to-workspace", "prev"]] {
            assertEquals(plan(args: args), .send(args, readsStdin: true))
        }
        for args in [["workspace", "1"], ["move-node-to-workspace", "1"], ["list-windows", "--all"]] {
            assertEquals(plan(args: args), .send(args, readsStdin: false))
        }
    }

    func testSubcommandHelpIsPrintedLocally() {
        guard case .help(let text) = plan(args: ["focus", "--help"]) else {
            return XCTFail("expected .help, got \(plan(args: ["focus", "--help"]))")
        }
        XCTAssertTrue(text.contains("focus"), text)
    }

    func testUnknownSubcommandIsBadArgs() {
        guard case .badArgs = plan(args: ["no-such-command"]) else {
            return XCTFail("expected .badArgs, got \(plan(args: ["no-such-command"]))")
        }
    }

    /// `exec-and-forget` is config-only, so the CLI must refuse it rather than forward it.
    func testConfigOnlyCommandIsRejected() {
        guard case .badArgs = plan(args: ["exec-and-forget", "true"]) else {
            return XCTFail("exec-and-forget reached the server")
        }
    }
}

/// Error messages should say what to do next, not only what went wrong.
final class CliSuggestionTest: XCTestCase {
    private func failure(_ args: [String]) -> String {
        if case .failure(let e) = parseCmdArgs(args) { return e }
        return "<parsed successfully>"
    }

    /// The realistic typo: a plural, or one wrong letter.
    func testAMistypedSubcommandSuggestsTheRealOne() {
        let msg = failure(["workspaces"])
        XCTAssertTrue(msg.contains("workspace"), msg)
        XCTAssertTrue(msg.contains("--help"), "no next step offered: \(msg)")
    }

    func testASingleCharacterTypoIsCaught() {
        XCTAssertTrue(failure(["focu"]).contains("focus"), failure(["focu"]))
        XCTAssertTrue(failure(["lyout"]).contains("layout"), failure(["lyout"]))
    }

    /// Nonsense must NOT get a confident wrong guess -- proposing an unrelated command is worse
    /// than proposing nothing. The pointer to `--help` still has to be there.
    func testUnrelatedInputGetsNoBogusSuggestion() {
        let msg = failure(["zzzzzzzzzzzz"])
        XCTAssertFalse(msg.contains("Did you mean"), "guessed at nonsense: \(msg)")
        XCTAssertTrue(msg.contains("--help"), msg)
    }

    /// An unknown flag should list what the command *does* take: the user is already in the right
    /// command and only needs the spelling.
    func testAnUnknownFlagListsTheSupportedOnes() {
        let msg = failure(["list-workspaces", "--all", "--formatt", "%{workspace}"])
        XCTAssertTrue(msg.contains("--format"), msg)
    }

    func testEditDistanceIsSane() {
        XCTAssertEqual(editDistance("focus", "focus"), 0)
        XCTAssertEqual(editDistance("focu", "focus"), 1)
        XCTAssertEqual(editDistance("", "abc"), 3)
        XCTAssertEqual(editDistance("kitten", "sitting"), 3) // the textbook case
    }
}

/// A command that exists but only in the config file.
final class ConfigOnlyCommandTest: XCTestCase {
    private func failure(_ args: [String]) -> String {
        if case .failure(let e) = parseCmdArgs(args) { return e }
        return "<parsed successfully>"
    }

    /// `exec-and-forget` has a man page and a documented synopsis, but is never registered as a CLI
    /// subcommand -- it is parsed by the config reader. A user following the docs used to get
    /// "Unrecognized subcommand", which is true and tells them nothing.
    func testAConfigOnlyCommandSaysWhereItBelongs() {
        let msg = failure(["exec-and-forget", "echo hi"])
        XCTAssertFalse(msg.contains("Unrecognized"), msg)
        XCTAssertTrue(msg.contains("config file"), msg)
        XCTAssertTrue(msg.contains("binding"), "no example of correct use: \(msg)")
    }

    /// ...and a genuinely unknown name still takes the normal path.
    func testAnUnknownNameIsStillUnrecognized() {
        XCTAssertTrue(failure(["definitely-not-a-command"]).contains("Unrecognized"), failure(["definitely-not-a-command"]))
    }

    /// Every `CmdKind` is either a CLI subcommand or gets the config-only message -- no third
    /// category where the user is told nothing useful.
    func testEveryCommandKindIsAccountedFor() {
        for kind in CmdKind.allCases where subcommandParsers[kind.rawValue] == nil {
            let msg = failure([kind.rawValue])
            XCTAssertTrue(msg.contains("config file"), "\(kind.rawValue) is neither a CLI command nor explained: \(msg)")
        }
    }
}
