@testable import AppBundle
import Common
import Foundation
import XCTest

/// Every TOML example in the user docs must parse, and must teach the v2 spelling.
///
/// The guide, the goodies page and the i3 example taught `[mode.main.binding]` long after the shipped
/// default moved to `[keys]`. A user who copied one got a v1 file, which AeroSpork rewrites on the next
/// start, and the comments survived only in the `.pre-v2` copy. `ReadmeExamplesTest` covers the README.
@MainActor
final class DocExamplesTest: XCTestCase {
    struct Block {
        let file: String
        let line: Int
        let text: String
        /// The anchor of the section the block sits in, such as `config-v2`.
        let section: String?
    }

    /// The `[source,toml...]` blocks of an AsciiDoc file. A block that includes a file is skipped: the
    /// file itself is checked on its own.
    static func tomlBlocks(inAsciiDoc text: String, file: String) -> [Block] {
        var blocks: [Block] = []
        var section: String? = nil
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)[...]
        var lineNumber = 0
        while let line = lines.popFirst() {
            lineNumber += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[#"), trimmed.hasSuffix("]") {
                section = String(trimmed.dropFirst(2).dropLast())
            }
            guard trimmed.hasPrefix("[source,toml") else { continue }
            guard lines.first?.trimmingCharacters(in: .whitespaces) == "----" else { continue }
            _ = lines.popFirst()
            lineNumber += 1
            let start = lineNumber + 1
            var body: [String] = []
            while let next = lines.popFirst() {
                lineNumber += 1
                if next.trimmingCharacters(in: .whitespaces) == "----" { break }
                body.append(next)
            }
            let joined = body.joined(separator: "\n")
            if joined.contains("include::") { continue }
            blocks.append(Block(file: file, line: start, text: joined, section: section))
        }
        return blocks
    }

    private func allBlocks() throws -> [Block] {
        let docs = projectRoot.appending(path: "docs")
        var result: [Block] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: docs.path).sorted() where name.hasSuffix(".adoc") {
            let text = try String(contentsOf: docs.appending(path: name), encoding: .utf8)
            result += Self.tomlBlocks(inAsciiDoc: text, file: "docs/\(name)")
        }
        let examples = docs.appending(path: "config-examples")
        for name in try FileManager.default.contentsOfDirectory(atPath: examples.path).sorted() where name.hasSuffix(".toml") {
            let text = try String(contentsOf: examples.appending(path: name), encoding: .utf8)
            result.append(Block(file: "docs/config-examples/\(name)", line: 1, text: text, section: nil))
        }
        return result
    }

    func testExtractorFindsTheGuideExamples() throws {
        let blocks = try allBlocks()
        XCTAssertTrue(blocks.contains { $0.file == "docs/guide.adoc" }, "no TOML blocks in the guide: the extractor is broken")
        XCTAssertTrue(blocks.contains { $0.file == "docs/goodies.adoc" }, "no TOML blocks in goodies: the extractor is broken")
        XCTAssertTrue(blocks.contains { $0.file.hasPrefix("docs/config-examples/") }, "no config examples found")
    }

    /// The errors of a block, read as a whole config. A block with no table header and no known
    /// top-level key, such as `alt-enter = '...'` in a man page, is a fragment of `[keys]`, so it is
    /// read under `[keys]` when it does not parse on its own.
    private func errors(of block: Block) -> [String] {
        func errors(_ text: String) -> [String] {
            switch parseConfig(text) {
                case .success: []
                // Unit tests run with a stub environment that holds only PATH, so `${HOME}` in an
                // example cannot resolve here. That says nothing about the example.
                case .failure(let errors): errors.descriptions.filter { !$0.contains("isn't presented in AeroSpork.app env vars") }
            }
        }
        let asIs = errors(block.text)
        let hasHeader = block.text.split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }
        if asIs.isEmpty || hasHeader { return asIs }
        return errors("[keys]\n" + block.text).isEmpty ? [] : asIs
    }

    func testEveryDocTomlExampleParses() throws {
        for block in try allBlocks() {
            let errors = errors(of: block)
            if !errors.isEmpty {
                XCTFail("\(block.file):\(block.line): TOML example does not parse:\n\(block.text)\n\n\(errors)")
            }
        }
    }

    /// The v1 binding spelling belongs only in the reference section that explains v1 and v2.
    func testDocExamplesUseTheV2BindingSpelling() throws {
        let v1Binding = /^\s*\[mode\.[^\]]+\.binding\]/.anchorsMatchLineEndings()
        for block in try allBlocks() where block.section != "config-v2" {
            XCTAssertNil(
                block.text.firstMatch(of: v1Binding),
                "\(block.file):\(block.line): teaches the v1 `[mode.<name>.binding]` spelling. Use `[keys]` or `[keys.<mode>]`",
            )
            XCTAssertFalse(
                block.text.contains("workspace-to-monitor-force-assignment"),
                "\(block.file):\(block.line): teaches the v1 monitor spelling. Use `[monitors]`",
            )
        }
    }
}
