@testable import Common
import CryptoKit
import Foundation
import XCTest

/// Two levels above `Sources/CommonTests/`, not a `.git` walk, so a tree with no `.git` works too.
let projectRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

func grammarText() throws -> String {
    XCTAssertTrue(FileManager.default.fileExists(atPath: projectRoot.appending(component: "Package.swift").path), projectRoot.path)
    return try String(contentsOf: projectRoot.appending(path: "grammar/commands-bnf-grammar.txt"), encoding: .utf8)
}

/// Shell completion must offer every command the CLI actually has.
///
/// `grammar/commands-bnf-grammar.txt` is hand-maintained and drives complgen, which generates the
/// bash/fish/zsh completions shipped in the release. Nothing kept it in sync with `CmdKind`, so a
/// command could work while tab-completion did not know it existed -- which is how `open-settings`
/// and two flags (`--show-secrets`, `--workspace` on `move-workspace-to-monitor`) went missing.
final class ShellCompletionGrammarTest: XCTestCase {
    func testEveryCommandIsCompletable() throws {
        let text = try grammarText()
        // A production head, i.e. `<name>` at the start of an alternative -- not a bare mention,
        // which would also match the command's name inside a comment or another command's args.
        let heads = Set(
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.hasPrefix("| ") ? String($0.dropFirst(2)) : $0 }
                .compactMap { $0.split(separator: " ").first.map(String.init) },
        )

        // `exec-and-forget` is config-only: it is rejected in the CLI by design, so completing it
        // would advertise something that always errors.
        let cliOnly = Set(CmdKind.allCases.map(\.rawValue)).subtracting(["exec-and-forget"])
        let missing = cliOnly.subtracting(heads).sorted()
        XCTAssertEqual(missing, [], "not offered by shell completion: \(missing)")
    }

    /// Counter-check: the parse must actually be finding production heads. Without it, a grammar
    /// that failed to load would make the test above pass with an empty `missing`.
    func testTheGrammarWasActuallyRead() throws {
        let text = try grammarText()
        XCTAssertGreaterThan(text.count, 500, "grammar file looks empty")
        XCTAssertTrue(text.contains("<subcommand> ::="), "not the grammar file we think it is")
    }

    /// The vendored `shell-completion/` was generated from this grammar. `build-shell-completion.sh`
    /// writes the hash itself, so it cannot be bumped without regenerating.
    func testShellCompletionWasGeneratedFromThisGrammar() throws {
        let grammar = try Data(contentsOf: projectRoot.appending(path: "grammar/commands-bnf-grammar.txt"))
        let actual = SHA256.hash(data: grammar).map { String(format: "%02x", $0) }.joined()
        let recorded = try String(contentsOf: projectRoot.appending(path: "shell-completion/.grammar-sha256"), encoding: .utf8)
            .split(separator: " ").first.map(String.init)
        XCTAssertEqual(recorded, actual, "grammar/commands-bnf-grammar.txt changed: run ./build-shell-completion.sh and commit shell-completion/")
    }
}
