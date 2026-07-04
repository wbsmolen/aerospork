import AppKit
import Common

class GlobalObserver {
    private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == lockScreenAppBundleId {
            return
        }
        let notifName = notification.name.rawValue
        Task { @MainActor in
            if !TrayMenuModel.shared.isEnabled { return }
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue {
                runRefreshSession(.globalObserver(notifName), screenIsDefinitelyUnlocked: false, optimisticallyPreLayoutWorkspaces: true)
            } else {
                runRefreshSession(.globalObserver(notifName), screenIsDefinitelyUnlocked: false)
            }
        }
    }

    private static func onHideApp(_ notification: Notification) {
        let notifName = notification.name.rawValue
        Task { @MainActor in
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runSession(.globalObserver(notifName), token) {
                if config.automaticallyUnhideMacosHiddenApps {
                    if let w = prevFocus?.windowOrNil,
                       w.macAppUnsafe.nsApp.isHidden,
                       // "Hide others" (cmd-alt-h) -> don't force focus
                       // "Hide app" (cmd-h) -> force focus
                       MacApp.allAppsMap.values.count(where: { $0.nsApp.isHidden }) == 1
                    {
                        // Force focus
                        _ = w.focusWindow()
                        w.nativeFocus()
                    }
                    for app in MacApp.allAppsMap.values {
                        app.nsApp.unhide()
                    }
                }
            }
        }
    }

    @MainActor
    static func initObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onHideApp)
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif)

        // Monitor change detection
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                onMonitorConfigurationChanged()
            }
        }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            // todo reduce number of refreshSession in the callback
            //  resetManipulatedWithMouseIfPossible might call its own refreshSession
            //  The end of the callback calls refreshSession
            Task { @MainActor in
                guard let token: RunSessionGuard = .isServerEnabled else { return }
                resetClosedWindowsCache()
                try await resetManipulatedWithMouseIfPossible()
                let mouseLocation = mouseLocation
                let clickedMonitor = mouseLocation.monitorApproximation
                switch () {
                    // Detect clicks on desktop of different monitors
                    case _ where clickedMonitor.activeWorkspace != focus.workspace:
                        _ = try await runSession(.globalObserverLeftMouseUp, token) {
                            clickedMonitor.activeWorkspace.focusWorkspace()
                        }
                    // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                    //  And trigger new window detection that could be delayed due to mouseDown event
                    default:
                        runRefreshSession(.globalObserverLeftMouseUp, screenIsDefinitelyUnlocked: true)
                }
            }
        }
    }

    // DisplayLink docks fire didChangeScreenParametersNotification in bursts during a single
    // connect (multi-stage settle) and on flap. Coalesce bursts into one refresh+rebalance.
    @MainActor private static var pendingMonitorReconfigTask: Task<Void, Never>?
    // Set-based signal: rebalance when the monitor arrangement actually changes, not just the count.
    @MainActor private static var lastMonitorSignature: String?

    @MainActor
    private static func onMonitorConfigurationChanged() {
        pendingMonitorReconfigTask?.cancel()
        pendingMonitorReconfigTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            applyMonitorConfigurationChange()
        }
    }

    @MainActor
    private static func applyMonitorConfigurationChange() {
        guard let token: RunSessionGuard = .isServerEnabled else { return }

        let signature = monitorSetSignature()

        // Run a refresh session to update monitor state
        runRefreshSession(.globalObserver("didChangeScreenParameters"), screenIsDefinitelyUnlocked: true)

        // Rebalance only when the monitor set changed (count or arrangement) — e.g. reconnecting
        // identical DisplayLink panels in a different layout. Never rebalance when nothing changed.
        if config.autoMoveWorkspacesOnMonitorConnect && signature != lastMonitorSignature {
            Task { @MainActor in
                try await runSession(.globalObserver("autoMoveWorkspaces"), token) {
                    autoMoveWorkspacesToAssignedMonitors()
                }
            }
        }
        lastMonitorSignature = signature
    }

    @MainActor
    private static func monitorSetSignature() -> String {
        sortedMonitors
            .map { "\($0.name)|\($0.rect.topLeftX),\($0.rect.topLeftY),\($0.rect.width),\($0.rect.height)" }
            .joined(separator: ";")
    }
}
