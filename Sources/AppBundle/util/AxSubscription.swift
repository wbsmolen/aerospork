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

    /// All of `keys`, or nil. Partly subscribed, `deinit` takes back what did succeed.
    static func subscribe(_ obs: AXObserver, _ ax: AXUIElement, _ keys: [String]) -> AxSubscription? {
        let subscription = AxSubscription(obs: obs, ax: ax)
        for key in keys {
            if AXObserverAddNotification(obs, ax, key as CFString, nil) != .success { return nil }
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

/// The one callback of every app's one observer.
func axNotified(_ obs: AXObserver, ax: AXUIElement, notif: CFString, data: UnsafeMutableRawPointer?) {
    switch notif as String {
        case kAXMovedNotification: movedObs(obs, ax: ax, notif: notif, data: data)
        case kAXResizedNotification: resizedObs(obs, ax: ax, notif: notif, data: data)
        default: refreshObs(obs, ax: ax, notif: notif, data: data)
    }
}
