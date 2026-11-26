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
    // Before the read, for the watcher. Not for a dry run, which applies nothing, nor for the forced
    // read of the bundled default, which is not the user's file.
    let applied = args.dryRun || forceConfigUrl != nil ? nil : ConfigSnapshot.now()
    let result = readConfig(forceConfigUrl: forceConfigUrl, warnings: &warnings)
    // A dry run promises to change nothing, and that includes what the banner says.
    if !args.dryRun { recordConfigHealth(result, warnings: warnings, searched: forceConfigUrl == nil) }
    // A failure too, so saving the same broken bytes again does not raise a second dialog.
    if let applied { ConfigFileWatcher.recordApplied(applied) }
    switch result {
        case .success(let (parsedConfig, url)):
            if !args.dryRun { apply(parsedConfig, url: url) }
            logConfigLoaded(url, warnings)
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

/// A Settings save's apply, right after the write. `refusal` (or `validate`) already parsed what was
/// written, so a file that reads back as exactly those bytes gets that config without a second parse.
/// Anything else, such as an edit that landed after the write, gets the full reload: the running
/// config is always what is on disk. Either way the bytes applied are recorded, so the watcher, which
/// sees the write, does not reload them again.
@MainActor func applySavedConfig(_ validated: ConfigurationWriter.Validated?) -> Bool {
    let onDisk = ConfigSnapshot.now()
    guard let validated, let url = onDisk.file.urlOrNil, onDisk.bytes == Data(validated.text.utf8) else { return reloadConfig() }
    recordConfigHealth(.success((validated.config, url)), warnings: validated.warnings)
    ConfigFileWatcher.recordApplied(onDisk)
    apply(validated.config, url: url)
    logConfigLoaded(url, validated.warnings)
    return true
}

@MainActor private func apply(_ parsedConfig: Config, url: URL) {
    config = parsedConfig
    configUrl = url
    activateMode(activeMode)
    syncStartAtLogin()
}

/// The single most useful line in a bug report: which file the running app is actually on.
/// `readConfig` already prints warnings, but only to stderr -- and a .app launched by launchd has
/// nowhere for stderr to go, so that record did not survive the session.
@MainActor private func logConfigLoaded(_ url: URL, _ warnings: [String]) {
    AppLog.config.notice("Config loaded: \(url.path, privacy: .public)")
    for warning in warnings {
        AppLog.config.notice("Config warning: \(warning, privacy: .public)")
    }
}
