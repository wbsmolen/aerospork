import Common
import Darwin
import Foundation

extension Notification.Name {
    /// Posted after the config was reloaded because the file changed on disk (not from a GUI save).
    static let aerosporkConfigReloadedExternally = Notification.Name("aerosporkConfigReloadedExternally")
}

/// What the user's config is at one moment: the file the search finds, and its bytes (nil when it
/// can't be read). The watcher reloads only when this differs from the one last applied.
struct ConfigSnapshot: Equatable {
    let file: ConfigFile
    let bytes: Data?

    var isMissing: Bool { file == .noCustomConfigExists }

    @MainActor static func now() -> ConfigSnapshot {
        let file = searchUserConfig() ?? .noCustomConfigExists
        return ConfigSnapshot(file: file, bytes: file.urlOrNil.flatMap { try? Data(contentsOf: $0) })
    }
}

/// Watches the user's config and hot-reloads it on change, so edits from an external editor apply
/// without a manual `reload-config`.
///
/// It watches the file and the folders around it. A folder watch never goes stale, so it sees a
/// config that appears, an atomic replace, a delete, and a swapped link (home-manager swaps one on
/// every switch), none of which a file descriptor alone survives. Every event re-arms and compares
/// the config with the one last applied, so the app's own saves, which apply themselves, reload once.
@MainActor
enum ConfigFileWatcher {
    private static var sources: [DispatchSourceFileSystemObject] = []
    private static var debounceTask: Task<Void, Never>?
    private static var lastApplied: ConfigSnapshot?
    private static var missingSince: ContinuousClock.Instant?
    private static var reportedFailures: Set<String> = []

    /// Where a config is applied (`reloadConfig`), with the snapshot taken BEFORE its read: a change in
    /// between then reloads once more, instead of being marked applied when it never was.
    static func recordApplied(_ snapshot: ConfigSnapshot) { lastApplied = snapshot }

    /// The file and folders to watch, given which paths exist. The folders are every existing one from a
    /// candidate's folder up to `home`, or the nearest existing one for a candidate outside it. Every
    /// event re-plans, so a folder created later (`~/.config/aerospork`) is watched from then on.
    ///
    /// Only the user's candidates go in, never `configUrl`: after a broken config falls back, that
    /// points into the app bundle, which never changes, and the user's fix would never be seen.
    nonisolated static func watchPlan(
        candidates: [String],
        existing: (String) -> Bool,
        home: String = FileManager.default.homeDirectoryForCurrentUser.path,
    ) -> (file: String?, dirs: [String]) {
        var dirs: [String] = []
        for candidate in candidates {
            var dir = URL(filePath: candidate).deletingLastPathComponent().path
            while true {
                let exists = existing(dir)
                if exists, !dirs.contains(dir) { dirs.append(dir) }
                let underHome = dir == home || dir.hasPrefix(home + "/")
                if dir == home || dir == "/" || (exists && !underHome) { break }
                dir = URL(filePath: dir).deletingLastPathComponent().path
            }
        }
        let files = candidates.filter(existing)
        return (files.count == 1 ? files.first : nil, dirs)
    }

    static var plan: (file: String?, dirs: [String]) {
        watchPlan(candidates: customConfigCandidates().map(\.path), existing: { FileManager.default.fileExists(atPath: $0) })
    }

    static func start() {
        for source in sources { source.cancel() }
        sources = []
        let plan = plan
        if let file = plan.file { watch(file, [.write, .delete, .rename, .extend]) }
        for dir in plan.dirs { watch(dir, .write) }
    }

    static func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        for source in sources { source.cancel() }
        sources = []
    }

    private static func watch(_ path: String, _ mask: DispatchSource.FileSystemEvent) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            // Once per path: every event re-arms, and `AppLog` must stay rare.
            if reportedFailures.insert(path).inserted {
                AppLog.config.error("Hot-reload can't watch \(path, privacy: .public) (errno \(errno, privacy: .public))")
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        src.setEventHandler { MainActor.assumeIsolated { scheduleCheck() } }
        src.setCancelHandler { close(fd) }
        sources.append(src)
        src.resume()
    }

    private static func scheduleCheck() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150)) // coalesce editor write bursts
            guard !Task.isCancelled else { return }
            // Re-arm first: the file may have been replaced, and a change after this raises a new event.
            start()
            await check()
        }
    }

    /// Reloads when the config differs from the one last applied, and says whether it reloaded.
    ///
    /// A config that is gone waits `grace` first, from when it was first seen gone: an editor's
    /// rename-over never empties the path, but unlink-and-create and move-away-and-back do. Only one
    /// still gone falls back to the defaults, as the default config's header promises.
    @discardableResult
    static func check(grace: Duration = .seconds(1)) async -> Bool {
        var now = ConfigSnapshot.now()
        if now.isMissing, now != lastApplied {
            let since = missingSince ?? .now
            missingSince = since
            try? await Task.sleep(until: since + grace, clock: .continuous)
            guard !Task.isCancelled else { return false }
            now = ConfigSnapshot.now()
            if now.isMissing, now != lastApplied {
                let gone = lastApplied?.file.urlOrNil?.path ?? "The config"
                AppLog.config.notice("\(gone, privacy: .public) is gone, so the defaults apply")
            }
        }
        missingSince = nil
        guard now != lastApplied else { return false }
        if reloadConfig() {
            if !isUnitTest { runRefreshSession(.globalObserver("configFileChanged"), screenIsDefinitelyUnlocked: true) }
            // An open settings window holds a snapshot of what it loaded. Without this it would keep
            // editing against stale text and could write it back over the external change.
            NotificationCenter.default.post(name: .aerosporkConfigReloadedExternally, object: nil)
        }
        return true
    }
}
