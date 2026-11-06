@testable import AppBundle
import Common
import XCTest

/// The config is user-authored data. Losing it is worse than a crash, because it is silent.
///
/// These run against a temp directory, never `$HOME` -- a test that can eat the developer's own
/// config is not a safety test.
@MainActor
final class ConfigSafetyBackupTest: XCTestCase {
    private var dir: URL!
    private var config: URL!

    override func setUp() async throws {
        dir = URL(filePath: NSTemporaryDirectory()).appending(path: "aerospork-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        config = dir.appending(path: ".aerospork.toml")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ text: String) throws { try text.write(to: config, atomically: true, encoding: .utf8) }
    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    private func at(_ minute: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(minute) * 60) }

    /// The whole point of P0-1: one generation meant the save that made you notice the damage was
    /// also the save that destroyed the last good copy.
    func testEachSaveKeepsItsOwnGeneration() throws {
        for i in 0 ..< 3 {
            try write("accordion-padding = \(i)")
            ConfigurationWriter.backUp(config, now: at(i))
        }
        let backups = ConfigurationWriter.backups(of: config)
        assertEquals(backups.count, 3)
        // Newest first, and each generation holds what the file said at that moment.
        assertEquals(backups.map { read($0) }, ["accordion-padding = 2", "accordion-padding = 1", "accordion-padding = 0"])
    }

    /// Bounded, or the home directory fills up with a backup per keystroke-debounce forever.
    func testOldGenerationsArePruned() throws {
        for i in 0 ..< (ConfigurationWriter.backupsToKeep + 4) {
            try write("accordion-padding = \(i)")
            ConfigurationWriter.backUp(config, now: at(i))
        }
        let backups = ConfigurationWriter.backups(of: config)
        assertEquals(backups.count, ConfigurationWriter.backupsToKeep)
        // The survivors are the newest ones -- pruning the wrong end would keep only ancient copies.
        assertEquals(read(backups.first!), "accordion-padding = \(ConfigurationWriter.backupsToKeep + 3)")
        assertEquals(read(backups.last!), "accordion-padding = 4")
    }

    /// A debounced burst can save twice inside one second. Keeping the FIRST copy of that second
    /// keeps the version furthest from whatever the user is trying to undo.
    func testSameSecondDoesNotOverwriteTheEarlierCopy() throws {
        try write("good")
        ConfigurationWriter.backUp(config, now: at(0))
        try write("bad")
        ConfigurationWriter.backUp(config, now: at(0))
        assertEquals(ConfigurationWriter.backups(of: config).compactMap { read($0) }, ["good"])
    }

    /// Autosave writes every 600ms. A backup per write rotated all five generations out within
    /// seconds, so the config from before Settings opened was gone by the time anyone wanted it.
    func testASettingsSessionKeepsOneBackupHoweverOftenItSaves() throws {
        try write("before settings opened")
        ConfigurationWriter.startBackupSession()
        for i in 0 ..< (ConfigurationWriter.backupsToKeep + 3) {
            ConfigurationWriter.backUpOncePerSession(config, now: at(i))
            try write("autosave \(i)")
        }
        assertEquals(ConfigurationWriter.backups(of: config).compactMap { read($0) }, ["before settings opened"])
    }

    /// Reopening Settings, or an explicit Raw TOML apply, is a new generation.
    func testANewSessionGetsItsOwnBackup() throws {
        try write("first")
        ConfigurationWriter.startBackupSession()
        ConfigurationWriter.backUpOncePerSession(config, now: at(0))
        try write("second")
        ConfigurationWriter.startBackupSession()
        ConfigurationWriter.backUpOncePerSession(config, now: at(1))
        assertEquals(ConfigurationWriter.backups(of: config).compactMap { read($0) }, ["second", "first"])
    }

    /// Backups must not be mistaken for configs, or `findCustomConfigUrl` starts reporting the
    /// config directory as ambiguous and the app refuses to write at all.
    func testBackupNamesAreNotTomlFiles() throws {
        try write("x")
        ConfigurationWriter.backUp(config, now: at(0))
        let name = ConfigurationWriter.backups(of: config).first!.lastPathComponent
        XCTAssertTrue(name.hasSuffix(".backup"), name)
        XCTAssertFalse(name.hasSuffix(".toml"), name)
    }

    /// Unrelated neighbours in the same directory are not ours to enumerate or delete.
    func testUnrelatedFilesAreIgnored() throws {
        try write("x")
        try "other".write(to: dir.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        try "other".write(to: dir.appending(path: "other.toml.20200101-000000.backup"), atomically: true, encoding: .utf8)
        ConfigurationWriter.backUp(config, now: at(0))
        assertEquals(ConfigurationWriter.backups(of: config).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "notes.txt").path))
    }
}
