import Common
import TOMLKit

// MARK: - TOML Type Validation Helpers

extension TOMLValueConvertible {
    /// Validates this value is a TOML table, returning ParsedToml
    func expectTable(_ backtrace: TomlBacktrace) -> ParsedToml<TOMLTable> {
        table.orFailure(expectedActualTypeError(expected: .table, actual: type, backtrace))
    }

    /// Validates this value is a TOML array, returning ParsedToml
    func expectArray(_ backtrace: TomlBacktrace) -> ParsedToml<TOMLArray> {
        array.orFailure(expectedActualTypeError(expected: .array, actual: type, backtrace))
    }

    /// Validates this value is a string, returning ParsedToml
    func expectString(_ backtrace: TomlBacktrace) -> ParsedToml<String> {
        string.orFailure(expectedActualTypeError(expected: .string, actual: type, backtrace))
    }

    /// Validates this value is an integer, returning ParsedToml
    func expectInt(_ backtrace: TomlBacktrace) -> ParsedToml<Int> {
        int.orFailure(expectedActualTypeError(expected: .int, actual: type, backtrace))
    }

    /// Validates this value is a boolean, returning ParsedToml
    func expectBool(_ backtrace: TomlBacktrace) -> ParsedToml<Bool> {
        bool.orFailure(expectedActualTypeError(expected: .bool, actual: type, backtrace))
    }
}

// MARK: - Error Collection Helpers

extension Result where Failure == TomlParseError {
    /// Unwraps the value or appends error to the errors array
    func unwrapOrCollect(_ errors: inout [TomlParseError]) -> Success? {
        getOrNil(appendErrorTo: &errors)
    }
}

// MARK: - Enum Parsing Helpers

/// Generic enum parser for string-based enums
func parseEnumValue<E: RawRepresentable>(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    type: E.Type,
    typeName: String
) -> ParsedToml<E> where E.RawValue == String {
    parseString(raw, backtrace).flatMap {
        E(rawValue: $0).orFailure(.semantic(backtrace, "Can't parse \(typeName) '\($0)'"))
    }
}
