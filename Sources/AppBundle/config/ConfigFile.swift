import Common
import Foundation

let configDotfileName = isDebug ? ".aerospork-debug.toml" : ".aerospork.toml"

/// Where a user config may live, in the order they are listed in an ambiguity error.
func customConfigCandidates() -> [URL] {
    if let configLocation = serverArgs.configLocation { return [URL(filePath: configLocation)] }
    let fileName = isDebug ? "aerospork-debug.toml" : "aerospork.toml"
    let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
    return [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName),
        xdgConfigHome.appending(path: "aerospork").appending(path: fileName),
    ]
}

func findCustomConfigUrl(among candidates: [URL] = customConfigCandidates()) -> ConfigFile {
    let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
    // `fileExists` follows links, so a dangling one (a dotfiles repo not checked out yet, an unmounted
    // volume) read as "no config": the defaults ran with no word, and the first Settings save replaced
    // the link with a regular file. It is the user's config, so reading it fails and says why. Only
    // when no real file exists, so a stale link next to a working config changes nothing.
    let found = existing.isEmpty ? candidates.filter { danglingLinkDestination($0) != nil } : existing
    return switch found.count {
        case 0: .noCustomConfigExists
        case 1: .file(found.first.orDie())
        default: .ambiguousConfigError(found)
    }
}

/// Where the link at `url` points, when it is a link to nothing.
func danglingLinkDestination(_ url: URL) -> String? {
    guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path),
          !FileManager.default.fileExists(atPath: url.path) else { return nil }
    return destination
}

/// The config text at `url`, or a sentence saying why it can't be read.
///
/// Any failure here used to read as "no config", so the defaults ran with no banner while the log
/// said the user's file had loaded, and a save then replaced a file nobody could see. TOML is UTF-8
/// by definition. The read without an encoding did not guess either: it gave nil for a Latin-1 file.
func readConfigText(at url: URL) -> Result<String, String> {
    if let destination = danglingLinkDestination(url) {
        return .failure("\(url.path) is a link to \(destination), which does not exist")
    }
    do {
        return .success(try String(contentsOf: url, encoding: .utf8))
    } catch {
        let error = error as NSError
        if let posix = error.userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain {
            return .failure("Can't read \(url.path): \(String(cString: strerror(Int32(posix.code))).lowercased())")
        }
        if error.domain == NSCocoaErrorDomain,
           [CocoaError.fileReadCorruptFile.rawValue, CocoaError.fileReadInapplicableStringEncoding.rawValue].contains(error.code)
        {
            return .failure("\(url.path) isn't UTF-8 text")
        }
        return .failure("Can't read \(url.path): \(error.localizedDescription)")
    }
}

enum ConfigFile {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists

    var urlOrNil: URL? {
        return switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}
