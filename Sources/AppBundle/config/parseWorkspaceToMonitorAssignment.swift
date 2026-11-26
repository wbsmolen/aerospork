import Common
import TOMLKit

func parseWorkspaceToMonitorAssignment(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> [String: [MonitorDescription]] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: [MonitorDescription]] = [:]
    for (workspaceName, rawMonitorDescription) in rawTable {
        result[workspaceName] = parseMonitorDescriptions(rawMonitorDescription, backtrace + .key(workspaceName), &errors)
    }
    return result
}

func parseMonitorDescriptions(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ errors: inout [TomlParseError]) -> [MonitorDescription] {
    if let array = raw.array {
        return array.enumerated()
            .map { (index, rawDesc) in parseMonitorDescription(rawDesc, backtrace + .index(index), &errors).getOrNil(appendErrorTo: &errors) }
            .filterNotNil()
    } else {
        return parseMonitorDescription(raw, backtrace, &errors).getOrNil(appendErrorTo: &errors).asList()
    }
}

/// `warnings` gets what loads anyway, such as a fingerprint field written twice.
func parseMonitorDescription(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ warnings: inout [TomlParseError]) -> ParsedToml<MonitorDescription> {
    // Check if it's a table (fingerprint pattern). `{ fingerprint = { … } }` is the v1 spelling;
    // v2 drops the wrapper, because a table here can only ever have meant a fingerprint.
    if let table = raw.table {
        if let fingerprintTable = table["fingerprint"]?.table {
            return parseFingerprintPattern(fingerprintTable, backtrace + .key("fingerprint"), &warnings)
        } else {
            return parseFingerprintPattern(table, backtrace, &warnings)
        }
    }

    // Otherwise parse as string/int
    let rawString: String
    if let string = raw.string {
        rawString = string
    } else if let int = raw.int {
        rawString = String(int)
    } else {
        return .failure(expectedActualTypeError(expected: [.string, .int, .table], actual: raw.type, backtrace))
    }

    return parseMonitorDescription(rawString).toParsedToml(backtrace)
}

private func parseFingerprintPattern(_ table: TOMLTable, _ backtrace: TomlBacktrace, _ warnings: inout [TomlParseError]) -> ParsedToml<MonitorDescription> {
    var vendorID: UInt32?
    var modelID: UInt32?
    var serialNumber: String?
    var displayNamePattern: String?
    var widthPixels: Int?
    var heightPixels: Int?
    var displayUUID: String?

    // Every alias spelling stays: users' configs use them. Two spellings of one field used to let
    // whichever TOMLKit iterates last win, with no word. An error would reject a config that loads.
    var spellings: [String: String] = [:]
    for (key, value) in table {
        let keyBacktrace = backtrace + .key(key)
        func note(_ field: String) {
            if let other = spellings.updateValue(key, forKey: field) {
                warnings.append(.deprecation(keyBacktrace, "\(other) and \(key) are two spellings of one field, and only one of them is used. Keep one."))
            }
        }
        switch key {
            case "vendor", "vendor_id", "vendorID":
                note("vendor")
                switch parseEdidId(value, keyBacktrace, "vendor_id", example: "0x1234") {
                    case .success(let v): vendorID = v
                    case .failure(let error): return .failure(error)
                }
            case "model", "model_id", "modelID":
                note("model")
                switch parseEdidId(value, keyBacktrace, "model_id", example: "0x5678") {
                    case .success(let v): modelID = v
                    case .failure(let error): return .failure(error)
                }
            case "serial", "serial_number", "serialNumber":
                note("serial")
                guard let string = value.string else {
                    return .failure(expectedActualTypeError(expected: .string, actual: value.type, keyBacktrace))
                }
                serialNumber = string
            case "name", "display_name", "displayName":
                note("name")
                guard let string = value.string else {
                    return .failure(expectedActualTypeError(expected: .string, actual: value.type, keyBacktrace))
                }
                displayNamePattern = string
            case "width", "width_pixels", "widthPixels":
                note("width")
                guard let int = value.int else {
                    return .failure(expectedActualTypeError(expected: .int, actual: value.type, keyBacktrace))
                }
                widthPixels = int
            case "height", "height_pixels", "heightPixels":
                note("height")
                guard let int = value.int else {
                    return .failure(expectedActualTypeError(expected: .int, actual: value.type, keyBacktrace))
                }
                heightPixels = int
            case "uuid", "display_uuid", "displayUUID":
                note("uuid")
                guard let string = value.string else {
                    return .failure(expectedActualTypeError(expected: .string, actual: value.type, keyBacktrace))
                }
                displayUUID = string
            default:
                return .failure(unknownKeyError(keyBacktrace))
        }
    }

    let patternData = MonitorFingerprintPatternData(
        vendorID: vendorID,
        modelID: modelID,
        serialNumber: serialNumber,
        displayNamePattern: displayNamePattern,
        widthPixels: widthPixels,
        heightPixels: heightPixels,
        displayUUID: displayUUID,
    )

    return .success(.fingerprint(patternData))
}

/// An EDID vendor or model id: an integer, or a `0x` hex string. `UInt32(exactly:)` and a nil check on
/// the hex parse: `-1` or a value past 32 bits must be a config error, not a crash, and `0xZZZZ` must
/// not be silently dropped (a dropped field silently WIDENS the match).
private func parseEdidId(_ value: TOMLValueConvertible, _ backtrace: TomlBacktrace, _ name: String, example: String) -> ParsedToml<UInt32> {
    if let int = value.int, let v = UInt32(exactly: int) { return .success(v) }
    if let string = value.string, string.hasPrefix("0x") || string.hasPrefix("0X"), let v = UInt32(string.dropFirst(2), radix: 16) {
        return .success(v)
    }
    return .failure(.semantic(backtrace, "\(name) must be a 32-bit unsigned integer or hex string (e.g., '\(example)')"))
}
