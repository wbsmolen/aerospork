import AppKit
import Common
import TOMLKit

@MainActor
func readConfig(forceConfigUrl: URL? = nil) -> Result<(Config, URL), String> {
    // Self-guarding: only ever rewrites the user's own v1 file, and only once. Sitting here rather
    // than in a startup hook means `reload-config` and hot-reload are covered too.
    migrateUserConfigToV2IfNeeded()

    let customConfigUrl: URL
    let isUserConfig: Bool
    switch findCustomConfigUrl() {
        case .file(let url):
            customConfigUrl = url
            isUserConfig = true
        case .noCustomConfigExists:
            customConfigUrl = defaultConfigUrl
            isUserConfig = false
            // A migrating user's first launch: the config they brought is right there and not read,
            // so they get the default keymap and no hint why.
            if let hint = upstreamConfigLeftBehindHint() {
                AppLog.config.notice("\(hint, privacy: .public)")
                printStderr(hint)
            }
        case .ambiguousConfigError(let candidates):
            let msg = """
                Ambiguous config error. Several configs found:
                \(candidates.map(\.path).joined(separator: "\n"))
                """
            return .failure(msg)
    }
    let configUrl: URL = forceConfigUrl ?? customConfigUrl
    let finalIsUserConfig = forceConfigUrl != nil ? true : isUserConfig

    let configContent = try? String(contentsOf: configUrl)
    var warnings: [TomlParseError] = []
    let parseResult = configContent.map { parseConfig($0, isUserConfig: finalIsUserConfig, warnings: &warnings) } ?? .success(defaultConfig)

    // Reading the BUNDLED default is the startup fallback, not a load of the user's config.
    // Recording health here would erase the only surviving record that the user's config failed --
    // `initAppBundle` retries with the default immediately after, and the retry always succeeds.
    let recordHealth = configUrl != defaultConfigUrl

    switch parseResult {
        case .success(let parsedConfig):
            if recordHealth {
                configLoadFailure = nil
                configWarnings = warnings.map(\.description)
                for warning in configWarnings { printStderr("\(configUrl.lastPathComponent): \(warning)") }
            }
            return .success((parsedConfig, configUrl))
        case .failure(let errors):
            let msg = """
                Failed to parse \(configUrl.absoluteURL.path)

                \(errors.map(\.description).joined(separator: "\n\n"))
                """
            if recordHealth { configLoadFailure = msg }
            return .failure(msg)
    }
}



extension ParserProtocol {
    func transformRawConfig(_ raw: S,
                            _ value: TOMLValueConvertible,
                            _ backtrace: TomlBacktrace,
                            _ errors: inout [TomlParseError]) -> S
    {
        if let value = parse(value, backtrace, &errors).getOrNil(appendErrorTo: &errors) {
            return raw.copy(keyPath, value)
        }
        return raw
    }
}

protocol ParserProtocol<S>: Sendable {
    associatedtype T
    associatedtype S where S: ConvenienceCopyable
    var keyPath: SendableWritableKeyPath<S, T> { get }
    var parse: @Sendable (TOMLValueConvertible, TomlBacktrace, inout [TomlParseError]) -> ParsedToml<T> { get }
}

struct Parser<S: ConvenienceCopyable, T>: ParserProtocol {
    let keyPath: SendableWritableKeyPath<S, T>
    let parse: @Sendable (TOMLValueConvertible, TomlBacktrace, inout [TomlParseError]) -> ParsedToml<T>

    init(_ keyPath: SendableWritableKeyPath<S, T>, _ parse: @escaping @Sendable (TOMLValueConvertible, TomlBacktrace, inout [TomlParseError]) -> T) {
        self.keyPath = keyPath
        self.parse = { raw, backtrace, errors -> ParsedToml<T> in .success(parse(raw, backtrace, &errors)) }
    }

    init(_ keyPath: SendableWritableKeyPath<S, T>, _ parse: @escaping @Sendable (TOMLValueConvertible, TomlBacktrace) -> ParsedToml<T>) {
        self.keyPath = keyPath
        self.parse = { raw, backtrace, _ -> ParsedToml<T> in parse(raw, backtrace) }
    }
}

private let keyMappingConfigRootKey = "key-mapping"
let modeConfigRootKey = "mode"

// For every new config option you add, think:
// 1. Does it make sense to have different value
// 2. Prefer commands and commands flags over toml options if possible
/// Every top-level config key the parser accepts.
///
/// Exposed so `ConfigCommandKeyCoverageTest` can prove `buildConfigMap` -- the hand-maintained list
/// behind `config --get` -- lists all of them. Two keys were added to the parser and not to that
/// list, so they configured the app while `config --get` answered "No value at key token".
let configParserKeys: Set<String> = Set(configParser.keys)

private let configParser: [String: any ParserProtocol<Config>] = [
    "after-startup-command": Parser(\.afterStartupCommand) { parseCommandOrCommands($0).toParsedToml($1) },

    "on-focus-changed": Parser(\.onFocusChanged) { parseCommandOrCommands($0).toParsedToml($1) },
    "on-focused-monitor-changed": Parser(\.onFocusedMonitorChanged) { parseCommandOrCommands($0).toParsedToml($1) },
    "on-focused-workspace-changed": Parser(\.onFocusedWorkspaceChanged) { parseCommandOrCommands($0).toParsedToml($1) },

    "enable-normalization-flatten-containers": Parser(\.enableNormalizationFlattenContainers, parseBool),
    "enable-normalization-opposite-orientation-for-nested-containers": Parser(\.enableNormalizationOppositeOrientationForNestedContainers, parseBool),

    "default-root-container-layout": Parser(\.defaultRootContainerLayout, parseLayout),
    "default-root-container-orientation": Parser(\.defaultRootContainerOrientation, parseDefaultContainerOrientation),

    "start-at-login": Parser(\.startAtLogin, parseBool),
    "automatically-unhide-macos-hidden-apps": Parser(\.automaticallyUnhideMacosHiddenApps, parseBool),
    "accordion-padding": Parser(\.accordionPadding, parseInt),
    "exec": Parser(\.execConfig, parseExecConfig),

    keyMappingConfigRootKey: Parser(\.keyMapping, skipParsing(Config().keyMapping)), // Parsed manually
    modeConfigRootKey: Parser(\.modes, skipParsing(Config().modes)), // Parsed manually

    // Config v2. All parsed manually, in `applyConfigV2`, because each of them desugars into a
    // field that a v1 key already writes -- letting the generic table walker set them would make
    // the winner depend on TOML iteration order.
    "mod": Parser(\._deprecatedNoOp, skipParsing(())),
    "workspaces": Parser(\._deprecatedNoOp, skipParsing(())),
    "keys": Parser(\._deprecatedNoOp, skipParsing(())),
    "monitors": Parser(\._deprecatedNoOp, skipParsing(())),
    "on-window": Parser(\._deprecatedNoOp, skipParsing(())),

    // Upstream's spelling of "these workspaces always exist". Read by the generic walker, NOT listed
    // in `configV2RootKeys`: that would reclassify an upstream `[mode.*]` config as v2 and skip its
    // migration. `workspaces` and force-assigned names join the same set later in `parseConfig`.
    "persistent-workspaces": Parser(\.persistentWorkspaces) { raw, backtrace, errors in
        Set(parseWorkspaceNames(raw, backtrace, &errors))
    },

    "gaps": Parser(\.gaps, parseGaps),
    "workspace-to-monitor-force-assignment": Parser(\.workspaceToMonitorForceAssignment, parseWorkspaceToMonitorAssignment),
    "on-window-detected": Parser(\.onWindowDetected, parseOnWindowDetectedArray),
    "auto-move-workspaces-on-monitor-connect": Parser(\.autoMoveWorkspacesOnMonitorConnect, parseBool),
    "show-menu-bar-icon": Parser(\.showMenuBarIcon, parseBool),
    "show-dock-icon": Parser(\.showDockIcon, parseBool),

    // Deprecated. Every key here reports a WARNING and the config still loads -- see `deprecated`.

    // Still honoured: `focus.swift` runs it on every workspace change. It used to accept ONLY `[]`,
    // which made its own consumer unreachable -- the key looked supported and did nothing.
    "exec-on-workspace-change": Parser(\.execOnWorkspaceChange) { raw, backtrace, errors in
        switch parseTomlArray(raw, backtrace).flatMap({ $0.mapAllOrFailure { parseString($0, backtrace) } }) {
            case .success(let argv):
                if !argv.isEmpty {
                    errors.append(deprecated(backtrace, "exec-on-workspace-change is deprecated. Please use on-focused-workspace-changed with exec-and-forget instead."))
                }
                return argv
            case .failure(let error):
                errors.append(error)
                return []
        }
    },

    // Accepted so an old config still loads; they do nothing. Removing them outright would turn
    // them into "Unknown top-level key", which IS fatal -- the exact failure P1-1 exists to stop.
    "after-login-command": Parser(\._deprecatedNoOp, deprecatedNoOp(
        "after-login-command is deprecated and does nothing. Use after-startup-command.")),
    "non-empty-workspaces-root-containers-layout-on-startup": Parser(\._deprecatedNoOp, deprecatedNoOp(
        "non-empty-workspaces-root-containers-layout-on-startup is deprecated and does nothing. " +
            "There is no startup-specific layout: every workspace root container uses default-root-container-layout.")),
    "indent-for-nested-containers-with-the-same-orientation": Parser(\._deprecatedNoOp, deprecatedNoOp(
        "indent-for-nested-containers-with-the-same-orientation is deprecated and does nothing. See https://github.com/wbsmolen/aerospork/issues/96")),
].merging(upstreamOnlyKeyParsers) { own, _ in own } // upstream-only keys: reported and ignored

/// A finding against an obsolete key: the key is ignored (or still honoured), and the rest of the
/// config loads.
///
/// Hard-failing was the old behaviour, and it meant one legacy line cost the user every binding
/// they had -- the app fell back to the bundled default keymap. A deprecation notice the user can
/// ignore until Sunday beats an unusable window manager.
///
/// The severity is carried by `.deprecation` itself rather than by a set of deprecated top-level
/// key names, because deprecated keys are not all top-level -- see `TomlParseError.deprecation`.
func deprecated(_ backtrace: TomlBacktrace, _ msg: String) -> TomlParseError {
    .deprecation(backtrace, "Deprecated: " + msg)
}

/// A key that parses to nothing and does nothing, but must keep loading. The warning is the
/// entire behaviour -- silently accepting a key that has no effect is a lie to the user.
private func deprecatedNoOp(_ msg: String) -> @Sendable (TOMLValueConvertible, TomlBacktrace) -> ParsedToml<Void> {
    { _, backtrace in .failure(deprecated(backtrace, msg)) }
}

extension ParsedCmd where T == any Command {
    internal func toEither() -> Parsed<T> { // Changed to internal
        return switch self {
            case .cmd(let a):
                a.info.allowInConfig
                    ? .success(a)
                    : .failure("Command '\(a.info.kind.rawValue)' cannot be used in config")
            case .help(let a): .failure(a)
            case .failure(let a): .failure(a)
        }
    }
}

extension Command {
    fileprivate var isMacOsNativeCommand: Bool { // Problem ID-B6E178F2
        self is MacosNativeMinimizeCommand || self is MacosNativeFullscreenCommand
    }
}

func parseCommandOrCommands(_ raw: TOMLValueConvertible) -> Parsed<[any Command]> {
    if let rawString = raw.string {
        return parseCommand(rawString).toEither().map { [$0] }
    } else if let rawArray = raw.array {
        let commands: Parsed<[any Command]> = (0 ..< rawArray.count).mapAllOrFailure { index in
            let rawString: String = rawArray[index].string ?? expectedActualTypeError(expected: .string, actual: rawArray[index].type)
            return parseCommand(rawString).toEither()
        }
        return commands.filter("macos-native-* commands are only allowed to be the last commands in the list") {
            !$0.dropLast().contains(where: { $0.isMacOsNativeCommand })
        }
    } else {
        return .failure(expectedActualTypeError(expected: [.string, .array], actual: raw.type))
    }
}

@MainActor func parseConfig(_ rawToml: String, isUserConfig: Bool = true) -> Result<Config, [TomlParseError]> {
    var discarded: [TomlParseError] = []
    return parseConfig(rawToml, isUserConfig: isUserConfig, warnings: &discarded)
}

/// `warnings` collects the non-fatal findings (deprecated keys). They are reported to the user but
/// must not fail the load; only `.failure` refuses the config.
@MainActor func parseConfig(_ rawToml: String, isUserConfig: Bool = true, warnings: inout [TomlParseError]) -> Result<Config, [TomlParseError]> {
    let rawTable: TOMLTable
    do {
        rawTable = try TOMLTable(string: rawToml)
    } catch let e as TOMLParseError {
        return .failure([.syntax(e.debugDescription)])
    } catch let e {
        return .failure([.syntax(e.localizedDescription)])
    }

    var errors: [TomlParseError] = []

    var config = rawTable.parseTable(Config(), configParser, .emptyRoot, &errors)

    if let mapping = rawTable[keyMappingConfigRootKey].flatMap({ parseKeyMapping($0, .rootKey(keyMappingConfigRootKey), &errors) }) {
        config.keyMapping = mapping
    }

    let isV2 = isConfigV2(rawTable)
    if let modes = rawTable[modeConfigRootKey].flatMap({
        // In v2 the main mode is `[keys]` (plus whatever `mod` generated), so `[mode.*]` is a
        // supplement -- demanding `[mode.main]` as well would mean writing an empty section.
        parseModes($0, .rootKey(modeConfigRootKey), &errors, config.keyMapping.resolve(), requireMainMode: !isV2)
    }) {
        config.modes = modes
    }

    if isV2 { applyConfigV2(rawTable, &config, &errors) }

    // Declared workspaces always exist -- see `Workspace.garbageCollectUnusedWorkspaces`. `workspaces`
    // was added in `applyConfigV2` and `persistent-workspaces` by the table walker; a force-assignment
    // is a declaration too, since pinning a workspace to a monitor says it exists. Unlike the
    // binding-derived names below, this holds for the bundled default as well: copying the default to
    // a file of your own must not change what it does.
    config.persistentWorkspaces.formUnion(config.workspaceToMonitorForceAssignment.keys)

    // Only preserve workspace names if this is a user config, not the default config
    if isUserConfig {
        config.preservedWorkspaceNames = config.modes.values.lazy
            .flatMap { (mode: Mode) -> [HotkeyBinding] in Array(mode.bindings.values) }
            .flatMap { (binding: HotkeyBinding) -> [String] in
                binding.commands.filterIsInstance(of: WorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw } +
                    binding.commands.filterIsInstance(of: MoveNodeToWorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw }
            }
            + (config.workspaceToMonitorForceAssignment).keys
    } else {
        // For default config, only preserve workspaces with force assignments
        config.preservedWorkspaceNames = Array(config.workspaceToMonitorForceAssignment.keys)
    }

    if config.enableNormalizationFlattenContainers {
        let containsSplitCommand = config.modes.values.lazy.flatMap { $0.bindings.values }
            .flatMap { $0.commands }
            .contains { $0 is SplitCommand }
        if containsSplitCommand {
            errors += [.semantic(
                // `.emptyRoot` because the conflict is between two coordinates in different
                // sections (a `split` binding and a top-level flag) and `TomlBacktrace` can only
                // name one. Pointing at either alone would be misleading. A `.pair` of backtraces
                // in the error, or a second "see also" field, is what would fix the message.
                .emptyRoot,
                """
                The config contains:
                1. usage of 'split' command
                2. enable-normalization-flatten-containers = true
                These two settings don't play nicely together. 'split' command has no effect when enable-normalization-flatten-containers is disabled.

                My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
                """,
            )]
        }
    }

    errors += upstreamNameWarnings(rawToml)

    warnings = errors.filter(\.isDeprecation)
    let fatal = errors.filter { !$0.isDeprecation }

    if fatal.isEmpty {
        return .success(config)
    } else {
        return .failure(fatal)
    }
}

func parseInt(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    raw.int.orFailure(expectedActualTypeError(expected: .int, actual: raw.type, backtrace))
}

func parseString(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<String> {
    raw.string.orFailure(expectedActualTypeError(expected: .string, actual: raw.type, backtrace))
}

func parseSimpleType<T>(_ raw: TOMLValueConvertible) -> T? {
    (raw.int as? T) ?? (raw.string as? T) ?? (raw.bool as? T)
}

extension TOMLValueConvertible {
    func unwrapTableWithSingleKey(expectedKey: String? = nil, _ backtrace: inout TomlBacktrace) -> ParsedToml<(key: String, value: TOMLValueConvertible)> {
        guard let table else {
            return .failure(expectedActualTypeError(expected: .table, actual: type, backtrace))
        }
        let singleKeyError: TomlParseError = .semantic(
            backtrace,
            expectedKey != nil
                ? "The table is expected to have a single key '\(expectedKey.orDie())'"
                : "The table is expected to have a single key",
        )
        guard let (actualKey, value): (String, TOMLValueConvertible) = table.count == 1 ? table.first : nil else {
            return .failure(singleKeyError)
        }
        if expectedKey != nil && expectedKey != actualKey {
            return .failure(singleKeyError)
        }
        backtrace = backtrace + .key(actualKey)
        return .success((actualKey, value))
    }
}

func parseTomlArray(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<TOMLArray> {
    raw.array.orFailure(expectedActualTypeError(expected: .array, actual: raw.type, backtrace))
}

func parseTable<T: ConvenienceCopyable>(
    _ raw: TOMLValueConvertible,
    _ initial: T,
    _ fieldsParser: [String: any ParserProtocol<T>],
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> T {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, backtrace))
        return initial
    }
    return table.parseTable(initial, fieldsParser, backtrace, &errors)
}

private func parseLayout(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Layout> {
    parseString(raw, backtrace)
        .flatMap { $0.parseLayout().orFailure(.semantic(backtrace, "Can't parse layout '\($0)'")) }
}

private func skipParsing<T: Sendable>(_ value: T) -> @Sendable (_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<T> {
    { _, _ in .success(value) }
}

/// Shares the CLI's enum parser, so the config lists the accepted values the same way `--help` does.
/// `Parsed.toParsedToml` is the bridge between the two error types.
private func parseDefaultContainerOrientation(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<DefaultContainerOrientation> {
    parseString(raw, backtrace).flatMap { parseEnum($0, DefaultContainerOrientation.self).toParsedToml(backtrace) }
}




func parseBool(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Bool> {
    raw.bool.orFailure(expectedActualTypeError(expected: .bool, actual: raw.type, backtrace))
}



extension TOMLTable {
    func parseTable<T: ConvenienceCopyable>(
        _ initial: T,
        _ fieldsParser: [String: any ParserProtocol<T>],
        _ backtrace: TomlBacktrace,
        _ errors: inout [TomlParseError],
    ) -> T {
        var raw = initial

        for (key, value) in self {
            let backtrace: TomlBacktrace = backtrace + .key(key)
            if let parser = fieldsParser[key] {
                raw = parser.transformRawConfig(raw, value, backtrace, &errors)
            } else {
                errors.append(unknownKeyError(backtrace))
            }
        }

        return raw
    }
}

func unknownKeyError(_ backtrace: TomlBacktrace) -> TomlParseError {
    .semantic(backtrace, backtrace.isRootKey ? "Unknown top-level key" : "Unknown key")
}

func expectedActualTypeError(expected: TOMLType, actual: TOMLType, _ backtrace: TomlBacktrace) -> TomlParseError {
    .semantic(backtrace, expectedActualTypeError(expected: expected, actual: actual))
}

func expectedActualTypeError(expected: [TOMLType], actual: TOMLType, _ backtrace: TomlBacktrace) -> TomlParseError {
    .semantic(backtrace, expectedActualTypeError(expected: expected, actual: actual))
}
