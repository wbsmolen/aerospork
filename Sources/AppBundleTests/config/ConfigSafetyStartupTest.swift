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
        _ = readConfig(forceConfigUrl: defaultConfigUrl)
        assertEquals(configLoadFailure, "Failed to parse ~/.aerospork.toml")
    }

    /// Under `swift test` the URL-less read resolved to the developer's own `~/.aerospork-debug.toml`.
    func testUnitTestsNeverResolveTheRealConfig() {
        XCTAssertNil(testConfigOverride)
        guard case .failure(let reason) = readConfig() else { return XCTFail("a test read a real config") }
        assertEquals(reason, "tests may not touch a real config")
        assertEquals(configBaseText(), "")
        guard case .failure = userConfigTargetUrl() else { return XCTFail("a test resolved a real config to write") }
        // A forced read still reads exactly the file it names.
        guard case .success((_, let url)) = readConfig(forceConfigUrl: defaultConfigUrl) else { return XCTFail() }
        assertEquals(url, defaultConfigUrl)
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
