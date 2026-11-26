import AppKit
import Common
import TOMLKit

/// `found` stands in for the search for the user's config, so a test can hand it files of its own.
///
/// It reads and reports, and records nothing: `reload-config --dry-run` reads too, and a dry run that
/// cleared the failure took the fallback banner away while the defaults still ran. The one read that
/// is applied records it, through `recordConfigHealth`.
@MainActor
func readConfig(forceConfigUrl: URL? = nil, found: ConfigFile? = nil) -> Result<(Config, URL), String> {
    var warnings: [String] = []
    return readConfig(forceConfigUrl: forceConfigUrl, found: found, warnings: &warnings)
}

@MainActor
func readConfig(forceConfigUrl: URL? = nil, found: ConfigFile? = nil, warnings: inout [String]) -> Result<(Config, URL), String> {
    // Before the search, not after it. The forced read is `initAppBundle`'s fallback once the user's
    // config failed, and it `check`s the result. When the search itself was what failed (two
    // configs), the fallback failed the same way and the app died at startup.
    if let forceConfigUrl { return readConfig(at: forceConfigUrl, warnings: &warnings) }
    guard let customConfig = found ?? searchUserConfig() else { return .failure("tests may not touch a real config") }
    switch customConfig {
        case .file(let url):
            return readConfig(at: url, warnings: &warnings)
        case .noCustomConfigExists:
            // A migrating user's first launch: the config they brought is right there and not read,
            // so they get the default keymap and no hint why.
            if let hint = upstreamConfigLeftBehindHint() {
                AppLog.config.notice("\(hint, privacy: .public)")
                printStderr(hint)
            }
            return readConfig(at: defaultConfigUrl, warnings: &warnings)
        case .ambiguousConfigError(let candidates):
            let msg = """
                \(ambiguousConfigFailurePrefix) Several configs found:
                \(candidates.map(\.path).joined(separator: "\n"))
                """
            return .failure(msg)
    }
}

/// The search `readConfig` runs and the watcher compares. Under XCTest only `testConfigOverride`, and nil
/// without one.
@MainActor
func searchUserConfig() -> ConfigFile? {
    isUnitTest ? testConfigOverride.map { findCustomConfigUrl(among: [$0]) } : findCustomConfigUrl()
}

@MainActor
func readConfig(at configUrl: URL) -> Result<(Config, URL), String> {
    var warnings: [String] = []
    return readConfig(at: configUrl, warnings: &warnings)
}

@MainActor
func readConfig(at configUrl: URL, warnings: inout [String]) -> Result<(Config, URL), String> {
    // Parsed once, at launch, with `Config()` behind it, so the startup fallback cannot fail. It is also
    // the no-file case's config, which parsed the bundled file again on every reload.
    if configUrl == defaultConfigUrl {
        warnings = []
        return .success((defaultConfig, configUrl))
    }
    let configContent: String
    switch readConfigText(at: configUrl) {
        case .success(let text):
            configContent = text
        case .failure(let reason):
            return .failure(reason)
    }
    var parseWarnings: [TomlParseError] = []
    let parseResult = parseConfig(configContent, warnings: &parseWarnings)

    switch parseResult {
        case .success(let parsedConfig):
            warnings = parseWarnings.map(\.description)
            for warning in warnings { printStderr("\(configUrl.lastPathComponent): \(warning)") }
            return .success((parsedConfig, configUrl))
        case .failure(let errors):
            let msg = """
                \(configParseFailurePrefix)\(configUrl.absoluteURL.path)

                \(errors.map(\.description).joined(separator: "\n\n"))
                """
            return .failure(msg)
    }
}

/// How the two failures that are not "can't read this file" start. The banner and the menu word their
/// recovery by which one `configLoadFailure` is.
let configParseFailurePrefix = "Failed to parse "
let ambiguousConfigFailurePrefix = "Ambiguous config error."

/// What the banner and the menu warning show, from the read that is applied.
///
/// `searched` says the read looked for the user's config, so the bundled default it returned means
/// none exists. A forced read of the default does not say that.
@MainActor
func recordConfigHealth(_ result: Result<(Config, URL), String>, warnings: [String], searched: Bool = false) {
    switch result {
        case .success((_, let url)):
            // A forced read of the BUNDLED default is the startup fallback, not a load of the user's
            // config. Recording it would erase the only surviving record that the user's config failed --
            // `initAppBundle` retries with the default immediately after, and the retry always succeeds.
            // A search that found no config is a healthy load: deleting a broken config left its banner.
            guard url != defaultConfigUrl || searched else { return }
            configLoadFailure = nil
            configWarnings = warnings
        case .failure(let msg):
            configLoadFailure = msg
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
    "mod": Parser(\._handledElsewhere, skipParsing(())),
    "workspaces": Parser(\._handledElsewhere, skipParsing(())),
    "keys": Parser(\._handledElsewhere, skipParsing(())),
    "monitors": Parser(\._handledElsewhere, skipParsing(())),
    "on-window": Parser(\._handledElsewhere, skipParsing(())),

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
    "after-login-command": Parser(\._handledElsewhere, deprecatedNoOp(
        "after-login-command is deprecated and does nothing. Use after-startup-command.")),
    "non-empty-workspaces-root-containers-layout-on-startup": Parser(\._handledElsewhere, deprecatedNoOp(
        "non-empty-workspaces-root-containers-layout-on-startup is deprecated and does nothing. " +
            "There is no startup-specific layout: every workspace root container uses default-root-container-layout.")),
    "indent-for-nested-containers-with-the-same-orientation": Parser(\._handledElsewhere, deprecatedNoOp(
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
    internal func toEither() -> Parsed<T> {
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
            // The type error used to be handed to `parseCommand` as if it were a command, which reported
            // "Unrecognized subcommand 'Expected'" and no index.
            guard let rawString = rawArray[index].string else {
                return .failure("[\(index)]: " + expectedActualTypeError(expected: .string, actual: rawArray[index].type))
            }
            return parseCommand(rawString).toEither()
        }
        return commands.filter("macos-native-* commands are only allowed to be the last commands in the list") {
            !$0.dropLast().contains(where: { $0.isMacOsNativeCommand })
        }
    } else {
        return .failure(expectedActualTypeError(expected: [.string, .array], actual: raw.type))
    }
}

@MainActor func parseConfig(_ rawToml: String) -> Result<Config, [TomlParseError]> {
    var discarded: [TomlParseError] = []
    return parseConfig(rawToml, warnings: &discarded)
}

/// `warnings` collects the non-fatal findings (deprecated keys). They are reported to the user but
/// must not fail the load; only `.failure` refuses the config.
@MainActor func parseConfig(_ rawToml: String, warnings: inout [TomlParseError]) -> Result<Config, [TomlParseError]> {
    let rawTable: TOMLTable
    do {
        rawTable = try TOMLTable(string: rawToml)
    } catch let e as TOMLParseError {
        return .failure([.syntax(e.debugDescription)])
    } catch let e {
        return .failure([.syntax(e.localizedDescription)])
    }
    return parseConfig(table: rawTable, rawToml: rawToml, warnings: &warnings)
}

/// The same, for a caller that already holds the parsed table of `rawToml`, so the text is not parsed twice.
@MainActor func parseConfig(
    table rawTable: TOMLTable,
    rawToml: String,
    warnings: inout [TomlParseError],
) -> Result<Config, [TomlParseError]> {
    var errors: [TomlParseError] = []

    var config = rawTable.parseTable(Config(), configParser, .emptyRoot, &errors)

    if let mapping = rawTable[keyMappingConfigRootKey].flatMap({ parseKeyMapping($0, .rootKey(keyMappingConfigRootKey), &errors) }) {
        config.keyMapping = mapping
    }

    let isV2 = isConfigV2(rawTable)
    let mapping = config.keyMapping.resolve()
    if let modes = rawTable[modeConfigRootKey].flatMap({
        // In v2 the main mode is `[keys]` (plus whatever `mod` generated), so `[mode.*]` is a
        // supplement -- demanding `[mode.main]` as well would mean writing an empty section.
        parseModes($0, .rootKey(modeConfigRootKey), &errors, mapping, requireMainMode: !isV2)
    }) {
        config.modes = modes
    }

    if isV2 { applyConfigV2(rawTable, &config, &errors, mapping) }

    // Declared workspaces always exist -- see `Workspace.garbageCollectUnusedWorkspaces`. `workspaces`
    // was added in `applyConfigV2` and `persistent-workspaces` by the table walker; a force-assignment
    // is a declaration too, since pinning a workspace to a monitor says it exists.
    config.persistentWorkspaces.formUnion(config.workspaceToMonitorForceAssignment.keys)

    // The names a binding reaches, for `getStubWorkspace`. Only names: no workspace is made for them.
    // The same for the bundled default as for any file, so copying the default to a file of your own
    // does not change what it does. (The default once got only its force-assigned names here.)
    config.preservedWorkspaceNames = config.modes.values.lazy
        .flatMap { (mode: Mode) -> [HotkeyBinding] in Array(mode.bindings.values) }
        .flatMap { (binding: HotkeyBinding) -> [String] in
            binding.commands.filterIsInstance(of: WorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw } +
                binding.commands.filterIsInstance(of: MoveNodeToWorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw }
        }
        + (config.workspaceToMonitorForceAssignment).keys

    if config.enableNormalizationFlattenContainers {
        let containsSplitCommand = config.modes.values.lazy.flatMap { $0.bindings.values }
            .flatMap { $0.commands }
            .contains { $0 is SplitCommand }
        if containsSplitCommand {
            // A warning, not an error. It was fatal, so one `split` binding cost the user every binding
            // they had, while `SplitCommand` already refuses at run time with this same advice.
            errors += [.deprecation(
                // `.emptyRoot` because the conflict is between two coordinates in different
                // sections (a `split` binding and a top-level flag) and `TomlBacktrace` can only
                // name one. Pointing at either alone would be misleading. A `.pair` of backtraces
                // in the error, or a second "see also" field, is what would fix the message.
                .emptyRoot,
                """
                The config contains:
                1. usage of 'split' command
                2. enable-normalization-flatten-containers = true
                These two settings don't play nicely together. 'split' command has no effect when enable-normalization-flatten-containers is enabled.

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
