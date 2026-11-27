import AppKit
import Common

struct ListModesCommand: Command {
    let args: ListModesCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        let modeNames: [String] = args.current ? [activeMode ?? mainModeId] : config.modes.map { $0.key }
        guard args.json else { return io.out(modeNames) }
        // An array of names, like `config --get mode --keys --json`.
        return JSONEncoder.aeroSporkDefault.encodeToString(modeNames).map(io.out) ?? io.err("Can't encode the mode names to JSON")
    }
}
