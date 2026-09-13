import AppKit
import Common

struct ExecAndForgetCommand: Command {
    let args: ExecAndForgetCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        // todo shall exec-and-forget fork exec session?
        // It doesn't throw if exit code is non-zero
        Result { try execAndForgetProcess(args.bashScript, env).run() }.isSuccess
    }
}

/// The child `exec-and-forget` spawns, not yet launched, so what it would receive can be checked.
///
/// `env.asMap`, not the bare config environment it used before. That dropped every variable the docs
/// promise -- `AEROSPORK_WINDOW_ID`, `AEROSPORK_WORKSPACE`, and for `on-focused-workspace-changed` the
/// `AEROSPORK_FOCUSED_WORKSPACE`/`AEROSPORK_PREV_WORKSPACE` pair -- so the replacement the deprecation
/// notice recommends for `exec-on-workspace-change` handed status bars empty strings.
@MainActor func execAndForgetProcess(_ bashScript: String, _ env: CmdEnv) -> Process {
    let process = Process()
    process.environment = env.asMap
    process.executableURL = URL(filePath: "/bin/bash")
    process.arguments = ["-c", bashScript]
    return process
}
