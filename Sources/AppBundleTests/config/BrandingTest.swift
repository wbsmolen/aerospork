@testable import AppBundle
import Common
import Foundation
import XCTest

/// Source-text invariants for the fork's own name.
///
/// Asserted against the source rather than against behaviour because the leaks that actually reach
/// users are string literals inside instructions -- `Run 'aerospace debug-windows' once again`,
/// `You can use 'aerospace enable on'` -- and a test that exercised those code paths would need a
/// live debug-windows session and a disabled server. The property is "the wrong product name does
/// not appear", which is exactly a text property.
///
/// Same technique, and same reasoning, as `PerfInvariantsTest.testHotPathsContainNoUnconditionalPrint`.
final class BrandingTest: XCTestCase {
    /// Every Swift source the product ships, with no exemptions left.
    ///
    /// This used to be a list of subdirectories, which silently excluded `Sources/AppBundle/*.swift`
    /// itself -- `focus.swift`, `server.swift`, `GlobalObserver.swift`, `runLoop.swift` and friends
    /// were never scanned by the invariant that claims to cover the codebase. Enumerating
    /// `Sources/AppBundle` recursively closes that hole and subsumes the old list, `ui/` included.
    ///
    /// The former carve-outs are all gone: the `AEROSPACE_*` `exec` env-var aliases, the
    /// `during-aerospace-startup` matcher key, and the `aeroSpaceApp*` identifiers were removed
    /// outright rather than deprecated.
    private static let scanned = [
        "Sources/AppBundle",
        "Sources/Cli",
        "Sources/Common",
    ]

    private func swiftFiles() throws -> [(path: String, text: String)] {
        var result: [(String, String)] = []
        for dir in Self.scanned {
            let root = projectRoot.appending(path: dir)
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" } ?? []
            XCTAssertFalse(files.isEmpty, "\(dir) matched no Swift files -- the scan silently covered nothing")
            for file in files {
                result.append((file.path.replacingOccurrences(of: projectRoot.path + "/", with: ""), try String(contentsOf: file, encoding: .utf8)))
            }
        }
        return result
    }

    /// The one file allowed to spell the upstream name. Recognising a config brought over from
    /// upstream -- its file name, its env vars, its CLI, its keys -- means naming them, so every such
    /// string lives there and nowhere else. One file, so the exemption cannot spread.
    private static let upstreamMigrationFile = "Sources/AppBundle/config/upstreamMigration.swift"

    /// The upstream product name, in any case, in any of the owned sources. `during-…-startup` and
    /// `AEROSPACE_*` were removed outright rather than deprecated, so there is no legitimate
    /// remaining occurrence -- not in a literal, not in a comment -- outside `upstreamMigrationFile`.
    func testOwnedSourcesDoNotMentionTheUpstreamProductName() throws {
        var offenders: [String] = []
        for (path, text) in try swiftFiles() where path != Self.upstreamMigrationFile {
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.lowercased().contains("aerospace")
            {
                offenders.append("\(path):\(i + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(offenders, [], "the product is AeroSpork:\n" + offenders.joined(separator: "\n"))
    }

    /// Every `os.Logger` must take its subsystem from the build's real bundle id. A hardcoded
    /// release id makes a debug build file its records under the release app's subsystem, so
    /// `log show --predicate 'subsystem == "com.wbs.aerospork"'` mixes the two binaries and a user
    /// with both installed cannot tell which one produced a line.
    func testLoggersUseTheBuildsOwnBundleId() throws {
        var offenders: [String] = []
        for (path, text) in try swiftFiles() {
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("Logger(subsystem:") && !line.contains("aeroSporkAppId")
            {
                offenders.append("\(path):\(i + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(offenders, [], "use aeroSporkAppId, not a literal:\n" + offenders.joined(separator: "\n"))
    }

    /// The exemption must not outlive its reason: the file exists, is scanned, and still needs it.
    func testTheUpstreamMigrationExemptionIsStillNeeded() throws {
        let file = try XCTUnwrap(try swiftFiles().first { $0.path == Self.upstreamMigrationFile }, "exempted file is gone; drop the exemption")
        XCTAssertTrue(file.text.lowercased().contains("aerospace"), "the exempted file no longer names upstream; drop the exemption")
    }

    /// Counter-check: the scan must actually be looking at file contents. Without this, a broken
    /// enumerator (wrong path, wrong extension filter) would make both tests above pass vacuously.
    func testTheScanReadsRealSources() throws {
        let files = try swiftFiles()
        XCTAssertGreaterThan(files.count, 20, "expected the command+config trees, got \(files.count) files")
        XCTAssertTrue(
            files.contains { $0.path.hasSuffix("AppBundle/AppLog.swift") && $0.text.contains("aeroSporkAppId") },
            "anchor file not found -- the enumerator is not reading what the scan claims to read",
        )
        // The gap this scan used to have: AppBundle's own top-level sources.
        XCTAssertTrue(files.contains { $0.path.hasSuffix("AppBundle/focus.swift") }, "AppBundle root files are not being scanned")
    }

    // MARK: - The fork's own name is stylized consistently

    /// `aeroSporkAppName` is *display* text -- it is interpolated into the menu bar's Quit item, the
    /// "server is disabled" error, and the version string a user pastes into a bug report. It is not
    /// a path: `aeroSporkAppId` is what names the bundle, the log subsystem and the socket.
    ///
    /// It used to be `"aerospork"`, which made the app contradict itself: the crash dialog said
    /// `AeroSpork` while the menu bar said "Quit aerospork". Pinning the constant fixes the whole
    /// class, because every display site interpolates it rather than hardcoding a literal.
    /// Checked against the SOURCE TEXT, not the compiled constant, because `appMetadata.swift` is
    /// an `#if DEBUG` pair and a test binary only ever compiles one branch -- so asserting on the
    /// value would silently leave the release spelling unpinned. (Verified: lowercasing the release
    /// branch alone did not fail a value-based assertion.)
    func testTheDisplayNameIsStylizedAeroSpork() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/Common/appMetadata.swift"),
            encoding: .utf8,
        )
        for line in source.split(separator: "\n") where line.contains("aeroSporkAppName") && line.contains("=") {
            XCTAssertTrue(
                line.contains("\"AeroSpork"),
                "the product is written AeroSpork in prose: \(line.trimmingCharacters(in: .whitespaces))",
            )
        }
        for line in source.split(separator: "\n") where line.contains("aeroSporkAppId") && line.contains("=") {
            // The identifier is the opposite rule: lowercase, or bundle paths, the log subsystem
            // and the CLI socket path all break.
            XCTAssertTrue(
                line.contains("\"com.wbs.aerospork"),
                "the bundle id must stay lowercase: \(line.trimmingCharacters(in: .whitespaces))",
            )
        }
        // The compiled branch must agree with what we just scanned.
        XCTAssertTrue(aeroSporkAppName.hasPrefix("AeroSpork"), aeroSporkAppName)
    }

    /// macOS shows `CFBundleDisplayName` (falling back to `CFBundleName`) in the Settings window
    /// title, Force Quit, Login Items and the Accessibility prompt. `CFBundleName` comes from
    /// `PRODUCT_NAME`, which also names `aerospork.app` on disk -- so the display name has to be
    /// declared separately or the window title reads "aerospork Settings".
    func testProjectDeclaresACapitalizedDisplayName() throws {
        let yml = try String(contentsOf: projectRoot.appending(path: "project.yml"), encoding: .utf8)
        XCTAssertTrue(
            yml.contains("INFOPLIST_KEY_CFBundleDisplayName: AeroSpork"),
            "project.yml must set CFBundleDisplayName, or macOS shows the lowercase bundle name",
        )
        // Guard the reason it cannot simply be PRODUCT_NAME.
        XCTAssertTrue(yml.contains("PRODUCT_NAME: aerospork"), "the bundle on disk must stay lowercase")
    }
}
