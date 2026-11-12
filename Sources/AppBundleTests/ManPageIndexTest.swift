@testable import AppBundle
import XCTest

/// `docs/aerospork.adoc` is the `aerospork(1)` page, and its SEE ALSO list is the only index of the
/// subcommand pages. `CliSurfaceTest` ties every page to a command, but nothing tied the pages to
/// that list, so a new command shipped a man page that `man aerospork` never mentioned.
final class ManPageIndexTest: XCTestCase {
    func testTheMainManPageListsEverySubcommandPage() throws {
        let docs = projectRoot.appending(path: "docs")
        let pages = Set(try FileManager.default.contentsOfDirectory(atPath: docs.path)
            .filter { $0.hasPrefix("aerospork-") && $0.hasSuffix(".adoc") }
            .map { String($0.dropLast(".adoc".count)) })
        let index = try String(contentsOf: docs.appending(path: "aerospork.adoc"), encoding: .utf8)
        let listed = Set(index.matches(of: /(aerospork-[a-z-]+)\(1\)/).map { String($0.1) })
        XCTAssertEqual(pages.subtracting(listed).sorted(), [], "pages missing from aerospork.adoc")
        XCTAssertEqual(listed.subtracting(pages).sorted(), [], "aerospork.adoc names pages that do not exist")
    }
}
