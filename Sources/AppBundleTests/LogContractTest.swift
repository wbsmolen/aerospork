@testable import AppBundle
import Common
import OSLog
import XCTest

/// The guide's troubleshooting part ("Troubleshooting and bug reports" in `docs/guide.adoc`) tells users
/// to filter the unified log by category and to look for exact records. A renamed category or a reworded
/// record leaves those instructions returning nothing, and only the subsystem was pinned
/// (`BrandingTest.testLoggersUseTheBuildsOwnBundleId`).
@MainActor
final class LogContractTest: XCTestCase {
    /// Read back from the unified log, so it pins what a user's `log show` sees, not the source text.
    /// One read: reading the store takes seconds, whatever the start position.
    func testTheCategoriesAndTheReloadRecordReachTheLog() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "LogContractTest-\(UUID().uuidString).toml")
        try "".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let start = Date()

        let probe = "LogContractTest probe \(UUID().uuidString)"
        AppLog.config.notice("\(probe, privacy: .public)")
        AppLog.server.notice("\(probe, privacy: .public)")
        AppLog.session.notice("\(probe, privacy: .public)")
        var args = ReloadConfigCmdArgs(rawArgs: [])
        args.dryRun = true
        var stdout = ""
        XCTAssertTrue(reloadConfig(args: args, forceConfigUrl: url, stdout: &stdout), stdout)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let records = try store.getEntries(at: store.position(date: start), matching: NSPredicate(format: "subsystem == %@", aeroSporkAppId))
            .compactMap { $0 as? OSLogEntryLog }
            .map { (category: $0.category, message: $0.composedMessage) }
        for category in ["config", "server", "session"] {
            XCTAssertTrue(
                records.contains { $0.category == category && $0.message == probe },
                "no record under category \(category); the guide tells users to filter on it",
            )
        }
        XCTAssertTrue(
            records.contains { $0.category == "config" && $0.message == "Config loaded: \(url.path)" },
            "a reload no longer records which file loaded, under config",
        )
    }

    /// A key another app owns fails to register, and that cannot be arranged without taking a real key
    /// from the user, so this one is read from the source.
    func testAHotkeyThatFailsToRegisterIsRecordedAsTheGuideQuotesIt() throws {
        let source = try String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/config/HotkeyBinding.swift"), encoding: .utf8)
        let line = try XCTUnwrap(source.split(separator: "\n").first { $0.contains(" not registered") }, "the guide quotes `Hotkey <key> not registered`")
        XCTAssertTrue(line.contains(#"AppLog.config.error("Hotkey \("#), "the record must start `Hotkey <key>` and go to the config category")
    }
}
