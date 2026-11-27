@testable import AppBundle
import XCTest

/// The settings window is seven panes written at seven different times, and the failure mode is
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

    /// A symbol-only `Button` invented in a pane skips `IconButton`'s one-string help/accessibility
    /// contract -- the exact route by which the window once grew three remove buttons. Scoped to
    /// bare `Button`s on one line; a `Menu` label is a different shape this rule does not claim.
    func testTabsUseIconButtonForSymbolOnlyButtons() throws {
        try forEachCodeLine { path, line, code in
            XCTAssertFalse(
                code.contains("label: { Image(systemName:"),
                "\(path):\(line) hand-rolls a symbol-only button -- use IconButton from SettingsChrome: \(code)",
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

    /// `testNoTabRollsItsOwnBadge` only catches a hand-rolled `Capsule()`; it missed a bare `Text`
    /// used to mark the exact same "this row is generated" concept `Badge` already exists for --
    /// same file, two implementations, one with no `.help()` and no accessibility label.
    func testNoTabMarksOriginWithBareText() throws {
        try forEachCodeLine { path, line, code in
            XCTAssertFalse(
                code.contains("Text(\"(generated)\")"),
                "\(path):\(line) marks a row's origin with bare text -- use Badge(_:tone:help:) from SettingsChrome: \(code)",
            )
        }
    }

    /// Every control in `SettingsChrome.swift` is shared. The code editor is not: only Raw TOML has one,
    /// so it sits with that pane, and the chrome file stays small enough to be read as a catalogue.
    func testTheCodeEditorLivesInTheRawTomlPane() throws {
        let chrome = try String(contentsOf: projectRoot.appending(path: Self.chrome), encoding: .utf8)
        XCTAssertFalse(chrome.contains("struct CodeEditor"))
        let pane = try String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/ConfigurationTabs/RawTomlTab.swift"), encoding: .utf8)
        XCTAssertTrue(pane.contains("struct CodeEditor"))
        XCTAssertTrue(pane.contains("enum TomlSyntaxHighlighter"))
    }

    /// The window's error strip is the only place a failed Apply or Restore, or the changed-on-disk
    /// conflict, is shown. Hiding it on Raw TOML made Apply look like it did nothing there. The
    /// `Settings` scene cannot be rendered headlessly, so this reads the source.
    func testTheErrorStripShowsOnEveryPane() throws {
        let source = withoutComments(try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/ConfigurationWindow.swift"),
            encoding: .utf8,
        ))
        let strip = try XCTUnwrap(
            source.split(separator: "\n").first { $0.contains("if let error = viewModel.errorMessage") },
            "the error strip moved: update this test",
        )
        XCTAssertFalse(strip.contains("selectedPane"), "the error strip is hidden on some pane: \(strip)")
    }

    /// The window locks the structured panes on `hasPendingRawEdits`, which publishes only when the
    /// buffer's edited state flips. Reading the buffer or `rawTomlEdited` would make the window observe
    /// every keystroke and re-run all seven pane bodies again.
    func testTheWindowDoesNotReadTheRawBuffer() throws {
        let source = withoutComments(try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/ConfigurationWindow.swift"),
            encoding: .utf8,
        ))
        for read in ["viewModel.raw\\b", "viewModel.rawToml\\b", "rawTomlEdited"] {
            XCTAssertNil(source.range(of: read, options: .regularExpression), "ConfigurationWindow reads \(read)")
        }
        XCTAssertTrue(source.contains(".disabled(viewModel.hasPendingRawEdits)"), "the structured panes lost their lock")
    }

    /// The product voice keeps the em dash for the rare interruption nothing else handles
    /// (`.claude/skills/aerospork-design/readme.md`), and the panes had 17 of them in their copy. A
    /// colon, a comma or a full stop says each of these better. Comments are not copy.
    func testUiCopyHasNoEmDashes() throws {
        var offenders: [String] = []
        try forEachCodeLine { path, line, code in
            // The odd segments between quotes are the string literals on the line.
            let literals = code.split(separator: "\"", omittingEmptySubsequences: false).enumerated().filter { $0.offset % 2 == 1 }
            if literals.contains(where: { $0.element.contains("—") }) { offenders.append("\(path):\(line)") }
        }
        XCTAssertEqual(offenders, [], "rewrite with a colon, a comma or a full stop")
    }

    /// A debug build has no feed, so an update control there is a permanent dead control. The test
    /// process runs with the updater disabled, so a render cannot see the gate: this reads the source.
    func testUpdateControlsAreGatedOnTheUpdaterBeingEnabled() throws {
        let source = withoutComments(try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/ConfigurationTabs/GeneralSettingsTab.swift"),
            encoding: .utf8,
        ))
        let gate = try XCTUnwrap(source.range(of: "if Updater.shared.isEnabled {"), "the update gate moved: update this test")
        // The gate's block, up to its matching brace.
        var depth = 1
        let end = source[gate.upperBound...].firstIndex { char in
            if char == "{" { depth += 1 } else if char == "}" { depth -= 1 }
            return depth == 0
        } ?? source.endIndex
        let gated = source[gate.upperBound ..< end]
        for control in ["Toggle(\"Automatically check for updates\"", "Button(\"Check for updates…\")"] {
            XCTAssertTrue(gated.contains(control), "\(control) is missing from the isEnabled gate")
            XCTAssertEqual(source.components(separatedBy: control).count, 2, "\(control) also appears outside the gate")
        }
    }

    /// Reload replaces the Raw TOML buffer with the file, which threw away unapplied typing with no
    /// warning. A headless render cannot tell whether a button is disabled, so this reads the source.
    func testRawTomlReloadIsDisabledWhileThereAreUnappliedEdits() throws {
        let source = withoutComments(try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/ui/ConfigurationTabs/RawTomlTab.swift"),
            encoding: .utf8,
        ))
        let reload = try XCTUnwrap(source.range(of: "Button(\"Reload\")"), "the Reload button moved: update this test")
        let modifiers = source[reload.upperBound...].prefix(600)
        XCTAssertTrue(modifiers.contains(".disabled(viewModel.rawTomlEdited)"), String(modifiers))
        XCTAssertTrue(modifiers.contains("Apply or revert your edits first"), String(modifiers))
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

    /// Icon-only controls get the 24pt hit shape from the one place that defines it, and that shape
    /// must not change layout: a `frame(minWidth:)` there made the Keys filter pill jump when its
    /// clear button appeared. A headless render cannot hit-test, so this reads the source.
    func testIconControlsGetTheHitTargetWithoutGrowingLayout() throws {
        for name in ["struct IconButton", "struct CopyButton"] {
            let body = try sourceBody(name, in: Self.chrome)
            XCTAssertTrue(body.contains(".settingsHitTarget()"), "\(name) has no settingsHitTarget")
        }
        let hitTarget = try sourceBody("func settingsHitTarget()", in: Self.chrome)
        XCTAssertFalse(hitTarget.contains("frame("), "settingsHitTarget must not change layout: \(hitTarget)")
        let actionBar = try sourceBody("struct ListActionBar", in: Self.chrome)
        XCTAssertFalse(
            actionBar.replacingOccurrences(of: "IconButton(", with: "").contains("Button"),
            "ListActionBar's +/- should be IconButtons: \(actionBar)",
        )
    }

    /// The window's error strip was a hand-made `Banner`: its tint, its own padding, and no way to
    /// offer the recovery. A banner wash outside the chrome file is that copy growing back.
    func testNoPaneMakesItsOwnBanner() throws {
        let wash = try Regex(#"Banner\.Kind\.\w+\.tint\.opacity\("#)
        try forEachCodeLine { path, line, code in
            XCTAssertFalse(code.contains(wash), "\(path):\(line) paints its own banner -- use Banner from SettingsChrome: \(code)")
        }
    }

    /// macOS buttons do not use a pointing hand, and a hovered view torn down before its pop left the
    /// cursor stack unbalanced.
    func testNoPaneUsesAPointingHandCursor() throws {
        try forEachCodeLine { path, line, code in
            XCTAssertFalse(code.contains("NSCursor.pointingHand.push"), "\(path):\(line): \(code)")
        }
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

    /// A section footer is a `SettingsHint`. A plain `Text` there comes out right-aligned and at full
    /// brightness, and only in a real settings window, so no render in a test ever showed it.
    func testASectionFooterIsAHint() throws {
        let folder = projectRoot.appending(path: "Sources/AppBundle/ui/ConfigurationTabs")
        for file in try FileManager.default.contentsOfDirectory(atPath: folder.path()) where file.hasSuffix(".swift") {
            let source = withoutComments(try String(contentsOf: folder.appending(path: file), encoding: .utf8))
            var rest = source[...]
            while let footer = rest.range(of: "footer: {") {
                var depth = 1
                var end = footer.upperBound
                var inString = false
                while depth > 0, end < rest.endIndex {
                    switch rest[end] {
                        case "\"": inString.toggle()
                        case "{" where !inString: depth += 1
                        case "}" where !inString: depth -= 1
                        default: break
                    }
                    end = rest.index(after: end)
                }
                XCTAssertFalse(rest[footer.upperBound ..< end].contains(" Text("), "\(file): \(rest[footer.upperBound ..< end].prefix(80))")
                rest = rest[end...]
            }
        }
    }
}
