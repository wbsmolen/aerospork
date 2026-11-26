@testable import AppBundle
import Common
import ServiceManagement
import XCTest

/// A broken config makes the app start on the BUNDLED DEFAULT — every binding the user wrote is
/// replaced, and the only signal was a modal dialog they dismissed. These pin the two halves of
/// making that honest: the state stays visible, and fixing the file recovers on its own.
@MainActor
final class ConfigSafetyStartupTest: XCTestCase {
    private var savedUrl: URL!
    private var savedFailure: String?

    override func setUp() async throws {
        savedUrl = configUrl
        savedFailure = configLoadFailure
    }

    override func tearDown() async throws {
        configUrl = savedUrl
        configLoadFailure = savedFailure
    }

    func testFallbackToDefaultsIsVisible() {
        configLoadFailure = "Failed to parse ~/.aerospork.toml"
        configUrl = defaultConfigUrl
        XCTAssertTrue(isRunningFallbackDefaults)
    }

    /// Recovery needs no separate signal: a successful reload points `configUrl` back at the user's
    /// file and clears the failure, so the banner and the menu-bar warning go away by themselves.
    func testFixingTheConfigClearsTheWarning() {
        configLoadFailure = "Failed to parse ~/.aerospork.toml"
        configUrl = defaultConfigUrl
        configLoadFailure = nil
        configUrl = URL(filePath: "/tmp/aerospork-test.toml")
        XCTAssertFalse(isRunningFallbackDefaults)
    }

    /// A healthy app running the bundled default (no user config exists) is not "in fallback".
    func testBundledDefaultWithoutAFailureIsNotFallback() {
        configLoadFailure = nil
        configUrl = defaultConfigUrl
        XCTAssertFalse(isRunningFallbackDefaults)
    }

    /// `initAppBundle` retries with the bundled default the instant the user's config fails, and
    /// that retry always succeeds. Recording health from it would wipe the failure a millisecond
    /// after it was recorded, leaving nothing anywhere that says the config did not load.
    func testForcedDefaultReadDoesNotEraseTheFailure() {
        configLoadFailure = "Failed to parse ~/.aerospork.toml"
        var warnings: [String] = []
        recordConfigHealth(readConfig(forceConfigUrl: defaultConfigUrl, warnings: &warnings), warnings: warnings)
        assertEquals(configLoadFailure, "Failed to parse ~/.aerospork.toml")
    }

    /// `reload-config --dry-run` promises to change nothing. A passing one cleared the failure, so the
    /// banner went away while the defaults still ran, and a failing one set a failure for a config the
    /// app was not running.
    func testDryRunDoesNotTouchHealth() throws {
        let good = try useTemporaryConfig("accordion-padding = 31\n", for: self)
        let bad = good.deletingLastPathComponent().appending(path: "bad.toml")
        try "accordion-padding = 'thirty'\n".write(to: bad, atomically: true, encoding: .utf8)
        var args = ReloadConfigCmdArgs(rawArgs: [])
        args.dryRun = true
        args.noGui = true
        var stdout = ""

        configUrl = defaultConfigUrl
        configLoadFailure = "Failed to parse ~/.aerospork.toml"
        configWarnings = ["a warning from the running config"]
        XCTAssertTrue(reloadConfig(args: args, forceConfigUrl: good, stdout: &stdout), stdout)
        assertEquals(configLoadFailure, "Failed to parse ~/.aerospork.toml")
        assertEquals(configWarnings, ["a warning from the running config"])
        XCTAssertTrue(isRunningFallbackDefaults)

        configLoadFailure = nil
        XCTAssertFalse(reloadConfig(args: args, forceConfigUrl: bad, stdout: &stdout))
        XCTAssertNil(configLoadFailure)
        assertEquals(configWarnings, ["a warning from the running config"])
    }

    /// Under `swift test` the URL-less read resolved to the developer's own `~/.aerospork-debug.toml`.
    func testUnitTestsNeverResolveTheRealConfig() {
        XCTAssertNil(testConfigOverride)
        guard case .failure(let reason) = readConfig() else { return XCTFail("a test read a real config") }
        assertEquals(reason, "tests may not touch a real config")
        guard case .failure = configBaseText() else { return XCTFail("a test read a real config") }
        guard case .failure = userConfigTargetUrl() else { return XCTFail("a test resolved a real config to write") }
        // A forced read still reads exactly the file it names.
        guard case .success((_, let url)) = readConfig(forceConfigUrl: defaultConfigUrl) else { return XCTFail() }
        assertEquals(url, defaultConfigUrl)
    }

    /// With two configs, the search for the user's config fails. The forced read of the bundled default
    /// ran that search first and failed the same way, and `initAppBundle` `check`s it: the app died at
    /// startup. Now the defaults run, and the banner says why.
    func testTheForcedDefaultReadSurvivesTwoConfigs() throws {
        let first = try useTemporaryConfig("accordion-padding = 1\n", for: self)
        let second = try useTemporaryConfig("accordion-padding = 2\n", for: self)
        let twoConfigs = findCustomConfigUrl(among: [first, second])
        guard case .ambiguousConfigError = twoConfigs else { return XCTFail("two configs were not ambiguous") }
        configLoadFailure = nil

        let read = readConfig(found: twoConfigs)
        guard case .failure = read else { return XCTFail("an ambiguous config loaded") }
        recordConfigHealth(read, warnings: [])
        guard case .success((_, let url)) = readConfig(forceConfigUrl: defaultConfigUrl, found: twoConfigs) else {
            return XCTFail("the startup fallback failed, and initAppBundle would die")
        }
        configUrl = url
        XCTAssertTrue(isRunningFallbackDefaults)
    }

    /// A config that existed and could not be read loaded as "the defaults, successfully": no banner,
    /// and the log said the user's file had loaded. A Latin-1 file is the likely case.
    func testUnreadableConfigIsAFailureNotTheDefaults() throws {
        let locked = try useTemporaryConfig("accordion-padding = 31\n", for: self)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }
        let latin1 = locked.deletingLastPathComponent().appending(path: "latin1.toml")
        try Data("accordion-padding = 31 # caf\u{E9}\n".data(using: .isoLatin1).orDie()).write(to: latin1)

        for (url, why) in [(locked, "permission denied"), (latin1, "isn't UTF-8 text")] {
            configLoadFailure = nil
            let read = readConfig(at: url)
            guard case .failure(let reason) = read else { return XCTFail("\(url.lastPathComponent) loaded") }
            XCTAssertTrue(reason.contains(why), reason)
            recordConfigHealth(read, warnings: [])
            // `initAppBundle`'s fallback: it must succeed, and leave the failure showing.
            guard case .success((_, let fallback)) = readConfig(forceConfigUrl: defaultConfigUrl) else { return XCTFail() }
            configUrl = fallback
            XCTAssertTrue(isRunningFallbackDefaults, url.lastPathComponent)
        }
    }

    /// A dangling link (a dotfiles repo not checked out yet) read as "no config", and the first
    /// Settings save replaced the link with a regular file.
    func testDanglingConfigLinkIsReportedAndNotReplaced() async throws {
        let link = try useTemporaryConfig("", for: self)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "dotfiles/aerospork.toml")
        let missing = link.deletingLastPathComponent().appending(path: "missing.toml")

        guard case .file(let found) = findCustomConfigUrl(among: [link, missing]) else { return XCTFail("the link was not found") }
        assertEquals(found, link)
        guard case .failure(let reason) = readConfig(at: link) else { return XCTFail("a dangling link loaded") }
        XCTAssertTrue(reason.contains("is a link to dotfiles/aerospork.toml, which does not exist"), reason)

        let vm = ConfigurationViewModel()
        defer { vm.cancelPendingAutoSave() }
        vm.load(fromText: "")
        vm.settings.general.accordionPadding = 42
        await vm.saveConfiguration()

        XCTAssertNotNil(vm.errorMessage)
        assertEquals(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), "dotfiles/aerospork.toml")

        // A stale link next to a working config changes nothing: the config is still found.
        let real = link.deletingLastPathComponent().appending(path: "real.toml")
        try "".write(to: real, atomically: true, encoding: .utf8)
        guard case .file(let foundReal) = findCustomConfigUrl(among: [link, real]) else { return XCTFail() }
        assertEquals(foundReal, real)
    }

    /// The migration rewrites the user's file, so it belongs to startup. Inside `readConfig` it also
    /// ran for `reload-config --dry-run`, which promises to change nothing, and every Settings save.
    func testTheV2MigrationRunsOnceAtStartupAndNotOnEveryRead() throws {
        for declaration in ["func readConfig(forceConfigUrl", "func readConfig(at"] {
            let read = try sourceBody(declaration, in: "Sources/AppBundle/config/parseConfig.swift")
            XCTAssertFalse(read.contains("migrate"), declaration)
        }
        let start = try sourceBody("public func initAppBundle()", in: "Sources/AppBundle/initAppBundle.swift")
        let migrate = try XCTUnwrap(start.range(of: "migrateUserConfigToV2IfNeeded()"))
        let firstLoad = try XCTUnwrap(start.range(of: "reloadConfig()"))
        XCTAssertLessThan(migrate.lowerBound, firstLoad.lowerBound)
    }

    /// A settings save reloads the config, so this runs on every save.
    func testStartAtLoginOnlyCallsTheSystemWhenTheAnswerChanges() {
        XCTAssertFalse(startAtLoginNeedsChange(wanted: true, status: .enabled))
        XCTAssertFalse(startAtLoginNeedsChange(wanted: true, status: .requiresApproval), "would ask for approval again")
        XCTAssertFalse(startAtLoginNeedsChange(wanted: false, status: .notRegistered))
        XCTAssertFalse(startAtLoginNeedsChange(wanted: false, status: .notFound))
        XCTAssertTrue(startAtLoginNeedsChange(wanted: true, status: .notRegistered))
        XCTAssertTrue(startAtLoginNeedsChange(wanted: false, status: .enabled))
        XCTAssertTrue(startAtLoginNeedsChange(wanted: false, status: .requiresApproval))
    }

    /// The watcher must follow the file the USER edits. Watching `configUrl` meant that after a
    /// fallback it watched a file inside the app bundle, which can never change — so the fix the
    /// user was busy typing would not be picked up until the app was restarted.
    func testWatcherNeverWatchesTheBundledDefault() {
        configUrl = defaultConfigUrl
        XCTAssertNotEqual(ConfigFileWatcher.watchedPath, defaultConfigUrl.path)
    }
}
