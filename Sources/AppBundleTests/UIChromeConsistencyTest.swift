@testable import AppBundle
import XCTest

/// The settings window is seven tabs written at seven different times, and the failure mode is
/// always the same one: a tab needs a small piece of chrome, does not find it, and grows its own.
/// That is how the window ended up with two badges at two paddings, three hand-rolled +/- rows and
/// a status readout whose colour was decided per call site.
///
/// `SettingsChrome.swift` is the answer to that, and these tests are what stops it from decaying
/// back. They are deliberately source-text tests in the same spirit as
/// `PerfInvariantsTest.testHotPathsContainNoUnconditionalPrint`: what they pin is *where a
/// definition is allowed to live*, which is not observable by rendering a view.
final class UIChromeConsistencyTest: XCTestCase {
    private static let chrome = "Sources/AppBundle/ui/SettingsChrome.swift"

    /// Every `.swift` under `ui/` except the shared-chrome file itself.
    private func tabSources() throws -> [(path: String, source: String)] {
        let uiRoot = projectRoot.appending(path: "Sources/AppBundle/ui")
        let files = FileManager.default.enumerator(at: uiRoot, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path } ?? []
        XCTAssertGreaterThan(files.count, 5, "expected to find the settings UI sources")
        return try files.compactMap { url in
            let rel = url.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            if rel == Self.chrome { return nil }
            return (rel, try String(contentsOf: url, encoding: .utf8))
        }
    }

    private func forEachCodeLine(_ body: (String, Int, String) -> Void) throws {
        for (path, source) in try tabSources() {
            for (i, line) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("///") { continue }
                body(path, i + 1, code)
            }
        }
    }

    /// A capsule with a fill is a badge. There is one of those, and it takes a `help:` -- which is
    /// the part a hand-rolled one always forgets, leaving VoiceOver to read a bare word.
    func testNoTabRollsItsOwnBadge() throws {
        try forEachCodeLine { path, line, code in
            XCTAssertFalse(
                code.contains("Capsule()"),
                "\(path):\(line) builds its own capsule badge -- use Badge(_:tone:help:) from SettingsChrome: \(code)",
            )
        }
    }

    /// The symbol test below greps SF Symbol *names*, so a literal `⚠` in a string walked straight
    /// past it -- and did, in the menu bar's config-failure row, the one surface that is always on
    /// screen. CoreText renders those glyphs emoji-style in a menu, next to SF Symbols everywhere
    /// else.
    func testTabsDoNotUseGlyphsAsStatusIcons() throws {
        let glyphs = ["⚠", "✅", "❌", "⛔", "🔴", "🟢", "‼️"]
        try forEachCodeLine { path, line, code in
            for glyph in glyphs {
                XCTAssertFalse(
                    code.contains(glyph),
                    "\(path):\(line) uses \(glyph) as a status icon -- use StatusLabel/Banner: \(code)",
                )
            }
        }
    }

    /// `TextField("com.apple.finder", text:)` reads like it takes a placeholder. It does not -- that
    /// argument is the field's label. Outside a Form macOS happens to draw it like a placeholder,
    /// which is what made the mistake survive; inside a Form, and especially inside
    /// `LabeledContent`, SwiftUI draws it as a second label, squeezes the field to nothing and
    /// spills the text beside it hyphenated across three lines.
    ///
    /// Every text field in the window was written this way. `SettingsField` takes a real `prompt:`,
    /// so the fix is not per-tab vigilance.
    func testTabsDoNotUseATextFieldTitleAsAPlaceholder() throws {
        // The filter box is `.plain` with its own magnifying glass, and the add-mode popover sizes
        // itself; neither wants SettingsField's rounded border. Both are titles that macOS renders
        // as placeholders in a non-Form context, which is legitimate.
        let allowed = ["TextField(\"Filter\"", "TextField(\"mode name, e.g. resize\""]
        try forEachCodeLine { path, line, code in
            guard code.contains("TextField(\""), !code.contains("TextField(\"\",") else { return }
            guard !allowed.contains(where: code.contains) else { return }
            XCTFail(
                "\(path):\(line) passes a placeholder as a TextField title -- that is the label. "
                    + "Use SettingsField(_:prompt:text:) from SettingsChrome: \(code)",
            )
        }
    }

    /// The status symbols are a set, not a palette: red/green is the most confusable pair there is,
    /// so which symbol goes with which meaning is decided once, in `StatusLabel.Kind`.
    func testStatusSymbolsAreNotHardcodedInTabs() throws {
        let owned = ["checkmark.circle", "equal.circle", "exclamationmark.octagon.fill"]
        try forEachCodeLine { path, line, code in
            for symbol in owned {
                XCTAssertFalse(
                    code.contains("\"\(symbol)\""),
                    "\(path):\(line) hardcodes the status symbol \(symbol) -- use StatusLabel/Banner: \(code)",
                )
            }
            // `exclamationmark.triangle.fill` is allowed only via `StatusLabel.Kind`, because the
            // key-conflict row needs composite text that StatusLabel's String API cannot express.
            XCTAssertFalse(
                code.contains("\"exclamationmark.triangle.fill\""),
                "\(path):\(line) hardcodes the warning symbol -- use StatusLabel.Kind.warning: \(code)",
            )
        }
    }

    /// Both badges are the same shape; only the wash differs. Pinning the geometry in one place is
    /// the entire point of the shared component.
    func testBadgeTonesDifferOnlyInTheirFill() throws {
        let source = try String(contentsOf: projectRoot.appending(path: Self.chrome), encoding: .utf8)
        XCTAssertTrue(source.contains(".padding(.horizontal, 6)"), "Badge should keep its 6pt horizontal padding")
        XCTAssertTrue(source.contains(".padding(.vertical, 2)"), "Badge should keep its 2pt vertical padding")
        XCTAssertTrue(source.contains("case .standard: Color.primary.opacity(0.08)"))
        XCTAssertTrue(source.contains("case .muted: Color.secondary.opacity(0.2)"))
    }

    /// The chip is rasterized at 40pt and scaled to the menu bar's ~22pt. At 0.72 the glyphs come
    /// out well above the ~14pt of the clock beside them; 0.62 is what the design system specifies.
    func testMenuBarChipUsesTheDesignSystemFontRatio() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/MenuBarLabel.swift"),
            encoding: .utf8,
        )
        XCTAssertTrue(
            source.contains("size: height * 0.62"),
            "menu bar chip font ratio should be 0.62 to match aerospork-design/components/brand/WorkspaceChips.jsx",
        )
    }
}
