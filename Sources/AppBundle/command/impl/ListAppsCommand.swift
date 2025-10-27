import AppKit
import Common

struct ListAppsCommand: Command {
    let args: ListAppsCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        var result = Array(MacApp.allAppsMap.values)
        if let hidden = args.macosHidden {
            result = result.filter { $0.nsApp.isHidden == hidden }
        }

        return formatListOutput(
            result,
            countOnly: args.outputOnlyCount,
            json: args.json,
            format: args.format,
            ignoreRightPadding: args._format.isEmpty,
            mapper: { AeroObj.app($0) },
            io: io,
        )
    }
}
