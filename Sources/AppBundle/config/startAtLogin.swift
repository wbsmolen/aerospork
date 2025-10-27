import AppKit
import Common
import ServiceManagement

@MainActor
func syncStartAtLogin() {
    cleanupPlistFromPrevVersions()
    let service = SMAppService.mainApp
    if config.startAtLogin {
        _ = try? service.register()
    } else {
        _ = try? service.unregister()
    }
}

private func cleanupPlistFromPrevVersions() { // todo Drop after a couple of versions
    let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appending(component: "Library/LaunchAgents/")
    Result { try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true) }.getOrDie()
    // Clean up old AeroSpork plist files
    let oldUrls: [URL] = [
        launchAgentsDir.appending(path: "com.bsmolen.aerospork.plist"),
        launchAgentsDir.appending(path: "com.wbs.aerospork.plist")
    ]
    oldUrls.forEach { try? FileManager.default.removeItem(at: $0) }
}
