import Common
import TOMLKit

func parseCommand(_ raw: String) -> ParsedCmd<any Command> {
    debugLog("PARSECOMMAND: Parsing command string: '\(raw)'")
    if raw.starts(with: "exec-and-forget") {
        return .cmd(ExecAndForgetCommand(args: ExecAndForgetCmdArgs(bashScript: raw.removePrefix("exec-and-forget"))))
    }
    switch raw.splitArgs() {
        case .success(let args):
            debugLog("PARSECOMMAND: Split into args: \(args)")
            return parseCommand(args)
        case .failure(let fail):
            return .failure(fail)
    }
}

func parseCommand(_ args: [String]) -> ParsedCmd<any Command> {
    debugLog("PARSECOMMAND: Parsing command args: \(args)")
    let result = parseCmdArgs(args).map { $0.toCommand() }
    switch result {
        case .cmd(let command):
            debugLog("PARSECOMMAND: Successfully parsed command: \(String(describing: Swift.type(of: command)))")
        case .failure(let error):
            debugLog("PARSECOMMAND: Failed to parse command: \(error)")
        case .help(let help):
            debugLog("PARSECOMMAND: Help requested: \(help)")
    }
    return result
}

func expectedActualTypeError(expected: TOMLType, actual: TOMLType) -> String {
    "Expected type is '\(expected)'. But actual type is '\(actual)'"
}

func expectedActualTypeError(expected: [TOMLType], actual: TOMLType) -> String {
    if let single = expected.singleOrNil() {
        return expectedActualTypeError(expected: single, actual: actual)
    } else {
        return "Expected types are \(expected.map { "'\($0.description)'" }.joined(separator: " or ")). But actual type is '\(actual)'"
    }
}
