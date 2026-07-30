@testable import AppBundle
import Common
import XCTest

@MainActor
final class ConfigTest: XCTestCase {
    func parseConfigForTest(_ rawToml: String) -> (Config, [TomlParseError]) {
        switch parseConfig(rawToml) {
            case .success(let config):
                return (config, [])
            case .failure(let errors):
                return (Config(), errors)
        }
    }

    func testQueryCantBeUsedInConfig() {
        let (_, errors) = parseConfigForTest(
            """
            [mode.main.binding]
                alt-a = 'list-apps'
            """,
        )
        XCTAssertTrue(errors.descriptions.singleOrNil()?.contains("cannot be used in config") == true)
    }

    func testDropBindings() {
        let (config, errors) = parseConfigForTest(
            """
            mode.main = {}
            """,
        )
        assertEquals(errors, [])
        XCTAssertTrue(config.modes[mainModeId]?.bindings.isEmpty == true)
    }

    func testParseMode() {
        let (config, errors) = parseConfigForTest(
            """
            [mode.main.binding]
                alt-h = 'focus left'
            """,
        )
        assertEquals(errors, [])
        let binding = HotkeyBinding(.option, .h, [FocusCommand.new(direction: .left)])
        assertEquals(
            config.modes[mainModeId],
            Mode(name: nil, bindings: [binding.descriptionWithKeyCode: binding]),
        )
    }

    func testModesMustContainDefaultModeError() {
        let (config, errors) = parseConfigForTest(
            """
            [mode.foo.binding]
                alt-h = 'focus left'
            """,
        )
        assertEquals(
            errors.descriptions,
            ["mode: Please specify \'main\' mode"],
        )
        assertEquals(config.modes[mainModeId], nil)
    }

    func testHotkeyParseError() {
        let (_, errors) = parseConfigForTest(
            """
            [mode.main.binding]
                alt-hh = 'focus left'
                aalt-j = 'focus down'
                alt-k = 'focus up'
            """,
        )
        assertEquals(
            errors.descriptions,
            [
                "mode.main.binding.aalt-j: Can\'t parse modifiers in \'aalt-j\' binding",
                "mode.main.binding.alt-hh: Can\'t parse the key in \'alt-hh\' binding",
            ],
        )
        /*let binding = HotkeyBinding(.option, .k, [FocusCommand.new(direction: .up)])
         assertEquals(
             config.modes[mainModeId],
             Mode(name: nil, bindings: [binding.descriptionWithKeyCode: binding]),
         )*/
    }

    func testPermanentWorkspaceNames() {
        let (config, errors) = parseConfigForTest(
            """
            [mode.main.binding]
                alt-1 = 'workspace 1'
                alt-2 = 'workspace 2'
                alt-3 = ['workspace 3']
                alt-4 = ['workspace 4', 'focus left']
            """,
        )
        assertEquals(errors.descriptions, [])
        assertEquals(config.preservedWorkspaceNames.sorted(), ["1", "2", "3", "4"])
    }

    func testUnknownTopLevelKeyParseError() {
        let (_, errors) = parseConfigForTest(
            """
            unknownKey = true
            enable-normalization-flatten-containers = false
            """,
        )
        assertEquals(
            errors.descriptions,
            ["unknownKey: Unknown top-level key"],
        )
        // assertEquals(config.enableNormalizationFlattenContainers, false)
    }

    func testUnknownKeyParseError() {
        let (_, errors) = parseConfigForTest(
            """
            enable-normalization-flatten-containers = false
            [gaps]
                unknownKey = true
            """,
        )
        assertEquals(
            errors.descriptions,
            ["gaps.unknownKey: Unknown key"],
        )
        // assertEquals(config.enableNormalizationFlattenContainers, false)
    }

    /// Deprecated, but no longer a *lie*: the value now reaches `config`, where `focus.swift`
    /// already had a consumer that only `[]` could ever reach.
    func testExecOnWorkspaceChangeIsHonouredAndWarns() {
        var warnings: [TomlParseError] = []
        let result = parseConfig("exec-on-workspace-change = ['/bin/true', 'x']", warnings: &warnings)
        assertEquals(try? result.get().execOnWorkspaceChange, ["/bin/true", "x"])
        assertEquals(warnings.descriptions, [
            "exec-on-workspace-change: Deprecated: exec-on-workspace-change is deprecated. Please use on-focused-workspace-changed with exec-and-forget instead.",
        ])
    }

    func testExecOnWorkspaceChangeEmpty() {
        let (config, errors) = parseConfigForTest(
            """
            exec-on-workspace-change = []
            """,
        )
        assertEquals(errors, [])
        assertEquals(config.execOnWorkspaceChange, [])
    }

    /// Accepted so the config still loads, and reported so the key is not silently doing nothing.
    func testAfterLoginCommandWarnsAndDoesNotFail() {
        var warnings: [TomlParseError] = []
        let result = parseConfig("after-login-command = ['workspace 1']", warnings: &warnings)
        XCTAssertNotNil(try? result.get(), "one deprecated key must not cost the user their config")
        assertEquals(warnings.descriptions, [
            "after-login-command: Deprecated: after-login-command is deprecated and does nothing. Use after-startup-command.",
        ])
    }

    func testTypeMismatch() {
        let (_, errors) = parseConfigForTest(
            """
            enable-normalization-flatten-containers = 'true'
            """,
        )
        assertEquals(
            errors.descriptions,
            ["enable-normalization-flatten-containers: Expected type is \'bool\'. But actual type is \'string\'"],
        )
    }

    func testTomlParseError() {
        let (_, errors) = parseConfigForTest("true")
        assertEquals(
            errors.descriptions,
            ["Error while parsing key-value pair: encountered end-of-file (at line 1, column 5)"],
        )
    }

    func testMoveWorkspaceToMonitorCommandParsing() {
        XCTAssertTrue(parseCommand("move-workspace-to-monitor --wrap-around next").cmdOrNil is MoveWorkspaceToMonitorCommand)
        XCTAssertTrue(parseCommand("move-workspace-to-display --wrap-around next").cmdOrNil is MoveWorkspaceToMonitorCommand)
    }

    /// `on-focused-workspace-changed` was commented out in the parser, so it was an "Unknown
    /// top-level key" error rather than a working hook. Without it, a workspace switch within one
    /// monitor fires no callback at all -- `on-focused-monitor-changed` only fires when the monitor
    /// changes, which is why mouse-follow silently did nothing for same-monitor switches.
    func testParseOnFocusedWorkspaceChanged() {
        let (config, errors) = parseConfigForTest(
            """
            on-focused-workspace-changed = ['move-mouse window-lazy-center']
            """,
        )
        assertEquals(errors, [])
        assertEquals(config.onFocusedWorkspaceChanged.count, 1)
        XCTAssertTrue(config.onFocusedWorkspaceChanged.first is MoveMouseCommand)
    }

    func testParseTiles() {
        let command = parseCommand("layout tiles h_tiles v_tiles list h_list v_list").cmdOrNil
        XCTAssertTrue(command is LayoutCommand)
        assertEquals((command as! LayoutCommand).args.toggleBetween.val, [.tiles, .h_tiles, .v_tiles, .tiles, .h_tiles, .v_tiles])

        guard case .help = parseCommand("layout tiles -h") else {
            XCTFail()
            return
        }
    }

    func testSplitCommandAndFlattenContainersNormalization() {
        let (_, errors) = parseConfigForTest(
            """
            enable-normalization-flatten-containers = true
            [mode.main.binding]
            [mode.foo.binding]
                alt-s = 'split horizontal'
            """,
        )
        assertEquals(
            ["""
                The config contains:
                1. usage of 'split' command
                2. enable-normalization-flatten-containers = true
                These two settings don't play nicely together. 'split' command has no effect when enable-normalization-flatten-containers is disabled.

                My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
                """],
            errors.descriptions,
        )
    }

    func testParseWorkspaceToMonitorAssignment() {
        let (_, errors) = parseConfigForTest(
            """
            [workspace-to-monitor-force-assignment]
                workspace_name_1 = 1                            # Sequence number of the monitor (from left to right, 1-based indexing)
                workspace_name_2 = 'main'                       # main monitor
                workspace_name_3 = 'secondary'                  # non-main monitor (in case when there are only two monitors)
                workspace_name_4 = 'built-in'                   # case insensitive regex substring
                workspace_name_5 = '^built-in retina display$'  # case insensitive regex match
                workspace_name_6 = ['secondary', 1]             # you can specify multiple patterns. The first matching pattern will be used
                7 = "foo"
                w7 = ['', 'main']
                w8 = 0
                workspace_name_x = '2'                          # Sequence number of the monitor (from left to right, 1-based indexing)
            """,
        )
        /*assertEquals(
             parsed.workspaceToMonitorForceAssignment,
             [
                 "workspace_name_1": [.sequenceNumber(1)],
                 "workspace_name_2": [.main],
                 "workspace_name_3": [.secondary],
                 "workspace_name_4": [.pattern("built-in")!],
                 "workspace_name_5": [.pattern("^built-in retina display$")!],
                 "workspace_name_6": [.secondary, .sequenceNumber(1)],
                 "workspace_name_x": [.sequenceNumber(2)],
                 "7": [.pattern("foo")!],
                 "w7": [.main],
                 "w8": [],
             ],
         )*/
        assertEquals([
            "workspace-to-monitor-force-assignment.w7[0]: Empty string is an illegal monitor description",
            "workspace-to-monitor-force-assignment.w8: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal",
        ], errors.descriptions)
        assertEquals([:], defaultConfig.workspaceToMonitorForceAssignment)
    }

    /// DisplayLink: pin a workspace to a specific panel by its stable UUID.
    func testParseWorkspaceToMonitorFingerprintUuid() {
        let (parsed, errors) = parseConfigForTest(
            """
            [workspace-to-monitor-force-assignment]
                dock = { fingerprint = { uuid = "BBBBBBBB-0000-4000-8000-000000000002" } }
                ext = { fingerprint = { vendor = "0x1234", model = "0x5678" } }
            """,
        )
        assertEquals([], errors.descriptions)
        assertEquals(
            [MonitorDescription.fingerprint(MonitorFingerprintPatternData(displayUUID: "BBBBBBBB-0000-4000-8000-000000000002"))],
            parsed.workspaceToMonitorForceAssignment["dock"],
        )
        assertEquals(
            [MonitorDescription.fingerprint(MonitorFingerprintPatternData(vendorID: 0x1234, modelID: 0x5678))],
            parsed.workspaceToMonitorForceAssignment["ext"],
        )
    }

    func testParseWorkspaceToMonitorFingerprintRejectsUnknownKey() {
        let (_, errors) = parseConfigForTest(
            """
            [workspace-to-monitor-force-assignment]
                x = { fingerprint = { bogus = "y" } }
            """,
        )
        assertTrue(errors.descriptions.contains { $0.contains("bogus") })
    }

    func testParseOnWindowDetected() {
        let (_, errors) = parseConfigForTest(
            """
            [[on-window-detected]]
                check-further-callbacks = true
                run = ['layout floating', 'move-node-to-workspace W']
            [[on-window-detected]]
                if.app-id = 'com.apple.systempreferences'
                run = []
            [[on-window-detected]]
            [[on-window-detected]]
                run = ['move-node-to-workspace S', 'layout tiling']
            [[on-window-detected]]
                run = ['move-node-to-workspace S', 'move-node-to-workspace W']
            [[on-window-detected]]
                run = ['move-node-to-workspace S', 'layout h_tiles']
            """,
        )
        /*assertEquals(parsed.onWindowDetected, [
             WindowDetectedCallback(
                 matcher: WindowDetectedCallbackMatcher(
                     appId: nil,
                     appNameRegexSubstring: nil,
                     windowTitleRegexSubstring: nil,
                 ),
                 checkFurtherCallbacks: true,
                 rawRun: [
                     LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.floating])),
                     MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "W")),
                 ],
             ),
             WindowDetectedCallback(
                 matcher: WindowDetectedCallbackMatcher(
                     appId: "com.apple.systempreferences",
                     appNameRegexSubstring: nil,
                     windowTitleRegexSubstring: nil,
                 ),
                 checkFurtherCallbacks: false,
                 rawRun: [],
             ),
         ])*/

        assertEquals(errors.descriptions, [
            "on-window-detected[2]: \'run\' is mandatory key",
            "on-window-detected[3]: For now, \'move-node-to-workspace\' must be the latest instruction in the callback (otherwise it\'s error-prone). Please report your use cases to https://github.com/wbsmolen/aerospork/issues/20",
            "on-window-detected[4]: For now, \'move-node-to-workspace\' can be mentioned only once in \'run\' callback. Please report your use cases to https://github.com/wbsmolen/aerospork/issues/20",
            "on-window-detected[5]: For now, \'layout floating\', \'layout tiling\' and \'move-node-to-workspace\' are the only commands that are supported in \'on-window-detected\'. Please report your use cases to https://github.com/wbsmolen/aerospork/issues/20",
            "on-window-detected[5]: For now, \'move-node-to-workspace\' must be the latest instruction in the callback (otherwise it\'s error-prone). Please report your use cases to https://github.com/wbsmolen/aerospork/issues/20",
        ])
    }

    func testParseOnWindowDetectedRegex() {
        let (config, errors) = parseConfigForTest(
            """
            [[on-window-detected]]
                if.app-name-regex-substring = '^system settings$'
                run = []
            """,
        )
        XCTAssertTrue(config.onWindowDetected.singleOrNil()!.matcher.appNameRegexSubstring != nil)
        assertEquals(errors, [])
    }

    func testRegex() {
        var devNull: [String] = []
        XCTAssertTrue("System Settings".contains(parseCaseInsensitiveRegex("settings").getOrNil(appendErrorTo: &devNull)!))
        XCTAssertTrue(!"System Settings".contains(parseCaseInsensitiveRegex("^settings^").getOrNil(appendErrorTo: &devNull)!))
    }

    func testParseGaps() {
        let (config, errors1) = parseConfigForTest(
            """
            [gaps]
                inner.horizontal = 10
                inner.vertical = [{ monitor."main" = 1 }, { monitor."secondary" = 2 }, 5]
                outer.left = 12
                outer.bottom = 13
                outer.top = [{ monitor."built-in" = 3 }, { monitor."secondary" = 4 }, 6]
                outer.right = [{ monitor.2 = 7 }, 8]
            """,
        )
        assertEquals(errors1, [])
        assertEquals(
            config.gaps,
            Gaps(
                inner: .init(
                    vertical: .perMonitor(
                        [PerMonitorValue(description: .main, value: 1), PerMonitorValue(description: .secondary, value: 2)],
                        default: 5,
                    ),
                    horizontal: .constant(10),
                ),
                outer: .init(
                    left: .constant(12),
                    bottom: .constant(13),
                    top: .perMonitor(
                        [
                            PerMonitorValue(description: .pattern("built-in")!, value: 3),
                            PerMonitorValue(description: .secondary, value: 4),
                        ],
                        default: 6,
                    ),
                    right: .perMonitor([PerMonitorValue(description: .sequenceNumber(2), value: 7)], default: 8),
                ),
            ),
        )

        let (_, errors2) = parseConfigForTest(
            """
            [gaps]
                inner.horizontal = [true]
                inner.vertical = [{ foo.main = 1 }, { monitor = { foo = 2, bar = 3 } }, 1]
            """,
        )
        assertEquals(errors2.descriptions, [
            "gaps.inner.horizontal: The last item in the array must be of type Int",
            "gaps.inner.vertical[0]: The table is expected to have a single key \'monitor\'",
            "gaps.inner.vertical[1].monitor: The table is expected to have a single key",
        ])
    }

    /// Regression guard: the writer once interpolated `DynamicConfigValue` directly, emitting
    /// `horizontal = constant(0)` -- not valid TOML, so the GUI corrupted every config it saved and
    /// the app could no longer load it. Values are non-zero on purpose: a zero-valued case reads the
    /// same either way and would pass against the broken writer.
    func testWriterRoundTripsGaps() {
        let vm = ConfigurationViewModel()
        vm.innerGapsHorizontal = 10
        vm.innerGapsVertical = 11
        vm.outerGapsTop = 12
        vm.outerGapsBottom = 13
        vm.outerGapsLeft = 14
        vm.outerGapsRight = 15

        var lines: [String] = []
        ConfigurationWriter.replaceGaps(&lines, vm)
        let toml = lines.joined(separator: "\n")

        XCTAssertFalse(toml.contains("constant("), "writer leaked a DynamicConfigValue:\n\(toml)")

        let (config, errors) = parseConfigForTest(toml)
        assertEquals(errors, [])
        assertEquals(
            config.gaps,
            Gaps(
                inner: .init(vertical: 11, horizontal: 10),
                outer: .init(left: 14, bottom: 13, top: 12, right: 15),
            ),
        )
    }

    /// A config exercising every shape the settings UI cannot model: per-monitor gap arrays,
    /// a monitor fingerprint, a multi-monitor fallback list, and a multi-command binding.
    private static let lossyConfigSample = """
        # a comment that must survive
        start-at-login = false
        accordion-padding = 30

        [gaps]
            inner.horizontal = 10
            outer.top = [{ monitor."built-in" = 3 }, 6]

        [mode.main.binding]
            alt-h = 'focus left'
            alt-r = ['flatten-workspace-tree', 'mode main']

        [workspace-to-monitor-force-assignment]
        2 = { fingerprint = { display_name = 'ACME Display 32 (1)', width = 3840, height = 2160 } }
        5 = ['secondary', 'dell']
        """

    /// The do-no-harm invariant: saving without editing anything must not change one byte.
    ///
    /// This is the guard that matters. The view model is a lossy projection of the config -- it
    /// collapses per-monitor gap arrays to their default, monitor fingerprints to a single string,
    /// and fallback lists to `.first` -- so unconditionally re-serializing a section destroys
    /// whatever the UI couldn't express. A real config lost its DELL fingerprint width/height this
    /// way, degrading a hardware match into a name regex.
    func testWriterNoOpSaveIsByteIdentical() {
        let vm = ConfigurationViewModel()
        vm.markLoaded() // nothing edited
        assertEquals(ConfigurationWriter.render(baseText: Self.lossyConfigSample, from: vm), Self.lossyConfigSample)
    }

    /// The same invariant, on a file that ends with a newline.
    ///
    /// The sample above does not end with one, because a Swift `"""` literal has no trailing
    /// newline, so every writer test ran against input that no editor produces. A writer that
    /// dropped or added a final newline would have round-tripped "identically" through the whole
    /// suite while putting a one-byte diff in the user's dotfiles on every save.
    ///
    /// It passes today. It is here because the gap in coverage was real, not because it caught
    /// anything.
    func testWriterNoOpSavePreservesATrailingNewline() {
        let vm = ConfigurationViewModel()
        vm.markLoaded() // nothing edited
        let base = Self.lossyConfigSample + "\n"
        assertEquals(ConfigurationWriter.render(baseText: base, from: vm), base)
    }

    /// Editing one gap must rewrite `[gaps]` and nothing else -- the fingerprint, the fallback
    /// list, the multi-command binding and the comment all stay untouched.
    func testWriterEditingGapsLeavesEverythingElseIntact() {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.innerGapsHorizontal += 5 // the only edit

        let out = ConfigurationWriter.render(baseText: Self.lossyConfigSample, from: vm)

        XCTAssertTrue(out.contains("display_name = 'ACME Display 32 (1)', width = 3840, height = 2160"), "fingerprint was degraded:\n\(out)")
        XCTAssertTrue(out.contains("5 = ['secondary', 'dell']"), "fallback list was truncated:\n\(out)")
        XCTAssertTrue(out.contains("alt-r = ['flatten-workspace-tree', 'mode main']"), "multi-command binding was mangled:\n\(out)")
        XCTAssertTrue(out.contains("# a comment that must survive"), "comment was dropped:\n\(out)")

        // And the result must still parse.
        let (_, errors) = parseConfigForTest(out)
        assertEquals(errors, [])
    }

    /// Multi-command bindings used to round-trip through the view model joined by ", " and be
    /// re-emitted as `key = 'a, b'` -- one bogus command that fails to parse.
    func testWriterMultiCommandBindingRoundTrips() {
        let base = """
            [mode.main.binding]
                alt-h = 'focus left'
            """
        let vm = ConfigurationViewModel()
        vm.modes = [.init(mode: "main", bindings: [
            .init(key: "alt-h", command: "focus left"),
            .init(key: "alt-r", command: "flatten-workspace-tree\(ConfigurationViewModel.commandSeparator)mode main"),
        ])]
        vm.markLoaded()

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertTrue(out.contains("alt-r = ['flatten-workspace-tree', 'mode main']"), "expected a TOML array:\n\(out)")

        let (config, errors) = parseConfigForTest(out)
        assertEquals(errors, [])
        assertEquals(config.modes["main"]?.bindings.count, 2)
    }

    /// Values containing a quote must be escaped, not silently stripped.
    func testWriterEscapesQuotesInsteadOfDeletingThem() {
        let vm = ConfigurationViewModel()
        vm.modes = [.init(mode: "main", bindings: [])]
        vm.markLoaded()
        vm.modes[0].bindings = [.init(key: "alt-t", command: "exec-and-forget echo it's here")]

        let out = ConfigurationWriter.render(baseText: "[mode.main.binding]", from: vm)
        XCTAssertTrue(out.contains("it's here"), "apostrophe was stripped:\n\(out)")
        let (config, errors) = parseConfigForTest(out)
        assertEquals(errors, [])
        assertEquals(config.modes["main"]?.bindings.count, 1)
    }

    /// The callback keys, key-mapping, exec env and window rules were all invisible to the GUI.
    func testWriterEmitsPreviouslyUnreachableKeys() {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.onFocusedWorkspaceChanged = [.init(command: "move-mouse window-lazy-center")]
        vm.keyMappingPreset = "dvorak"
        vm.execInheritEnvVars = false
        vm.execEnvVars = [.init(name: "FOO", value: "bar")]
        vm.windowRules = [.init(appId: "com.apple.finder", run: "move-node-to-workspace 3")]

        let out = ConfigurationWriter.render(baseText: "", from: vm)
        let (config, errors) = parseConfigForTest(out)
        assertEquals(errors, [])
        assertEquals(config.onFocusedWorkspaceChanged.count, 1)
        assertEquals(config.onWindowDetected.count, 1)
        XCTAssertTrue(out.contains("preset = 'dvorak'"), out)
        XCTAssertTrue(out.contains("FOO = 'bar'"), out)
    }

    /// `[on-window]` is the v2 shorthand and the form the shipped default config documents. The GUI
    /// used to read only `on-window-detected`, so a v2 config showed an empty Window Rules tab while
    /// its rules were live.
    func testGuiSeesShorthandWindowRules() {
        let vm = ConfigurationViewModel()
        vm.loadWindowRules(fromText: """
            [on-window]
            "com.apple.finder" = "move-node-to-workspace 3"
            "com.apple.mail" = "layout floating"
            """)
        assertEquals(vm.windowRules.count, 2)
        assertEquals(vm.windowRules.first?.appId, "com.apple.finder")
        assertEquals(vm.windowRules.first?.run, "move-node-to-workspace 3")
    }

    /// Long form is tried before the shorthand (`parseConfigV2` appends `[on-window]` after it), so
    /// the list has to be read in that order or the GUI shows rules in an order they do not run in.
    func testGuiListsLongFormWindowRulesBeforeShorthand() {
        let vm = ConfigurationViewModel()
        vm.loadWindowRules(fromText: """
            [[on-window-detected]]
            if.app-id = 'com.apple.mail'
            run = ['layout floating']

            [on-window]
            "com.apple.finder" = "move-node-to-workspace 3"
            """)
        assertEquals(vm.windowRules.map(\.appId), ["com.apple.mail", "com.apple.finder"])
    }

    /// Editing a rule used to write a long-form copy while leaving the shorthand table in place, so
    /// every original rule then matched twice.
    func testEditingAShorthandRuleDoesNotLeaveADuplicate() {
        let base = """
            [on-window]
            "com.apple.finder" = "move-node-to-workspace 3"
            """
        let vm = ConfigurationViewModel()
        vm.loadWindowRules(fromText: base)
        vm.markLoaded()
        vm.windowRules.append(.init(appId: "com.apple.mail", run: "layout floating"))

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        let (config, errors) = parseConfigForTest(out)
        assertEquals(errors, [])
        // Two rules, not three: the original must not survive in both spellings.
        assertEquals(config.onWindowDetected.count, 2)
    }

    /// A config written in the shorthand stays in the shorthand when every rule still fits it.
    ///
    /// Rendered against the real base, not `""`. The shorthand is only chosen for a file that is
    /// already v2 -- `on-window` is a v2 root key, so emitting it into a v1 file would silently
    /// change that file's schema. An empty base is not v2 and never occurs anyway: with no user
    /// config, `configBaseText` falls back to the shipped default, which is v2.
    func testShorthandSurvivesAnEditThatStillFitsIt() {
        let base = """
            mod = 'alt'
            workspaces = ['1-9']

            [on-window]
            "com.apple.finder" = "move-node-to-workspace 3"
            """
        let vm = ConfigurationViewModel()
        vm.loadWindowRules(fromText: base)
        vm.markLoaded()
        vm.windowRules.append(.init(appId: "com.apple.mail", run: "layout floating"))

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertTrue(out.contains("[on-window]"), "shorthand was converted to long form:\n\(out)")
        XCTAssertFalse(out.contains("[[on-window-detected]]"), out)
    }

    /// A matcher the shorthand cannot express forces the whole set to long form, because in a mixed
    /// file the long-form rules take precedence regardless of text order.
    func testARegexMatcherForcesLongFormForEveryRule() {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.windowRules = [
            .init(appId: "com.apple.finder", run: "move-node-to-workspace 3"),
            .init(appId: "", appNameRegex: "Term", run: "layout floating"),
        ]

        let out = ConfigurationWriter.render(baseText: "", from: vm)
        XCTAssertFalse(out.contains("[on-window]"), "mixed rules must not be split across spellings:\n\(out)")
        let (config, errors) = parseConfigForTest(out)
        assertEquals(errors, [])
        assertEquals(config.onWindowDetected.count, 2)
    }

    /// Interior whitespace is legal TOML and TOMLKit reads it, so the GUI listed this rule -- but
    /// the writer compared the line to the exact string `[[on-window-detected]]` and left it. The
    /// file then held the old block AND a new one, and since the shorthand parses last, the STALE
    /// rule won: the edit did nothing and the config grew on every save.
    func testARuleHeaderWithInteriorSpacesIsStillReplaced() {
        let base = """
            [[ on-window-detected ]]
            if.app-id = 'com.apple.mail'
            run = ['move-node-to-workspace 3']
            """
        let vm = ConfigurationViewModel()
        vm.loadWindowRules(fromText: base)
        vm.markLoaded()
        assertEquals(vm.windowRules.count, 1)
        vm.windowRules[0].run = "move-node-to-workspace 4"

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        let (config, errors) = parseConfigForTest(out)
        assertEquals(errors, [])
        assertEquals(config.onWindowDetected.count, 1)
        XCTAssertFalse(out.contains("move-node-to-workspace 3"), "the superseded rule survived:\n\(out)")
    }

    /// Editing a window rule must not delete the documentation of the section that happens to follow
    /// it. `removeSections` has always walked back over trailing comments for exactly this reason;
    /// the array-of-tables walker did not, so a rules edit ate the next section's banner.
    func testEditingARuleKeepsTheFollowingSectionsComments() {
        let base = """
            [[on-window-detected]]
            if.app-id = 'com.apple.mail'
            run = ['move-node-to-workspace 3']

            # ---------------------------------------------
            # Gaps -- tuned for a 32" panel
            # ---------------------------------------------
            [gaps]
            inner.horizontal = 10
            """
        let vm = ConfigurationViewModel()
        vm.loadWindowRules(fromText: base)
        vm.markLoaded()
        vm.windowRules[0].run = "move-node-to-workspace 4"

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertTrue(out.contains("# Gaps -- tuned for a 32\" panel"), "an untouched section lost its comment:\n\(out)")
        XCTAssertTrue(out.contains("inner.horizontal = 10"), out)
    }

    /// Choosing the shorthand from the rules alone rewrote a v1 config into v2, because `on-window`
    /// is a v2 root key -- so retyping a workspace number changed the file's schema, and later saves
    /// then wrote bindings to a different place than the ones already in the file.
    func testEditingARuleDoesNotConvertAV1ConfigToV2() {
        let base = """
            [mode.main.binding]
            alt-h = 'focus left'

            [[on-window-detected]]
            if.app-id = 'com.apple.mail'
            run = ['move-node-to-workspace 3']
            """
        let vm = ConfigurationViewModel()
        vm.loadWindowRules(fromText: base)
        vm.markLoaded()
        vm.windowRules[0].run = "move-node-to-workspace 4"

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertFalse(out.contains("[on-window]"), "a v1 config was silently converted to v2:\n\(out)")
        let (config, errors) = parseConfigForTest(out)
        assertEquals(errors, [])
        assertEquals(config.onWindowDetected.count, 1)
    }

    /// Clearing a rule's command to retype it used to delete that rule from the file on the next
    /// autosave, while the row stayed on screen. Every keystroke of the replacement then failed
    /// validation and wrote nothing, so an interrupted edit lost the rule silently.
    func testAHalfTypedCommandDoesNotDeleteTheRulesAlreadyOnDisk() {
        let base = """
            mod = 'alt'

            [on-window]
            "com.apple.finder" = "move-node-to-workspace 3"
            "com.apple.mail" = "layout floating"
            """
        let vm = ConfigurationViewModel()
        vm.loadWindowRules(fromText: base)
        vm.markLoaded()
        assertEquals(vm.windowRules.count, 2)
        // The user selects the mail rule and clears its Command field, intending to retype it. The
        // row stays on screen; the question is whether it survives on disk until they finish.
        vm.windowRules[1].run = ""

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        let (config, errors) = parseConfigForTest(out)
        assertEquals(errors, [])
        assertEquals(config.onWindowDetected.count, 2)
        XCTAssertTrue(out.contains("layout floating"), "the rule being retyped was deleted from disk:\n\(out)")
    }

    /// Same guard, reached from a value the GUI cannot represent: `= 42` reads as an empty command,
    /// and dropping it would silently delete a line the user wrote.
    func testAnUnreadableRuleValueIsNotSilentlyDropped() {
        let base = """
            mod = 'alt'

            [on-window]
            "com.apple.finder" = 42
            """
        let vm = ConfigurationViewModel()
        vm.loadWindowRules(fromText: base)
        vm.markLoaded()
        vm.windowRules.append(.init(appId: "com.apple.mail", run: "layout floating"))

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertTrue(out.contains("42"), "a line the GUI could not read was deleted:\n\(out)")
    }

    /// An *applied* Raw TOML tab is authoritative -- it is exactly what lands on disk.
    /// See `ConfigurationWriterSafetyTest` for the counterpart: an unapplied buffer must NOT win.
    func testWriterRawTomlWins() {
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.rawToml = "accordion-padding = 7\n"
        vm.accordionPadding = 999 // must be ignored
        vm.rawTomlApplyRequested = true

        assertEquals(ConfigurationWriter.render(baseText: "accordion-padding = 30", from: vm), "accordion-padding = 7\n")
    }

    func testWriterValidateRejectsBrokenToml() {
        XCTAssertNil(ConfigurationWriter.validate("accordion-padding = 30"))
        XCTAssertNotNil(ConfigurationWriter.validate("accordion-padding = ["))
        XCTAssertNotNil(ConfigurationWriter.validate("totally-unknown-key = 1"))
    }

    func testKeyNotationPrettyPrinting() {
        assertEquals(KeyNotation.pretty("alt-shift-h"), "⌥⇧h")
        assertEquals(KeyNotation.pretty("cmd-enter"), "⌘enter")
        assertEquals(KeyNotation.pretty("h"), "h")
    }

    func testParseKeyMapping() {
        let (config, errors) = parseConfigForTest(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'q'
                unicorn = 'u'

            [mode.main.binding]
                alt-unicorn = 'workspace wonderland'
            """,
        )
        assertEquals(errors.descriptions, [])
        assertEquals(config.keyMapping, KeyMapping(preset: .qwerty, rawKeyNotationToKeyCode: [
            "q": .q,
            "unicorn": .u,
        ]))
        let binding = HotkeyBinding(.option, .u, [WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("unicorn").getOrDie())))])
        assertEquals(config.modes[mainModeId]?.bindings, [binding.descriptionWithKeyCode: binding])

        let (_, errors1) = parseConfigForTest(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'qw'
                ' f' = 'f'
            """,
        )
        assertEquals(errors1.descriptions, [
            "key-mapping.key-notation-to-key-code: ' f' is invalid key notation",
            "key-mapping.key-notation-to-key-code.q: 'qw' is invalid key code",
        ])

        let (dvorakConfig, dvorakErrors) = parseConfigForTest(
            """
            key-mapping.preset = 'dvorak'
            """,
        )
        assertEquals(dvorakErrors, [])
        assertEquals(dvorakConfig.keyMapping, KeyMapping(preset: .dvorak, rawKeyNotationToKeyCode: [:]))
        assertEquals(dvorakConfig.keyMapping.resolve()["quote"], .q)
        let (colemakConfig, colemakErrors) = parseConfigForTest(
            """
            key-mapping.preset = 'colemak'
            """,
        )
        assertEquals(colemakErrors, [])
        assertEquals(colemakConfig.keyMapping, KeyMapping(preset: .colemak, rawKeyNotationToKeyCode: [:]))
        assertEquals(colemakConfig.keyMapping.resolve()["f"], .e)
    }
}
