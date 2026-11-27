public typealias Parsed<T> = Result<T, String>

public enum TomlParseError: Error, CustomStringConvertible, Equatable {
    case semantic(_ backtrace: TomlBacktrace, _ message: String)
    case syntax(_ message: String)
    /// An obsolete key. Reported, but the config still loads.
    ///
    /// Severity lives in the TYPE rather than in a lookup table of deprecated top-level names,
    /// because a deprecated key can be NESTED: the legacy `if.during-…-startup` alias sits under
    /// `on-window-detected`, whose root key is perfectly live, so a root-key lookup classifies it
    /// as fatal -- and a fatal error there drops the whole window rule.
    case deprecation(_ backtrace: TomlBacktrace, _ message: String)

    public var isDeprecation: Bool { if case .deprecation = self { true } else { false } }

    public var description: String {
        return switch self {
            case .semantic(let backtrace, let message), .deprecation(let backtrace, let message):
                backtrace.isEmptyRoot ? message : "\(backtrace): \(message)"
            case .syntax(let message): message
        }
    }
}

public typealias ParsedToml<T> = Result<T, TomlParseError>

public indirect enum TomlBacktrace: CustomStringConvertible, Equatable, Sendable {
    case emptyRoot
    case rootKey(String)
    case key(String)
    case index(Int)
    case pair(TomlBacktrace, TomlBacktrace)

    public var description: String {
        return switch self {
            case .emptyRoot: dieT("Impossible")
            case .rootKey(let value): value
            case .key(let value): "." + value
            case .index(let index): "[\(index)]"
            case .pair(let first, let second): first.description + second.description
        }
    }

    public var isEmptyRoot: Bool {
        return switch self {
            case .emptyRoot: true
            default: false
        }
    }

    public var isRootKey: Bool {
        return switch self {
            case .rootKey: true
            default: false
        }
    }

    public static func + (lhs: TomlBacktrace, rhs: TomlBacktrace) -> TomlBacktrace {
        if case .emptyRoot = lhs {
            if case .key(let newRoot) = rhs {
                return .rootKey(newRoot)
            } else {
                die("Impossible")
            }
        } else {
            return pair(lhs, rhs)
        }
    }
}

extension Parsed where Failure == String {
    public func toParsedToml(_ backtrace: TomlBacktrace) -> ParsedToml<Success> {
        mapError { .semantic(backtrace, $0) }
    }
}

// `Result<T, String>` and `Result<T, [String]>` are the parser error type throughout. `@retroactive`
// makes an SDK that adds these conformances itself a build error rather than a silent behaviour
// change; the fix then is to delete these two lines. A hand-written Result-like type would avoid
// both, and would also cost every `map`/`flatMap`/`try` interop the stdlib gives us for free.
extension String: @retroactive Error {}
extension Array: @retroactive Error where Element: Error {}

extension String {
    public func trim() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func prefixLines(with: String) -> String {
        split(separator: "\n", omittingEmptySubsequences: false).map { with + $0 }.joined(separator: "\n")
    }

    public func quoted(with char: String) -> String { char + self + char }
    public var singleQuoted: String { "'" + self + "'" }
    public var doubleQuoted: String { "\"" + self + "\"" }
}

extension [String] {
    /// CLI-side formatting: `ERROR: ` and a hanging indent for continuation lines.
    ///
    /// Deliberately NOT used by `readConfig`, which joins with a blank line instead: a config error
    /// already carries a `gaps.inner.horizontal:` backtrace prefix, and stacking `ERROR: ` in front
    /// of that reads worse, not better. Reuse would also rewrite every string the config-error
    /// tests assert on.
    public func joinErrors() -> String {
        map { (error: String) -> String in
            error.split(separator: "\n").enumerated()
                .map { (i, line) in
                    i == 0
                        ? "ERROR: " + line
                        : "       " + line
                }
                .joined(separator: "\n")
        }
        .joined(separator: "\n")
    }

    public func joinTruncating(separator: String, length maxLength: Int, trailing: String = "…") -> String {
        if isEmpty {
            return ""
        }
        var remainingLen = maxLength
        let separatorCount = separator.count
        var result: String = first.orDie()
        for _elem in self.dropFirst() {
            let elemCount = separatorCount + _elem.count
            if remainingLen < elemCount / 2 {
                return result + separator + trailing
            }
            let elem = separator + _elem
            if elemCount < remainingLen {
                result += elem
                remainingLen -= elemCount
            } else {
                return result + elem.prefix(remainingLen) + trailing
            }
        }
        return result
    }
}

extension [[String]] {
    public func toPaddingTable(columnSeparator: String = " | ") -> [String] {
        let pads: [Int] = transposed().map { column in column.map { $0.count }.max().orDie() }
        return self.map { (row: [String]) in
            zip(row.enumerated(), pads)
                .map { (elem: (Int, String), pad: Int) in
                    elem.0 != row.count - 1 ? elem.1.padding(toLength: pad, withPad: " ", startingAt: 0) : elem.1
                }
                .joined(separator: columnSeparator)
        }
    }
}

extension Array {
    public func transposed<T>() -> [[T]] where Self.Element == [T] {
        if isEmpty {
            return []
        }
        let table: [[T]] = self
        var result: [[T]] = []
        for columnIndex in 0... {
            if columnIndex < table.first.orDie().count {
                result += [table.map { row in row.getOrNil(atIndex: columnIndex).orDie() }]
            } else {
                break
            }
        }
        return result
    }
}

extension String {
    public func interpolate(with variables: [String: String], interpolationChar: Character = "$") -> Result<String, [String]> {
        interpolationTokens(interpolationChar: interpolationChar)
            .mapError { [$0] }
            .flatMap { tokens in
                tokens.mapAllOrFailures { token in
                    switch token {
                        case .literal(let literal): .success(literal)
                        case .interVar(let value):
                            variables[value].flatMap(Result.success)
                                ?? .failure("Env variable '\(value)' isn't presented in AeroSpork.app env vars, " +
                                    "or not available for interpolation (because it's mutated)")
                    }
                }
            }
            .map { $0.joined(separator: "") }
    }

    public func interpolationTokens(interpolationChar: Character = "$") -> Result<[StringInterToken], String> {
        var mode: InterpolationParserState = .stringLiteral
        var result: [StringInterToken] = []
        var literal: String = ""
        for char: Character? in (Array(self) + [nil]) {
            switch (mode, char) { // State machine
                case (.stringLiteral, interpolationChar):
                    mode = .dollarEncountered
                case (.stringLiteral, _):
                    if let char {
                        literal.append(char)
                    } else {
                        result.append(.literal(literal))
                    }
                case (.dollarEncountered, "{"):
                    mode = .interpolatedValue("")
                    result.append(.literal(literal))
                    literal = ""
                case (.dollarEncountered, interpolationChar):
                    literal.append(interpolationChar)
                case (.dollarEncountered, _):
                    literal.append(interpolationChar)
                    if let char {
                        literal.append(char)
                    } else {
                        result.append(.literal(literal))
                    }
                    mode = .stringLiteral
                case (.interpolatedValue(let value), "}"):
                    result.append(.interVar(value))
                    mode = .stringLiteral
                case (.interpolatedValue(let value), "{"):
                    return .failure("Can't parse '\(value + "{")' inside interpolation (Open curly brace is invalid character)")
                case (.interpolatedValue(let value), interpolationChar):
                    return .failure("Can't parse '\(value + .init(interpolationChar))' inside interpolation ('\(interpolationChar)' is disallowed character)")
                case (.interpolatedValue(let value), _):
                    if let char {
                        mode = .interpolatedValue(value + .init(char))
                    } else {
                        return .failure("Unbalanced curly braces")
                    }
            }
        }
        return .success(result.filter { $0 != .literal("") })
    }
}

public enum StringInterToken: Equatable, Sendable {
    case literal(String)
    case interVar(String) // "interpolation variable"
}

private enum InterpolationParserState {
    case stringLiteral, dollarEncountered
    case interpolatedValue(String)
}
