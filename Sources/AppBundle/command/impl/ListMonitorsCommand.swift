import AppKit
import Common

struct ListMonitorsCommand: Command {
    let args: ListMonitorsCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let focus = focus
        var result = sortedMonitors
        if let focused = args.focused {
            result = result.filter { (monitor) in (monitor.activeWorkspace == focus.workspace) == focused }
        }
        if let mouse = args.mouse {
            let mouseWorkspace = mouseLocation.monitorApproximation.activeWorkspace
            result = result.filter { (monitor) in (monitor.activeWorkspace == mouseWorkspace) == mouse }
        }

        return formatListOutput(
            result,
            countOnly: args.outputOnlyCount,
            json: args.json,
            format: args.format,
            ignoreRightPadding: args._format.isEmpty,
            mapper: { AeroObj.monitor($0) },
            io: io,
        )
    }
}
