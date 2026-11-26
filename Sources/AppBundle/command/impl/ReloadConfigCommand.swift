import AppKit
import Common

struct ReloadConfigCommand: Command {
    let args: ReloadConfigCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        var stdout = ""
        let isOk = reloadConfig(args: args, stdout: &stdout)
        if !stdout.isEmpty {
            io.out(stdout)
        }
        return isOk
    }
}

@MainActor func reloadConfig(forceConfigUrl: URL? = nil) -> Bool {
    var devNull = ""
    return reloadConfig(forceConfigUrl: forceConfigUrl, stdout: &devNull)
}

@MainActor func reloadConfig(
    args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []),
    forceConfigUrl: URL? = nil,
    stdout: inout String,
) -> Bool {
    var warnings: [String] = []
    let result = readConfig(forceConfigUrl: forceConfigUrl, warnings: &warnings)
    // A dry run promises to change nothing, and that includes what the banner says.
    if !args.dryRun { recordConfigHealth(result, warnings: warnings) }
    switch result {
        case .success(let (parsedConfig, url)):
            if !args.dryRun {
                config = parsedConfig
                configUrl = url
                activateMode(activeMode)
                syncStartAtLogin()
            }
            // The single most useful line in a bug report: which file the running app is actually
            // on. `readConfig` already prints warnings, but only to stderr -- and a .app launched by
            // launchd has nowhere for stderr to go, so that record did not survive the session.
            AppLog.config.notice("Config loaded: \(url.path, privacy: .public)")
            for warning in warnings {
                AppLog.config.notice("Config warning: \(warning, privacy: .public)")
            }
            return true
        case .failure(let msg):
            AppLog.config.error("Config not loaded: \(msg, privacy: .public)")
            stdout.append(msg)
            if !args.noGui {
                showMessageInGui(
                    filenameIfConsoleApp: nil,
                    title: "AeroSpork Config Error",
                    message: msg,
                )
            }
            return false
    }
}
