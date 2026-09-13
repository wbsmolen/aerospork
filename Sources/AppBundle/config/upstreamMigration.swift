import Common
import Foundation
import TOMLKit

// Everything that has to spell the upstream product's name lives in this file, and only here.
//
// `BrandingTest` forbids that name in every other owned source and exempts this file alone:
// recognising a config brought over from upstream -- its file name, its environment variables, its
// CLI, its keys -- means naming them. One file is what keeps the exemption from spreading.

/// Upstream's own config, when a migrating user has one. It is never read, so without a hint the
/// first launch runs the default keymap and looks as if AeroSpork ignored the user's config.
func aerospaceConfigLeftBehind(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    xdgConfigHome: URL? = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) },
) -> URL? {
    [
        home.appending(path: ".aerospace.toml"),
        (xdgConfigHome ?? home.appending(path: ".config/")).appending(path: "aerospace").appending(path: "aerospace.toml"),
    ].first { FileManager.default.fileExists(atPath: $0.path) }
}

/// What to tell a user whose only config is upstream's, or nil when there is nothing to say.
func upstreamConfigLeftBehindHint() -> String? {
    aerospaceConfigLeftBehind().map {
        "No AeroSpork config found, but \($0.path) exists. AeroSpork does not read AeroSpace's config; copy it to ~/\(configDotfileName) to use it."
    }
}

/// Top-level keys only upstream has, merged into `configParser`. A migrated config usually carries
/// some, and an unknown top-level key is fatal -- so one of these used to cost the user the whole
/// config, which then fell back to the default keymap. Reported and ignored instead.
let upstreamOnlyKeyParsers: [String: any ParserProtocol<Config>] = [
    "config-version": Parser(\._deprecatedNoOp, ignored(
        "config-version is an AeroSpace setting. AeroSpork has one config schema and ignores it.")),
    "auto-reload-config": Parser(\._deprecatedNoOp, ignored(
        "auto-reload-config is an AeroSpace setting. AeroSpork always reloads a saved config, so it is ignored.")),
    "on-mode-changed": Parser(\._deprecatedNoOp, ignored(
        "on-mode-changed is an AeroSpace callback AeroSpork does not have. It is ignored.")),
    "focus-follows-mouse": Parser(\._deprecatedNoOp, ignored(
        "focus-follows-mouse is an AeroSpace setting AeroSpork does not support. It is ignored.")),
]

/// The same severity as a deprecated key, without calling a key AeroSpork never had "deprecated".
private func ignored(_ message: String) -> @Sendable (TOMLValueConvertible, TomlBacktrace) -> ParsedToml<Void> {
    { _, backtrace in .failure(.deprecation(backtrace, message)) }
}

/// For upstream's newer `[[on-window-detected]] if = 'test %{...}'`. Still an error -- the rule cannot
/// be honoured -- but one that names the fix, where the generic "expected table" did not.
let upstreamStringIfMessage =
    "A string 'if' (AeroSpace's 'test %{...}' syntax) is not supported. Use a table instead: if.app-id = '...', or if.window-title-regex-substring = '...'"

/// Upstream-branded names on a line of config. Both fail without an error -- `$AEROSPACE_FOCUSED_WORKSPACE`
/// expands to nothing and `aerospace` is not on `PATH` -- so a migrated status-bar hook runs and does
/// nothing. A warning, not an error: the rest of the config is fine. Comment lines are skipped, so a note
/// about the rename does not warn about itself.
func upstreamNameWarnings(_ rawToml: String) -> [TomlParseError] {
    var warnings: [TomlParseError] = []
    for (index, line) in rawToml.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
        if line.contains("AEROSPACE_") {
            warnings.append(.deprecation(.emptyRoot, "Line \(index + 1): AEROSPACE_* variables are never set. AeroSpork exports AEROSPORK_* instead, for example AEROSPORK_FOCUSED_WORKSPACE."))
        }
        if line.range(of: #"(^|[^A-Za-z0-9_.-])aerospace\s"#, options: .regularExpression) != nil {
            warnings.append(.deprecation(.emptyRoot, "Line \(index + 1): runs `aerospace`, which is AeroSpace's CLI. AeroSpork's is `aerospork`."))
        }
    }
    return warnings
}
