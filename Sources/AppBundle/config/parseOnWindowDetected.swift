import Common
import TOMLKit

struct WindowDetectedCallback: ConvenienceCopyable, Equatable {
    var matcher: WindowDetectedCallbackMatcher = WindowDetectedCallbackMatcher()
    var checkFurtherCallbacks: Bool = false
    var rawRun: [any Command]? = nil

    var run: [any Command] {
        rawRun ?? dieT("ID-46D063B2 should have discarded nil")
    }

    var debugJson: Json {
        var result: [String: Json] = [:]
        result["matcher"] = matcher.debugJson
        if let commands = rawRun {
            result["commands"] = .string(commands.prettyDescription)
        }
        return .dict(result)
    }

    static func == (lhs: WindowDetectedCallback, rhs: WindowDetectedCallback) -> Bool {
        return lhs.matcher == rhs.matcher && lhs.checkFurtherCallbacks == rhs.checkFurtherCallbacks &&
            zip(lhs.run, rhs.run).allSatisfy { $0.equals($1) }
    }
}

struct WindowDetectedCallbackMatcher: ConvenienceCopyable, Equatable {
    var appId: String?
    var appNameRegexSubstring: Regex<AnyRegexOutput>?
    var windowTitleRegexSubstring: Regex<AnyRegexOutput>?
    var workspace: String?
    var duringAeroSporkStartup: Bool?

    var debugJson: Json {
        var resultParts: [String] = []
        if let appId {
            resultParts.append("appId=\"\(appId)\"")
        }
        if appNameRegexSubstring != nil {
            resultParts.append("appNameRegexSubstrin=Regex")
        }
        if windowTitleRegexSubstring != nil {
            resultParts.append("windowTitleRegexSubstring=Regex")
        }
        if let workspace {
            resultParts.append("workspace=\"\(workspace)\"")
        }
        if let duringAeroSporkStartup {
            // Spelled as the TOML key the user wrote, not as the Swift property, so `debug-windows`
            // output can be pasted straight back into a config.
            resultParts.append("during-aerospork-startup=\(duringAeroSporkStartup)")
        }
        return .string(resultParts.joined(separator: ", "))
    }

    static func == (lhs: WindowDetectedCallbackMatcher, rhs: WindowDetectedCallbackMatcher) -> Bool {
        check(
            lhs.appNameRegexSubstring == nil &&
                lhs.windowTitleRegexSubstring == nil &&
                rhs.appNameRegexSubstring == nil &&
                rhs.windowTitleRegexSubstring == nil,
        )
        return lhs.appId == rhs.appId
    }
}

private let windowDetectedParser: [String: any ParserProtocol<WindowDetectedCallback>] = [
    "if": Parser(\.matcher, parseMatcher),
    "check-further-callbacks": Parser(\.checkFurtherCallbacks, parseBool),
    "run": Parser(\.rawRun, upcast { parseCommandOrCommands($0).toParsedToml($1) }),
]

private let matcherParsers: [String: any ParserProtocol<WindowDetectedCallbackMatcher>] = [
    "app-id": Parser(\.appId, upcast(parseString)),
    "workspace": Parser(\.workspace, upcast(parseString)),
    "app-name-regex-substring": Parser(\.appNameRegexSubstring, upcast(parseCasInsensitiveRegex)),
    "window-title-regex-substring": Parser(\.windowTitleRegexSubstring, upcast(parseCasInsensitiveRegex)),
    // The upstream spelling of this key was removed, not aliased: an unknown key is fatal here, so
    // a config still using it is rejected with `Unknown key` naming the exact line.
    "during-aerospork-startup": Parser(\.duringAeroSporkStartup, upcast(parseBool)),
]

private func upcast<T>(_ fun: @escaping @Sendable (TOMLValueConvertible, TomlBacktrace) -> ParsedToml<T>) -> @Sendable (TOMLValueConvertible, TomlBacktrace) -> ParsedToml<T?> {
    { fun($0, $1).map { $0 } }
}

func parseOnWindowDetectedArray(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> [WindowDetectedCallback] {
    guard let array = raw.expectArray(backtrace).unwrapOrCollect(&errors) else {
        return []
    }
    return array.enumerated().map { (index, raw) in parseWindowDetectedCallback(raw, backtrace + .index(index), &errors) }.filterNotNil()
}

private func parseCasInsensitiveRegex(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Regex<AnyRegexOutput>> {
    parseString(raw, backtrace).flatMap { parseCaseInsensitiveRegex($0).toParsedToml(backtrace) }
}

private func parseMatcher(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> WindowDetectedCallbackMatcher {
    // Upstream now writes `if = 'test %{app-bundle-id} == ...'`; see `upstreamStringIfMessage`.
    if raw.string != nil {
        errors.append(.semantic(backtrace, upstreamStringIfMessage))
        return WindowDetectedCallbackMatcher()
    }
    return parseTable(raw, WindowDetectedCallbackMatcher(), matcherParsers, backtrace, &errors)
}

/// Internal, not private: `[on-window]` desugars into this exact shape, so the rules about what a
/// window callback may run stay enforced in one place.
func parseWindowDetectedCallback(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> WindowDetectedCallback? {
    var myErrors: [TomlParseError] = []
    let callback = parseTable(raw, WindowDetectedCallback(), windowDetectedParser, backtrace, &myErrors)

    if callback.rawRun == nil { // ID-46D063B2
        myErrors.append(.semantic(backtrace, "'run' is mandatory key"))
    }

    let run = callback.rawRun ?? []

    // - 'exec' is prohibited because command-subject isn't yet supported in "exec session"
    // - Commands that change focus are prohibited because the design isn't yet clear
    if !run.allSatisfy({
        let layoutArg = ($0 as? LayoutCommand)?.args.toggleBetween.val.singleOrNil()
        return layoutArg == .floating || layoutArg == .tiling || $0 is MoveNodeToWorkspaceCommand
    }) {
        myErrors.append(.semantic(
            backtrace,
            "For now, 'layout floating', 'layout tiling' and 'move-node-to-workspace' are the only commands that are supported in 'on-window-detected'. " +
                "Please report your use cases to https://github.com/wbsmolen/aerospork/issues/20",
        ))
    }

    let count = run.count(where: { $0 is MoveNodeToWorkspaceCommand })
    if count >= 1 && !(run.last is MoveNodeToWorkspaceCommand) {
        myErrors.append(.semantic(
            backtrace,
            "For now, 'move-node-to-workspace' must be the latest instruction in the callback (otherwise it's error-prone). " +
                "Please report your use cases to https://github.com/wbsmolen/aerospork/issues/20",
        ))
    }

    if count > 1 {
        myErrors.append(.semantic(
            backtrace,
            "For now, 'move-node-to-workspace' can be mentioned only once in 'run' callback. " +
                "Please report your use cases to https://github.com/wbsmolen/aerospork/issues/20",
        ))
    }

    errors += myErrors
    // A deprecation must not cost the user the rule. Dropping the callback here is what "fatal"
    // means locally -- the whole `[[on-window-detected]]` entry disappears -- so only real errors
    // may do it.
    if myErrors.contains(where: { !$0.isDeprecation }) {
        return nil
    }

    return callback
}
