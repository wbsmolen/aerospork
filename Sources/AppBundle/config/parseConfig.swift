import AppKit
import Common
import HotKey
import TOMLKit

@MainActor
func readConfig(forceConfigUrl: URL? = nil) -> Result<(Config, URL), String> {
    let customConfigUrl: URL
    switch findCustomConfigUrl() {
        case .file(let url): customConfigUrl = url
        case .noCustomConfigExists: customConfigUrl = defaultConfigUrl
        case .ambiguousConfigError(let candidates):
            let msg = """
                Ambiguous config error. Several configs found:
                \(candidates.map(\.path).joined(separator: "\n"))
                """
            return .failure(msg)
    }
    let configUrl: URL = forceConfigUrl ?? customConfigUrl
    let (parsedConfig, errors) = (try? String(contentsOf: configUrl)).map { parseConfig($0) } ?? (defaultConfig, [])

    if errors.isEmpty {
        return .success((parsedConfig, configUrl))
    } else {
        let msg = """
            Failed to parse \(configUrl.absoluteURL.path)

            \(errors.map(\.description).joined(separator: "\n\n"))
            """
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
private let modeConfigRootKey = "mode"

// For every new config option you add, think:
// 1. Does it make sense to have different value
// 2. Prefer commands and commands flags over toml options if possible
private let configParser: [String: any ParserProtocol<Config>] = [
    "after-login-command": Parser(\.afterLoginCommand, parseAfterLoginCommand),
    "after-startup-command": Parser(\.afterStartupCommand) { parseCommandOrCommands($0).toParsedToml($1) },

    "on-focus-changed": Parser(\.onFocusChanged) { parseCommandOrCommands($0).toParsedToml($1) },
    "on-focused-monitor-changed": Parser(\.onFocusedMonitorChanged) { parseCommandOrCommands($0).toParsedToml($1) },
    // "on-focused-workspace-changed": Parser(\.onFocusedWorkspaceChanged, { parseCommandOrCommands($0).toParsedToml($1) }),

    "enable-normalization-flatten-containers": Parser(\.enableNormalizationFlattenContainers, parseBool),
    "enable-normalization-opposite-orientation-for-nested-containers": Parser(\.enableNormalizationOppositeOrientationForNestedContainers, parseBool),

    "default-root-container-layout": Parser(\.defaultRootContainerLayout, parseLayout),
    "default-root-container-orientation": Parser(\.defaultRootContainerOrientation, parseDefaultContainerOrientation),

    "start-at-login": Parser(\.startAtLogin, parseBool),
    "automatically-unhide-macos-hidden-apps": Parser(\.automaticallyUnhideMacosHiddenApps, parseBool),
    "accordion-padding": Parser(\.accordionPadding, parseInt),
    "exec-on-workspace-change": Parser(\.execOnWorkspaceChange, parseExecOnWorkspaceChange),
    "exec": Parser(\.execConfig, parseExecConfig),

    keyMappingConfigRootKey: Parser(\.keyMapping, skipParsing(Config().keyMapping)), // Parsed manually
    modeConfigRootKey: Parser(\.modes, skipParsing(Config().modes)), // Parsed manually

    "gaps": Parser(\.gaps, parseGaps),
    "workspace-to-monitor-force-assignment": Parser(\.workspaceToMonitorForceAssignment, parseWorkspaceToMonitorAssignment),
    "on-window-detected": Parser(\.onWindowDetected, parseOnWindowDetectedArray),
    "auto-move-workspaces-on-monitor-connect": Parser(\.autoMoveWorkspacesOnMonitorConnect, parseBool),

    // Deprecated
    "non-empty-workspaces-root-containers-layout-on-startup": Parser(\._nonEmptyWorkspacesRootContainersLayoutOnStartup, parseStartupRootContainerLayout),
    "indent-for-nested-containers-with-the-same-orientation": Parser(\._indentForNestedContainersWithTheSameOrientation, parseIndentForNestedContainersWithTheSameOrientation),

    // New: Workspace Profiles
    "profiles": Parser(\.workspaceProfiles, parseWorkspaceProfiles),
    "active-profile": Parser(\.activeProfileName) { $0.string.toParsedToml($1) }, // Fix for Optional<String>
]

// New parsing function for profiles
private func parseWorkspaceProfiles(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<[Config.WorkspaceProfile]> {
    guard let profilesTable = raw.table else {
        return .failure(expectedActualTypeError(expected: .table, actual: raw.type, backtrace))
    }

    var parsedProfiles: [Config.WorkspaceProfile] = []
    var errors: [TomlParseError] = []

    for (profileName, profileValue) in profilesTable {
        let profileBacktrace = backtrace + .key(profileName)
        guard let profileTable = profileValue.table else {
            errors.append(expectedActualTypeError(expected: .table, actual: profileValue.type, profileBacktrace))
            continue
        }

        var assignments: [Config.WorkspaceAssignment] = []
        if let assignmentsTable = profileTable["workspace-to-monitor-force-assignment"]?.table {
            let assignmentsBacktrace = profileBacktrace + .key("workspace-to-monitor-force-assignment")
            for (workspace, value) in assignmentsTable {
                if var assignment = parseWorkspaceAssignment(workspace: workspace, value: value) {
                    assignment.isForceAssignment = true
                    assignments.append(assignment)
                } else {
                    errors.append(.semantic(assignmentsBacktrace + .key(workspace), "Failed to parse workspace assignment"))
                }
            }
        }
        parsedProfiles.append(Config.WorkspaceProfile(name: profileName, assignments: assignments))
    }

    if errors.isEmpty {
        return .success(parsedProfiles)
    } else {
        return .failure(errors.first!) // Return the first error, or combine them
    }
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

func parseAfterLoginCommand(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<[any Command]> {
    if let array = raw.array, array.count == 0 {
        return .success([])
    }
    let msg = "after-login-command is deprecated since AeroSpace 0.19.0. https://github.com/nikitabobko/AeroSpace/issues/1482"
    return .failure(.semantic(backtrace, msg))
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

@MainActor func parseConfig(_ rawToml: String) -> (config: Config, errors: [TomlParseError]) { // todo change return value to Result
    let rawTable: TOMLTable
    do {
        rawTable = try TOMLTable(string: rawToml)
    } catch let e as TOMLParseError {
        return (defaultConfig, [.syntax(e.debugDescription)])
    } catch let e {
        return (defaultConfig, [.syntax(e.localizedDescription)])
    }

    var errors: [TomlParseError] = []

    var config = rawTable.parseTable(Config(), configParser, .emptyRoot, &errors)

    if let mapping = rawTable[keyMappingConfigRootKey].flatMap({ parseKeyMapping($0, .rootKey(keyMappingConfigRootKey), &errors) }) {
        config.keyMapping = mapping
    }

    if let modes = rawTable[modeConfigRootKey].flatMap({ parseModes($0, .rootKey(modeConfigRootKey), &errors, config.keyMapping.resolve()) }) {
        config.modes = modes
    }

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
            errors += [.semantic(
                .emptyRoot, // todo Make 'split' + flatten normalization prettier
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
    return (config, errors)
}

func parseIndentForNestedContainersWithTheSameOrientation(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
) -> ParsedToml<Void> {
    let msg = "Deprecated. Please drop it from the config. See https://github.com/nikitabobko/AeroSpace/issues/96"
    return .failure(.semantic(backtrace, msg))
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
    _ errors: inout [TomlParseError]
) -> T {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, backtrace))
        return initial
    }
    return table.parseTable(initial, fieldsParser, backtrace, &errors)
}

private func parseStartupRootContainerLayout(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Void> {
    parseString(raw, backtrace)
        .filter(.semantic(backtrace, "'non-empty-workspaces-root-containers-layout-on-startup' is deprecated. Please drop it from your config")) { raw in raw == "smart" }
        .map { _ in () }
}

private func parseLayout(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Layout> {
    parseString(raw, backtrace)
        .flatMap { $0.parseLayout().orFailure(.semantic(backtrace, "Can't parse layout '\($0)'")) }
}

private func skipParsing<T: Sendable>(_ value: T) -> @Sendable (_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<T> {
    { _, _ in .success(value) }
}

private func parseExecOnWorkspaceChange(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<[String]> {
    parseTomlArray(raw, backtrace)
        .flatMap { arr in
            arr.mapAllOrFailure { elem in parseString(elem, backtrace) }
        }
}

private func parseDefaultContainerOrientation(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<DefaultContainerOrientation> {
    parseString(raw, backtrace).flatMap {
        DefaultContainerOrientation(rawValue: $0)
            .orFailure(.semantic(backtrace, "Can't parse default container orientation '\($0)'"))
    }
}

private func parseWorkspaceAssignment(workspace: String, value: TOMLValueConvertible) -> Config.WorkspaceAssignment? {
    if let stringValue = value.string {
        return Config.WorkspaceAssignment(
            workspaceName: workspace,
            monitorDescription: stringValue,
            monitorType: parseMonitorType(from: stringValue)
        )
    } else if let intValue = value.int {
        return Config.WorkspaceAssignment(
            workspaceName: workspace,
            monitorDescription: String(intValue),
            monitorType: .index(intValue)
        )
    } else if let table = value.table {
        let fingerprintTable: TOMLTable?
        
        if let fp = table["fingerprint"]?.table {
            fingerprintTable = fp
        } else if table.keys.contains(where: { ["vendor_id", "model_id", "serial_number", "display_name", "width", "height"].contains($0) }) {
            fingerprintTable = table
        } else if table.count == 1, let firstKey = table.keys.first, firstKey == "fingerprint",
                  let nestedTable = table[firstKey]?.table {
            fingerprintTable = nestedTable
        } else {
            return nil
        }
        
        if let fingerprint = fingerprintTable {
            var fp = Config.WorkspaceAssignment.MonitorFingerprint()
            fp.vendorId = fingerprint["vendor_id"]?.string
            fp.modelId = fingerprint["model_id"]?.string
            fp.serialNumber = fingerprint["serial_number"]?.string
            fp.displayName = fingerprint["display_name"]?.string
            fp.width = fingerprint["width"]?.int
            fp.height = fingerprint["height"]?.int
            
            return Config.WorkspaceAssignment(
                workspaceName: workspace,
                monitorDescription: "Fingerprint",
                monitorType: .fingerprint(fp)
            )
        }
    }
    return nil
}

private func parseMonitorType(from string: String) -> Config.WorkspaceAssignment.MonitorType {
    if let index = Int(string) {
        return .index(index)
    } else {
        return .name(string)
    }
}



func parseBool(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Bool> {
    raw.bool.orFailure(expectedActualTypeError(expected: .bool, actual: raw.type, backtrace))
}



extension TOMLTable {
    func parseTable<T: ConvenienceCopyable>(
        _ initial: T,
        _ fieldsParser: [String: any ParserProtocol<T>],
        _ backtrace: TomlBacktrace,
        _ errors: inout [TomlParseError]
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
