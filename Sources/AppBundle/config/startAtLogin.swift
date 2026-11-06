import AppKit
import Common
import ServiceManagement

/// Runs on every config reload, and a settings save is a reload, so it only talks to the system when
/// the answer changes. `.requiresApproval` already counts as registered: registering again would ask
/// the user a second time.
@MainActor
func syncStartAtLogin() {
    let service = SMAppService.mainApp
    guard startAtLoginNeedsChange(wanted: config.startAtLogin, status: service.status) else { return }
    if config.startAtLogin {
        _ = try? service.register()
    } else {
        _ = try? service.unregister()
    }
}

func startAtLoginNeedsChange(wanted: Bool, status: SMAppService.Status) -> Bool {
    wanted != (status == .enabled || status == .requiresApproval)
}
