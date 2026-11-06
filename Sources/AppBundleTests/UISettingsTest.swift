@testable import AppBundle
import AppKit
import Common
import Foundation
import XCTest

/// Logic behind the settings surface that is useful to assert without UI automation: navigation
/// metadata, editor behavior, key notation, tray identity, branding, and the deployment floor.
@MainActor
final class UISettingsTest: XCTestCase {
    // MARK: - Pane navigation

    func testSettingsPaneMetadataIsCompleteAndStable() {
        let panes = ConfigurationWindow.SettingsPane.allCases
        XCTAssertEqual(panes.map(\.rawValue), [
            "general", "gaps", "keys", "monitors", "events", "windowRules", "rawToml",
        ])
        XCTAssertEqual(panes.map(\.title), [
            "General", "Gaps", "Keys", "Monitors", "Events", "Window Rules", "Raw TOML",
        ])
        XCTAssertTrue(panes.allSatisfy { !$0.symbol.isEmpty })
        XCTAssertEqual(Set(panes.map(\.symbol)).count, panes.count)
        for pane in panes {
            // A misspelled or too-new SF Symbol renders a blank toolbar icon, silently. This can
            // only catch a deployment-floor violation when run on the floor OS, but it catches a
            // bad name everywhere.
            XCTAssertNotNil(
                NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil),
                "\(pane.rawValue) pane symbol \"\(pane.symbol)\" is not a resolvable SF Symbol on this OS",
            )
        }
    }

    // MARK: - Key recorder

    /// Every Swift file of the settings UI. Asserts non-empty, so a wrong path cannot make the
    /// source-text invariants below pass vacuously.
    private func uiSources() throws -> [URL] {
        let directory = projectRoot.appending(path: "Sources/AppBundle/ui")
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "no UI sources found at \(directory.path)")
        return files
    }

    private func keyEvent(_ chars: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: keyCode,
        ).orDie("NSEvent.keyEvent returned nil")
    }

    /// Modifier order is not cosmetic: it is the string written into the config, and `ctrl-alt-h`
    /// and `alt-ctrl-h` are two different TOML keys for the same physical shortcut.
    func testRecorderBuildsNotationInCanonicalModifierOrder() {
        assertEquals(KeyNotation.from(event: keyEvent("h", keyCode: 4, [.option, .shift])), "alt-shift-h")
        assertEquals(KeyNotation.from(event: keyEvent("h", keyCode: 4, [.command, .control])), "ctrl-cmd-h")
        assertEquals(KeyNotation.from(event: keyEvent("1", keyCode: 18, [.option])), "alt-1")
    }

    /// Keys with no useful `charactersIgnoringModifiers` have to come from the key code, or the
    /// recorder silently records nothing when you press Tab or an arrow.
    func testRecorderNamesKeysThatHaveNoCharacter() {
        assertEquals(KeyNotation.from(event: keyEvent("", keyCode: 48, [.option])), "alt-tab")
        assertEquals(KeyNotation.from(event: keyEvent("", keyCode: 126)), "up")
        assertEquals(KeyNotation.from(event: keyEvent("[", keyCode: 33, [.option])), "alt-leftSquareBracket")
    }

    /// A modifier-only press must not be captured -- otherwise merely reaching for ⌥⇧H records
    /// nothing useful and closes the recorder before the real key arrives.
    func testRecorderIgnoresPressesWithNoKey() {
        assertNil(KeyNotation.from(event: keyEvent("", keyCode: 999, [.option])))
    }

    func testPrettyRendersModifiersAsGlyphsAndLeavesBareKeysAlone() {
        assertEquals(KeyNotation.pretty("alt-shift-h"), "⌥⇧h")
        assertEquals(KeyNotation.pretty("h"), "h")
        assertEquals(KeyNotation.pretty("ctrl-alt-cmd-space"), "⌃⌥⌘space")
        // An unknown leading token must survive rather than vanish.
        assertEquals(KeyNotation.pretty("hyper-h"), "hyper-h")
    }

    // MARK: - Raw TOML editor

    func testRawTomlSectionNavigationKeepsDocumentOrder() {
        let headers = RawTomlTab.sections(in: """
            title = '[not-a-header]'
            [gaps] # visible section
            inner.horizontal = 8
              [[on-window-detected]]
            ["display]rules"] # a quoted key can contain the closing glyph
            [['literal]key']]
            # [commented-out]
            broken [keys]
            [broken] trailing text
            """)
        XCTAssertEqual(headers.map(\.line), [2, 4, 5, 6])
        XCTAssertEqual(headers.map(\.label), [
            "[gaps]", "[[on-window-detected]]", "[\"display]rules\"]", "[['literal]key']]",
        ])
    }

    func testRawTomlHighlightingIsRestrainedAndQuoteAware() {
        let textView = NSTextView()
        textView.string = "[gaps]\nkey = 'a # value' # comment\n"
        TomlSyntaxHighlighter.apply(to: textView)
        let source = textView.string as NSString

        func color(at token: String, occurrence: Int = 1) -> NSColor? {
            var search = NSRange(location: 0, length: source.length)
            var result = NSRange(location: NSNotFound, length: 0)
            for _ in 0 ..< occurrence {
                result = source.range(of: token, options: [], range: search)
                guard result.location != NSNotFound else { return nil }
                let next = NSMaxRange(result)
                search = NSRange(location: next, length: source.length - next)
            }
            return textView.textStorage?.attribute(.foregroundColor, at: result.location, effectiveRange: nil) as? NSColor
        }

        XCTAssertEqual(color(at: "[gaps]"), NSColor.controlAccentColor)
        XCTAssertEqual(color(at: "key"), NSColor.labelColor)
        XCTAssertEqual(color(at: "#", occurrence: 1), NSColor.secondaryLabelColor, "a hash inside a string is not a comment")
        XCTAssertEqual(color(at: "#", occurrence: 2), NSColor.tertiaryLabelColor)
    }

    func testRawTomlHighlightingIgnoresCommentsInsideMultilineStrings() {
        let textView = NSTextView()
        textView.string = "value = \"\"\"first # value\nstill # value\n\"\"\" # comment\n"
        TomlSyntaxHighlighter.apply(to: textView)
        let source = textView.string as NSString
        var search = NSRange(location: 0, length: source.length)
        var colors: [NSColor?] = []
        for _ in 0 ..< 3 {
            let hash = source.range(of: "#", options: [], range: search)
            XCTAssertNotEqual(hash.location, NSNotFound)
            colors.append(textView.textStorage?.attribute(
                .foregroundColor,
                at: hash.location,
                effectiveRange: nil,
            ) as? NSColor)
            let next = NSMaxRange(hash)
            search = NSRange(location: next, length: source.length - next)
        }
        XCTAssertEqual(colors[0], NSColor.secondaryLabelColor)
        XCTAssertEqual(colors[1], NSColor.secondaryLabelColor)
        XCTAssertEqual(colors[2], NSColor.tertiaryLabelColor)
    }

    // MARK: - Guided controls

    func testGuidedWindowRuleActionsParseAndComposeWithoutLosingIntent() {
        let action = parseGuidedWindowAction("move-node-to-workspace 3 ; layout floating")
        XCTAssertEqual(action.layout, .floating)
        XCTAssertEqual(action.workspace, "3")
        XCTAssertFalse(action.isCustom)
        XCTAssertEqual(composeGuidedWindowAction(action), "layout floating ; move-node-to-workspace 3")

        let custom = parseGuidedWindowAction("layout tiling ; exec-and-forget open -a Finder")
        XCTAssertEqual(custom.layout, .tiling)
        XCTAssertTrue(custom.isCustom, "guided controls must not overwrite an unrepresentable command")
        XCTAssertEqual(
            composeGuidedWindowAction(custom), "layout tiling ; exec-and-forget open -a Finder",
            "the unrepresentable part must survive composition verbatim, not just flag itself",
        )
    }

    func testLinkedGapSettersUpdateEveryEdgeAndAvoidNoOpSaves() {
        let vm = ConfigurationViewModel()
        defer { vm.cancelPendingAutoSave() }

        vm.settings.gaps.innerHorizontal = 4
        vm.settings.gaps.innerVertical = 9
        vm.setInnerGaps(12)
        XCTAssertEqual([vm.settings.gaps.innerHorizontal, vm.settings.gaps.innerVertical], [12, 12])
        XCTAssertTrue(vm.hasUnsavedChanges)

        vm.markLoaded()
        vm.setInnerGaps(12)
        XCTAssertFalse(vm.hasUnsavedChanges, "setting the already-linked value should not schedule a save")

        vm.settings.gaps.outerTop = 1
        vm.settings.gaps.outerBottom = 2
        vm.settings.gaps.outerLeft = 3
        vm.settings.gaps.outerRight = 4
        vm.setOuterGaps(16)
        XCTAssertEqual(
            [vm.settings.gaps.outerTop, vm.settings.gaps.outerBottom, vm.settings.gaps.outerLeft, vm.settings.gaps.outerRight],
            [16, 16, 16, 16],
        )
        XCTAssertTrue(vm.hasUnsavedChanges)

        vm.markLoaded()
        vm.setOuterGaps(16)
        XCTAssertFalse(vm.hasUnsavedChanges, "setting the already-linked value should not schedule a save")
    }

    // MARK: - Monitor pinning

    func testUnpinnedDefinedWorkspacesAreDefinedMinusAssigned() {
        let vm = ConfigurationViewModel()
        vm.definedWorkspaces = ["1", "2", "2", "3"]
        vm.settings.assignments = [.init(workspace: "2", monitor: "main")]
        XCTAssertEqual(vm.unpinnedDefinedWorkspaces, ["1", "3"], "dedupe, config order, assigned excluded")
    }

    private static func twoMonitors() -> [ConfigurationViewModel.MonitorRow] {
        [
            ConfigurationViewModel.MonitorRow(
                name: "DELL U3223QE (1)",
                resolution: "3840 × 2160",
                uuid: "AAAAAAAA-0000-4000-8000-000000000001",
                position: 1,
                isMain: true,
                rect: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            ),
            ConfigurationViewModel.MonitorRow(
                name: "LG HDR 4K",
                resolution: "3840 × 2160",
                uuid: nil,
                position: 2,
                isMain: false,
                rect: CGRect(x: 2560, y: 0, width: 1920, height: 1080),
            ),
        ]
    }

    /// The detail strip's chips must resolve every token shape this editor itself writes, with
    /// the runtime's semantics: a name is a case-insensitive substring match, `secondary` only
    /// means anything with exactly two monitors, and a metacharacter regex resolves to nothing
    /// (the `complex` badge owns those).
    func testAssignmentsPinnedToAMonitorResolveEveryEditorToken() {
        let vm = ConfigurationViewModel()
        vm.liveMonitors = Self.twoMonitors()
        let dell = vm.liveMonitors[0]
        let lg = vm.liveMonitors[1]
        vm.settings.assignments = [
            .init(workspace: "a", monitor: "main"),
            .init(workspace: "b", monitor: "secondary"),
            .init(workspace: "c", monitor: "1"),
            .init(workspace: "d", monitor: "lg hdr"),
            .init(workspace: "e", monitor: dell.uuid!),
            .init(workspace: "f", monitor: "dell.*"),
        ]

        XCTAssertEqual(vm.assignments(pinnedTo: dell).map(\.workspace), ["a", "c", "e"])
        XCTAssertEqual(vm.assignments(pinnedTo: lg).map(\.workspace), ["b", "d"])
        XCTAssertNil(vm.monitorRow(forToken: "dell.*"), "a metacharacter regex must not fake-resolve")

        // `secondary` is only defined for exactly two monitors -- with three, its chip must
        // vanish rather than lie.
        vm.liveMonitors.append(ConfigurationViewModel.MonitorRow(
            name: "Sidecar",
            resolution: "2224 × 1668",
            uuid: nil,
            position: 3,
            isMain: false,
            rect: CGRect(x: -2224, y: 0, width: 2224, height: 1668),
        ))
        XCTAssertNil(vm.monitorRow(forToken: "secondary"))
    }

    func testPinUnpinRoundTripThroughTheMenuFlow() {
        let vm = ConfigurationViewModel()
        defer { vm.cancelPendingAutoSave() }
        vm.liveMonitors = Self.twoMonitors()
        let dell = vm.liveMonitors[0]
        vm.definedWorkspaces = ["1", "2", "3"]

        let id = vm.setAssignment(workspace: "3", monitorToken: dell.uuid!)
        XCTAssertEqual(vm.assignments(pinnedTo: dell).map(\.id), [id])
        XCTAssertEqual(vm.unpinnedDefinedWorkspaces, ["1", "2"])

        vm.markLoaded()
        vm.setAssignment(workspace: "3", monitorToken: dell.uuid!)
        XCTAssertFalse(vm.hasUnsavedChanges, "re-pinning to the same monitor must not schedule a save")

        vm.removeAssignment(id: id)
        vm.cancelPendingAutoSave()
        XCTAssertEqual(vm.unpinnedDefinedWorkspaces, ["1", "2", "3"], "unpinning returns the workspace to the menu")

        let emptyRow = vm.addAssignment(monitorToken: dell.uuid!)
        XCTAssertEqual(
            vm.settings.assignments.first { $0.id == emptyRow }?.monitor, dell.uuid!,
            "Other… must create the row already pinned to the selected monitor",
        )
    }

    // MARK: - Menu bar label

    /// The mode chip and a workspace chip can carry the same text (`[R]` mode next to workspace
    /// `R`). `ForEach` needs those to be distinct or one of them disappears from the menu bar.
    func testTrayItemIdSeparatesModesFromWorkspaces() {
        let mode = TrayItem(type: .mode, name: "R", isActive: true)
        let workspace = TrayItem(type: .workspace, name: "R", isActive: true)
        XCTAssertNotEqual(mode.id, workspace.id)
        assertEquals(Set([mode, workspace]).count, 2)
    }

    // MARK: - Branding

    /// The fork's own name, enforced over the settings UI. `BrandingTest` scans the rest of the
    /// tree and lists `Sources/AppBundle/ui` as the one directory still out of scope; this closes
    /// it, and keeps it closed.
    ///
    /// No exceptions. There used to be one -- the settings window had to keep *reading*
    /// `during-aerospace-startup`, because `parseOnWindowDetected` still accepted that matcher key
    /// with a deprecation warning, and reading only the new spelling would have dropped the matcher
    /// on the first GUI edit. The parser no longer accepts it, so a config carrying it does not load
    /// and the read was dead code. Both are gone.
    func testSettingsUiDoesNotMentionTheUpstreamProductName() throws {
        var offenders: [String] = []
        for file in try uiSources() {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.lowercased().contains("aerospace")
            {
                offenders.append("\(file.lastPathComponent):\(i + 1): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(offenders, [], "the product is AeroSpork:\n" + offenders.joined(separator: "\n"))
    }

    // MARK: - Deployment floor

    /// `Package.swift` declares macOS 13. APIs newer than that do not fail to build against a newer
    /// SDK -- SwiftUI modifiers are unavailable at *compile* time only if unguarded, and SF Symbols
    /// introduced later simply render as an empty box at runtime. Neither is visible from here, so
    /// the floor is enforced by reading the source.
    func testSettingsUiStaysWithinTheMacOS13Floor() throws {
        // token -> why it is banned
        let banned = [
            "ContentUnavailableView(": "macOS 14; use ContentUnavailableViewCompat",
            ".scrollBounceBehavior": "macOS 14",
            "alternatingRowBackgrounds": "macOS 14",
            ".accessoryBar": "macOS 14 button style",
            ".extraLarge": "macOS 14 control size",
            "MeshGradient": "macOS 15",
            "square.resize": "SF Symbols 5 (macOS 14)",
            "arrow.trianglehead": "SF Symbols 6 (macOS 15)",
        ]
        let files = try uiSources()

        // Anything genuinely newer has to sit behind `#available`, as `MenuBarLabel` does for
        // `ImageRenderer` -- these tokens have no macOS 13 rendering at all, guarded or not.
        for file in files {
            // Comments are stripped first: the whole point of a comment like "square.resize is SF
            // Symbols 5, so we use rectangle.split.3x3" is to record the rule, not break it.
            // TRADEOFF: naive `//` split, so a banned token inside a string containing `//` would
            // be missed. Upgrade path: none needed until a symbol name lives inside a URL.
            let source = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.components(separatedBy: "//").first ?? "" }
                .joined(separator: "\n")
            for (token, reason) in banned where source.contains(token) {
                XCTFail("\(file.lastPathComponent) uses \(token) — \(reason)")
            }
        }
    }
}
