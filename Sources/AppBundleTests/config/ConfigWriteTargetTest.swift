@testable import AppBundle
import Common
import XCTest

/// Under `swift test` the config reads and writes resolved to the developer's own
/// `~/.aerospork-debug.toml`, and only a refusal kept a save test from overwriting it. Now a test
/// reaches a config only through `testConfigOverride`, which lets a save run for real.
@MainActor
final class ConfigWriteTargetTest: XCTestCase {
    private static let text = "accordion-padding = 31\n"

    func testWithoutAnOverrideNothingResolvesToARealConfig() {
        XCTAssertNil(testConfigOverride)
        guard case .failure = userConfigTargetUrl() else { return XCTFail("a test resolved a real config to write") }
        assertEquals(ConfigurationWriter.backupsOfUserConfig(), [])
        guard case .failure = configBaseText() else { return XCTFail("a test read a real config") }
        guard case .failure = readConfig() else { return XCTFail("a test read a real config") }
    }

    func testTheOverrideIsTheOnlyTarget() throws {
        let url = try useTemporaryConfig(Self.text, for: self)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard case .success(let target) = userConfigTargetUrl() else { return XCTFail() }
        assertEquals(target, url)
        XCTAssertFalse(target.path.hasPrefix(home), target.path)
        assertEquals(try configBaseText().get(), Self.text)
        guard case .success((let parsed, let readUrl)) = readConfig() else { return XCTFail() }
        assertEquals(readUrl, url)
        assertEquals(parsed.accordionPadding, 31)
    }

    func testASaveWithNoEditWritesNothingAndMakesNoBackup() async throws {
        let url = try useTemporaryConfig(Self.text, for: self)
        let before = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        let vm = ConfigurationViewModel()
        vm.load(fromText: Self.text)
        ConfigurationWriter.startBackupSession()

        await vm.saveConfiguration()

        XCTAssertNil(vm.errorMessage)
        assertEquals(try String(contentsOf: url, encoding: .utf8), Self.text)
        assertEquals(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date, before)
        assertEquals(ConfigurationWriter.backups(of: url), [])
    }

    func testAnEditIsWrittenAndThenRecordedAsSaved() async throws {
        let url = try useTemporaryConfig(Self.text, for: self)
        let vm = ConfigurationViewModel()
        vm.load(fromText: Self.text)
        vm.settings.general.accordionPadding = 42
        XCTAssertTrue(vm.hasUnsavedChanges)

        await vm.saveConfiguration()

        XCTAssertNil(vm.errorMessage)
        let written = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(written.contains("accordion-padding = 42"), written)
        assertEquals(vm.rawToml, written)
        XCTAssertFalse(vm.hasUnsavedChanges)
    }

    /// `didWrite` comes after the write: a write that fails leaves the edit pending.
    func testAFailedWriteLeavesTheEditPending() async throws {
        let url = try useTemporaryConfig(Self.text, for: self)
        let vm = ConfigurationViewModel()
        vm.load(fromText: Self.text)
        vm.settings.general.accordionPadding = 42
        let dir = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }

        await vm.saveConfiguration()

        XCTAssertTrue(vm.errorMessage?.hasPrefix("Failed to save configuration") == true, vm.errorMessage ?? "no error")
        XCTAssertTrue(vm.hasUnsavedChanges)
        assertEquals(try String(contentsOf: url, encoding: .utf8), Self.text)
    }

    func testTheMigrationSeamMigratesTheGivenFile() throws {
        let v1 = "[mode.main.binding]\nalt-h = 'focus left'\n"
        let url = try useTemporaryConfig(v1, for: self)

        migrateConfigToV2(at: url)

        assertEquals(try String(contentsOf: url.appendingPathExtension("pre-v2"), encoding: .utf8), v1)
        let migrated = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(migrated.contains("mode.main.binding"), migrated)
    }
}
