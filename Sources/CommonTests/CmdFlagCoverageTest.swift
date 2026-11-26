@testable import Common
import Foundation
import XCTest

/// Every flag the parser accepts is in the command's synopsis (its `--help`) and in its shell
/// completion grammar. `ShellCompletionGrammarTest` checks only command names; two flags once went
/// missing from completion while the parser took them.
final class CmdFlagCoverageTest: XCTestCase {
    /// Flags left out of a synopsis or the grammar on purpose: command, flag, where it is missing.
    /// An entry that no longer matches a gap fails, so the list cannot go stale.
    private let deliberatelyUndocumented: Set<Gap> = []

    func testEveryParserFlagIsInTheSynopsisAndTheGrammar() throws {
        let grammar = try grammarText()
        var gaps: Set<Gap> = []
        var checked = 0
        for kind in CmdKind.allCases where kind != .execAndForget {
            let parser = try XCTUnwrap(subcommandParsers[kind.rawValue], kind.rawValue)
            let helpTokens = tokens(parser.info.help)
            let grammarTokens = tokens(completionText(of: kind.rawValue, in: grammar))
            XCTAssertFalse(grammarTokens.isEmpty, "no grammar alternative for \(kind.rawValue)")
            for flag in parser.optionNames {
                checked += 1
                if !helpTokens.contains(flag) { gaps.insert(Gap(kind.rawValue, flag, "synopsis")) }
                if !grammarTokens.contains(flag) { gaps.insert(Gap(kind.rawValue, flag, "grammar")) }
            }
        }
        XCTAssertGreaterThan(checked, 50, "the parsers' options were not actually read")
        XCTAssertEqual(gaps.subtracting(deliberatelyUndocumented).sorted(), [], "parser flags missing from docs or completion")
        XCTAssertEqual(deliberatelyUndocumented.subtracting(gaps).sorted(), [], "stale allowlist entries")
    }

    /// The command's alternatives in `<subcommand>`, plus the bodies of the `<x>` nonterminals they
    /// name, one level deep.
    private func completionText(of command: String, in grammar: String) -> String {
        let alternatives: [String] = grammar.split(separator: "\n").compactMap { line in
            var alternative: String = line.trimmingCharacters(in: .whitespaces)
            if alternative.hasPrefix("| ") { alternative.removeFirst(2) }
            return alternative.split(separator: " ").first == Substring(command) ? alternative : nil
        }
        var bodies: [String: String] = [:]
        for match in grammar.matches(of: /<([a-z0-9_]+)> ::=([^;]*);/) {
            bodies[String(match.1)] = String(match.2)
        }
        let referenced = alternatives.flatMap { $0.matches(of: /<([a-z0-9_]+)>/).map { String($0.1) } }
        return (alternatives + referenced.compactMap { bodies[$0] }).joined(separator: "\n")
    }

    private func tokens(_ text: String) -> Set<String> {
        Set(text.split { !($0.isLetter || $0.isNumber || $0 == "-") }.map(String.init))
    }
}

private struct Gap: Hashable, Comparable, CustomStringConvertible {
    let command: String
    let flag: String
    let missingFrom: String
    init(_ command: String, _ flag: String, _ missingFrom: String) {
        self.command = command
        self.flag = flag
        self.missingFrom = missingFrom
    }

    var description: String { "\(command) \(flag) (not in \(missingFrom))" }
    static func < (a: Gap, b: Gap) -> Bool { a.description < b.description }
}
