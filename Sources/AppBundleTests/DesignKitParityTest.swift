@testable import AppBundle
import XCTest

/// The design kit under `.claude/skills/aerospork-design/` is a recreation of the shipping SwiftUI,
/// derived from it, and `CLAUDE.md` says it documents the shipping UI rather than proposing a
/// different one. Nothing enforced that, and it drifted twice in three commits: once when the tab
/// strings were corrected to sentence case, and again one commit after that resync when two
/// empty-state strings were rewritten.
///
/// This pins the handful of user-visible strings that have actually drifted. It is deliberately a
/// short explicit list rather than a general diff: the kit is a *recreation*, so most of it is
/// allowed to differ, and a broad comparison would be noise that people learn to ignore.
///
/// When this fails, the fix is to update the kit — not to delete the entry.
final class DesignKitParityTest: XCTestCase {
    private var kitRoot: URL { projectRoot.appending(path: ".claude/skills/aerospork-design") }

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }

    private func readKit(_ relativePath: String) throws -> String {
        try String(contentsOf: kitRoot.appending(path: relativePath), encoding: .utf8)
    }

    /// A phrase the Swift shows the user, and the kit file that must show it too.
    private struct Shared {
        let phrase: String
        let swiftFile: String
        let kitFile: String
    }

    private let shared: [Shared] = [
        .init(phrase: "Add rule",
              swiftFile: "Sources/AppBundle/ui/ConfigurationTabs/WindowRulesTab.swift",
              kitFile: "ui_kits/settings_app/RulesTab.jsx"),
        .init(phrase: "Add assignment",
              swiftFile: "Sources/AppBundle/ui/ConfigurationTabs/WorkspacesMonitorsTab.swift",
              kitFile: "ui_kits/settings_app/MonitorsTab.jsx"),
        .init(phrase: "Startup & behaviour",
              swiftFile: "Sources/AppBundle/ui/ConfigurationTabs/GeneralSettingsTab.swift",
              kitFile: "ui_kits/settings_app/GeneralTab.jsx"),
        .init(phrase: "Pause tiling",
              swiftFile: "Sources/AppBundle/ui/MenuBar.swift",
              kitFile: "ui_kits/menu_bar/MenuBarKit.jsx"),
        .init(phrase: "Non-main",
              swiftFile: "Sources/AppBundle/ui/ConfigurationTabs/WorkspacesMonitorsTab.swift",
              kitFile: "ui_kits/settings_app/MonitorsTab.jsx"),
    ]

    /// Each phrase must still be in the Swift. If it is not, the Swift changed and the entry below
    /// is what tells you the kit needs the same change.
    func testTheSharedPhrasesAreStillInTheSwift() throws {
        for entry in shared {
            let source = try read(entry.swiftFile)
            XCTAssertTrue(
                source.contains(entry.phrase),
                """
                "\(entry.phrase)" is no longer in \(entry.swiftFile). If it was renamed, rename it in
                \(entry.kitFile) too and update this test — the kit is supposed to document what ships.
                """,
            )
        }
    }

    func testTheKitShowsTheSamePhrases() throws {
        for entry in shared {
            let kit = try readKit(entry.kitFile)
            XCTAssertTrue(
                kit.contains(entry.phrase),
                """
                the design kit's \(entry.kitFile) does not show "\(entry.phrase)", which
                \(entry.swiftFile) does. The kit is a recreation of the shipping UI, so it follows the
                Swift rather than the other way round.
                """,
            )
        }
    }

    /// The built bundle is generated from those sources and is what a mock actually loads, so a
    /// stale copy there is the same defect one layer down.
    func testTheBuiltBundleIsNotStale() throws {
        let bundle = try readKit("_ds_bundle.js")
        for phrase in ["Add rule", "Add assignment", "Pause tiling"] {
            XCTAssertTrue(
                bundle.contains(phrase),
                "_ds_bundle.js is stale: it does not contain \"\(phrase)\". Rebuild it from the component sources.",
            )
        }
    }
}
