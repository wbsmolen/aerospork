import AppKit
import Common

/// One element's notifications on its app's observer. Active as long as you keep this class in memory.
class AxSubscription {
    let obs: AXObserver
    let ax: AXUIElement
    let axThreadToken: AxAppThreadToken = axTaskLocalAppThreadToken ?? dieT("axTaskLocalAppThreadToken is not initialized")
    var notifKeys: Set<String> = []

    private init(obs: AXObserver, ax: AXUIElement) {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        self.obs = obs
        self.ax = ax
    }

    /// All of `keys`, or nil. Partly subscribed, `deinit` takes back what did succeed. A window's
    /// notifications carry its `windowId` as their refcon (`axRefcon`).
    static func subscribe(_ obs: AXObserver, _ ax: AXUIElement, _ keys: [String], windowId: UInt32? = nil) -> AxSubscription? {
        let subscription = AxSubscription(obs: obs, ax: ax)
        for key in keys {
            if AXObserverAddNotification(obs, ax, key as CFString, axRefcon(windowId: windowId)) != .success { return nil }
            subscription.notifKeys.insert(key)
        }
        return subscription
    }

    deinit {
        axThreadToken.checkEquals(axTaskLocalAppThreadToken)
        for notifKey in notifKeys {
            AXObserverRemoveNotification(obs, ax, notifKey as CFString)
        }
    }
}

/// A window's id as the refcon of its notifications, so a move or resize during a drag names its window
/// without an `_AXUIElementGetWindow` IPC per event. The id itself, never a pointer to an object: a
/// notification AX had already queued when the subscription went away then carries a number, not a freed
/// object, and a crash here takes the window manager down. Window ids are never 0, so nil still means none.
func axRefcon(windowId: UInt32?) -> UnsafeMutableRawPointer? {
    windowId.flatMap { UnsafeMutableRawPointer(bitPattern: UInt($0)) }
}

func axRefconWindowId(_ refcon: UnsafeMutableRawPointer?) -> UInt32? {
    refcon.map { UInt32(truncatingIfNeeded: UInt(bitPattern: $0)) }
}

/// The one callback of every app's one observer.
func axNotified(_ obs: AXObserver, ax: AXUIElement, notif: CFString, data: UnsafeMutableRawPointer?) {
    switch notif as String {
        case kAXMovedNotification:
            noteFrameNotification(data)
            movedObs(obs, ax: ax, notif: notif, data: data)
        case kAXResizedNotification:
            noteFrameNotification(data)
            resizedObs(obs, ax: ax, notif: notif, data: data)
        default: refreshObs(obs, ax: ax, notif: notif, data: data)
    }
}
