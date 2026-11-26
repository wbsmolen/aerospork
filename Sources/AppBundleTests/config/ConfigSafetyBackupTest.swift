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
            try ConfigurationWriter.backUp(config, now: at(i))
        }
        let backups = ConfigurationWriter.backups(of: config)
        assertEquals(backups.count, 3)
        // Newest first, and each generation holds what the file said at that moment.
        assertEquals(backups.map { read($0) }, ["accordion-padding = 2", "accordion-padding = 1", "accordion-padding = 0"])
    }

    /// The documented count. The pruning test reads the constant, so it passes whatever it says.
    func testFiveGenerationsAreKept() {
        assertEquals(ConfigurationWriter.backupsToKeep, 5)
    }

    /// Bounded, or the home directory fills up with a backup per keystroke-debounce forever.
    func testOldGenerationsArePruned() throws {
        for i in 0 ..< (ConfigurationWriter.backupsToKeep + 4) {
            try write("accordion-padding = \(i)")
            try ConfigurationWriter.backUp(config, now: at(i))
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
        try ConfigurationWriter.backUp(config, now: at(0))
        try write("bad")
        try ConfigurationWriter.backUp(config, now: at(0))
        assertEquals(ConfigurationWriter.backups(of: config).compactMap { read($0) }, ["good"])
    }

    /// Autosave writes every 600ms. A backup per write rotated all five generations out within
    /// seconds, so the config from before Settings opened was gone by the time anyone wanted it.
    func testASettingsSessionKeepsOneBackupHoweverOftenItSaves() throws {
        try write("before settings opened")
        ConfigurationWriter.startBackupSession()
        for i in 0 ..< (ConfigurationWriter.backupsToKeep + 3) {
            try ConfigurationWriter.backUpOncePerSession(config, now: at(i))
            try write("autosave \(i)")
        }
        assertEquals(ConfigurationWriter.backups(of: config).compactMap { read($0) }, ["before settings opened"])
    }

    /// Reopening Settings, or an explicit Raw TOML apply, is a new generation.
    func testANewSessionGetsItsOwnBackup() throws {
        try write("first")
        ConfigurationWriter.startBackupSession()
        try ConfigurationWriter.backUpOncePerSession(config, now: at(0))
        try write("second")
        ConfigurationWriter.startBackupSession()
        try ConfigurationWriter.backUpOncePerSession(config, now: at(1))
        assertEquals(ConfigurationWriter.backups(of: config).compactMap { read($0) }, ["second", "first"])
    }

    /// The copy failed quietly, and the atomic write still replaced the file, since a rename needs only
    /// the directory to be writable. So the one write with no backup was the one most likely to hurt.
    func testAWriteThatCannotBackUpIsRefused() throws {
        try write("mine")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: config.path)
        ConfigurationWriter.startBackupSession()
        XCTAssertThrowsError(try ConfigurationWriter.write("replaced", to: config))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: config.path)
        assertEquals(read(config), "mine")
    }

    // MARK: - A config that is a link (stow, chezmoi, home-manager)

    private func linkedConfig(_ text: String) throws -> (link: URL, target: URL) {
        let repo = dir.appending(path: "dotfiles")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let target = repo.appending(path: "aerospork.toml")
        try text.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: target)
        return (config, target)
    }

    private func isLink(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    /// An atomic write to the link path replaced the link with a regular file, and the dotfiles repo
    /// kept the old text. A backup made with `copyItem` was a copy of the link, so it followed the file.
    func testSaveThroughSymlinkKeepsTheLink() throws {
        let (link, target) = try linkedConfig("old")
        ConfigurationWriter.startBackupSession()

        try ConfigurationWriter.write("new", to: link)

        XCTAssertTrue(isLink(link), "the link was replaced")
        assertEquals(read(target), "new")
        let backups = ConfigurationWriter.backups(of: link)
        assertEquals(backups.count, 1)
        let backup = try XCTUnwrap(backups.first)
        XCTAssertFalse(isLink(backup), "the backup is a link, so it follows the live file")
        assertEquals(read(backup), "old")
        assertEquals(backup.deletingLastPathComponent().path, link.deletingLastPathComponent().path)
        assertEquals(ConfigurationWriter.backups(of: target), [])
    }

    /// The Nix store: the write cannot land, and the Cocoa error named neither file.
    func testSaveThroughLinkToReadOnlyTargetIsRefusedWithAClearMessage() throws {
        let (link, target) = try linkedConfig("managed")
        let repo = target.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: repo.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repo.path) }
        ConfigurationWriter.startBackupSession()

        XCTAssertThrowsError(try ConfigurationWriter.write("new", to: link)) { error in
            assertEquals(error.localizedDescription, "\(link.path) is a link to a read-only file. Edit it where it is managed.")
        }
        XCTAssertTrue(isLink(link))
        assertEquals(read(target), "managed")
        assertEquals(ConfigurationWriter.backups(of: link), [])
    }

    /// Raw TOML replaces the whole file, so its apply is a generation of its own even inside one
    /// Settings session.
    func testARawTomlApplyStartsANewBackupSession() async throws {
        let text = "accordion-padding = 31\n"
        let url = try useTemporaryConfig(text, for: self)
        let vm = ConfigurationViewModel()
        defer { vm.cancelPendingAutoSave() }
        vm.load(fromText: text)
        ConfigurationWriter.startBackupSession()
        vm.settings.general.accordionPadding = 42
        await vm.saveConfiguration()
        XCTAssertNil(vm.errorMessage)
        // Backups are named to the second, so clear this one to see whether the apply takes its own.
        for backup in ConfigurationWriter.backups(of: url) { try FileManager.default.removeItem(at: backup) }

        vm.rawToml = "accordion-padding = 7\n"
        vm.rawTomlApplyRequested = true
        await vm.saveConfiguration()

        XCTAssertNil(vm.errorMessage)
        assertEquals(ConfigurationWriter.backups(of: url).compactMap { read($0) }, ["accordion-padding = 42\n"])
    }

    /// Backups must not be mistaken for configs, or `findCustomConfigUrl` starts reporting the
    /// config directory as ambiguous and the app refuses to write at all.
    func testBackupNamesAreNotTomlFiles() throws {
        try write("x")
        try ConfigurationWriter.backUp(config, now: at(0))
        let name = ConfigurationWriter.backups(of: config).first!.lastPathComponent
        XCTAssertTrue(name.hasSuffix(".backup"), name)
        XCTAssertFalse(name.hasSuffix(".toml"), name)
    }

    /// Unrelated neighbours in the same directory are not ours to enumerate or delete.
    func testUnrelatedFilesAreIgnored() throws {
        try write("x")
        try "other".write(to: dir.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        try "other".write(to: dir.appending(path: "other.toml.20200101-000000.backup"), atomically: true, encoding: .utf8)
        try ConfigurationWriter.backUp(config, now: at(0))
        assertEquals(ConfigurationWriter.backups(of: config).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appending(path: "notes.txt").path))
    }
}
