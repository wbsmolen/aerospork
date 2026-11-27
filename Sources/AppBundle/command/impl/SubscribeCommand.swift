import AppKit
import Common

/// The server streams `subscribe` itself, before any session: see `streamEvents` in server.swift. Nothing else
/// reaches `run`, because the config rejects a command that works only from the CLI.
struct SubscribeCommand: Command {
    let args: SubscribeCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        io.err("subscribe works only from the CLI")
    }
}
