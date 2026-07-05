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

    func testExecOnWorkspaceChangeDeprecated() {
        let (_, errors) = parseConfigForTest(
            """
            exec-on-workspace-change = ['/bin/true']
            """,
        )
        assertEquals(errors.descriptions, [
            "Deprecated: exec-on-workspace-change is deprecated. Please use on-focused-monitor-changed with exec-and-forget instead.",
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

    func testAfterLoginCommandDeprecated() {
        let (_, errors) = parseConfigForTest(
            """
            after-login-command = ['workspace 1']
            """,
        )
        assertEquals(errors.descriptions, [
            "Deprecated: after-login-command is deprecated since AeroSpork 0.19.0. https://github.com/wbsmolen/AeroSpork/issues/1482",
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
                dock = { fingerprint = { uuid = "37D8832A-2D66-02CA-B9F7-8F30A301B230" } }
                ext = { fingerprint = { vendor = "0x1234", model = "0x5678" } }
            """,
        )
        assertEquals([], errors.descriptions)
        assertEquals(
            [MonitorDescription.fingerprint(MonitorFingerprintPatternData(displayUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230"))],
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
            "on-window-detected[3]: For now, \'move-node-to-workspace\' must be the latest instruction in the callback (otherwise it\'s error-prone). Please report your use cases to https://github.com/wbsmolen/AeroSpork/issues/20",
            "on-window-detected[4]: For now, \'move-node-to-workspace\' can be mentioned only once in \'run\' callback. Please report your use cases to https://github.com/wbsmolen/AeroSpork/issues/20",
            "on-window-detected[5]: For now, \'layout floating\', \'layout tiling\' and \'move-node-to-workspace\' are the only commands that are supported in \'on-window-detected\'. Please report your use cases to https://github.com/wbsmolen/AeroSpork/issues/20",
            "on-window-detected[5]: For now, \'move-node-to-workspace\' must be the latest instruction in the callback (otherwise it\'s error-prone). Please report your use cases to https://github.com/wbsmolen/AeroSpork/issues/20",
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
