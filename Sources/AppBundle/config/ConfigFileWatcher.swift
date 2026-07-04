import Common
import Darwin
import Foundation

/// Watches the active config file and hot-reloads on change, so edits from an external
/// editor (or the settings GUI) apply without a manual `reload-config`.
///
/// Editors typically save atomically (write a temp file, then rename over the original),
/// which invalidates the original file descriptor — so on any event we debounce a reload
/// and then re-arm the watch on whatever file now lives at `configUrl`.
@MainActor
enum ConfigFileWatcher {
    private static var source: DispatchSourceFileSystemObject?
    private static var debounceTask: Task<Void, Never>?

    static func start() {
        source?.cancel()
        source = nil
        let path = configUrl.path
        guard FileManager.default.fileExists(atPath: path) else { return } // nothing to watch (e.g. bundled default)
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: DispatchQueue.main,
        )
        src.setEventHandler {
            Task { @MainActor in scheduleReload() }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    static func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
    }

    private static func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150)) // coalesce editor write bursts
            guard !Task.isCancelled else { return }
            if reloadConfig() {
                runRefreshSession(.globalObserver("configFileChanged"), screenIsDefinitelyUnlocked: true)
            }
            start() // re-arm on the (possibly replaced) file
        }
    }
}
