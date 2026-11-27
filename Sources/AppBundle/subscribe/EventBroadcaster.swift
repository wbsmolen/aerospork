import Common
import Foundation
import os

/// The version of the event JSON. Every event and the snapshot carry it, because the CLI and the app can be
/// different builds. Bump it only for a change that breaks a reader.
let subscribeProtocolVersion = 1

/// One `aerospork subscribe` connection, as the broadcaster sees it: the events it asked for, and a bounded queue
/// of frames that a thread of its own writes out, so a slow client never blocks the main actor.
final class Subscriber: Sendable {
    /// A client this far behind has stopped reading. It is dropped, not waited on.
    static let maxQueuedFrames = 256

    let events: Set<SubscribeEvent>
    private let send: @Sendable (ServerAnswer) -> Bool
    private let hangUp: @Sendable () -> Void
    private let queue = DispatchQueue(label: "\(aeroSporkAppId).subscriber")
    private let queued = OSAllocatedUnfairLock(initialState: 0)

    /// `send` writes one frame and blocks until it is written: false means the client is gone. `hangUp` ends the
    /// connection from any thread, and wakes a `send` blocked on it.
    init(events: Set<SubscribeEvent>, send: @escaping @Sendable (ServerAnswer) -> Bool, hangUp: @escaping @Sendable () -> Void) {
        self.events = events
        self.send = send
        self.hangUp = hangUp
    }

    /// false, with nothing queued, when the queue is full.
    fileprivate func enqueue(_ answer: ServerAnswer) -> Bool {
        let accepted = queued.withLock { count in
            guard count < Self.maxQueuedFrames else { return false }
            count += 1
            return true
        }
        guard accepted else { return false }
        queue.async { [self] in
            if !send(answer) { hangUp() }
            queued.withLock { $0 -= 1 }
        }
        return true
    }

    /// `answer` after whatever is queued, past the bound, then the hang-up.
    fileprivate func close(with answer: ServerAnswer) {
        queue.async { [self] in
            _ = send(answer)
            hangUp()
        }
    }

    fileprivate func drop() { hangUp() }

    /// Returns once every frame queued so far has been written or has failed.
    func drain() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }
}

/// Fans the events of `aerospork subscribe` out to its subscribers. Never starts or waits for a session: every
/// call is synchronous on the main actor, and the writes happen on each subscriber's own queue.
@MainActor
final class EventBroadcaster {
    static let shared = EventBroadcaster()
    /// Each subscriber holds a thread and a file descriptor for as long as it stays connected.
    static let maxSubscribers = 16

    private(set) var subscribers: [Subscriber] = []
    /// The sorted window ids of each workspace at the last diff. nil while no subscriber asks for
    /// `workspace-windows-changed`, because building it walks every window.
    private var lastMembership: [String: [UInt32]]? = nil
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys] // one line per event
        return encoder
    }()

    var tracksMembership: Bool { lastMembership != nil }

    /// Registers `subscriber` and queues the snapshot as its first frame, in one main-actor step, so no event
    /// falls between the two. false when `maxSubscribers` are connected already.
    func add(_ subscriber: Subscriber) -> Bool {
        guard subscribers.count < Self.maxSubscribers else { return false }
        subscribers.append(subscriber)
        if subscriber.events.contains(.workspaceWindowsChanged), lastMembership == nil { lastMembership = currentMembership() }
        _ = subscriber.enqueue(serverAnswer(ExitCode.success, stdout: encode(snapshot())))
        return true
    }

    func remove(_ subscriber: Subscriber) {
        subscribers.removeAll { $0 === subscriber }
        if !subscribers.contains(where: { $0.events.contains(.workspaceWindowsChanged) }) { lastMembership = nil }
    }

    /// Ends every stream, each with `answer` as its last frame.
    func removeAll(sending answer: ServerAnswer) {
        let all = subscribers
        subscribers = []
        lastMembership = nil
        for subscriber in all { subscriber.close(with: answer) }
    }

    /// Sends `event` to the subscribers that asked for it. `fields` is not evaluated when none did, so an emit
    /// with nobody listening costs one check.
    func emit(_ event: SubscribeEvent, _ fields: @autoclosure () -> [String: Json]) {
        guard !subscribers.isEmpty else { return }
        let listeners = subscribers.filter { $0.events.contains(event) }
        if listeners.isEmpty { return }
        var object = fields()
        object["event"] = .string(event.rawValue)
        object["version"] = .int(subscribeProtocolVersion)
        let answer = serverAnswer(ExitCode.success, stdout: encode(object))
        for subscriber in listeners where !subscriber.enqueue(answer) {
            AppLog.server.notice("subscribe: dropped a client that stopped reading")
            remove(subscriber)
            subscriber.drop()
        }
    }

    /// One `workspace-windows-changed` for each workspace whose windows differ from the last call. Called once
    /// per refresh and per session; returns at once while nobody asks for the event.
    func emitWorkspaceWindowsChanges() {
        guard let before = lastMembership else { return }
        let after = currentMembership()
        lastMembership = after
        for name in changedWorkspaces(from: before, to: after) {
            emit(.workspaceWindowsChanged, ["workspace": .string(name), "windows": windowsJson(Workspace.existing(byName: name))])
        }
    }

    private func currentMembership() -> [String: [UInt32]] {
        Workspace.all.reduce(into: [:]) { $0[$1.name] = $1.allLeafWindowsRecursive.map(\.windowId).sorted() }
    }

    private func encode(_ object: [String: Json]) -> String {
        (try? encoder.encode(object)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// The first frame of every stream: the state the events that follow change.
    private func snapshot() -> [String: Json] {
        let focus = focus
        return [
            "event": .string("snapshot"),
            "version": .int(subscribeProtocolVersion),
            "mode": activeMode.map(Json.string) ?? .null,
            "focused-workspace": .string(focus.workspace.name),
            "focused-window-id": focus.windowOrNil.map { .uint32($0.windowId) } ?? .null,
            "focused-monitor-id": monitorIdJson(focus.workspace.workspaceMonitor),
            "monitors": .array(monitors.map { monitor in
                .dict([
                    "monitor-id": monitorIdJson(monitor),
                    "monitor-name": .string(monitor.name),
                    "workspace": .string(monitor.activeWorkspace.name),
                ])
            }),
            "workspaces": .array(Workspace.all.map { workspace in
                .dict([
                    "workspace": .string(workspace.name),
                    "monitor-id": monitorIdJson(workspace.workspaceMonitor),
                    "windows": windowsJson(workspace),
                ])
            }),
        ]
    }
}

/// The workspaces whose windows differ between two memberships, sorted. A workspace missing from one side has
/// no windows there.
func changedWorkspaces(from before: [String: [UInt32]], to after: [String: [UInt32]]) -> [String] {
    Set(before.keys).union(after.keys).filter { before[$0] ?? [] != after[$0] ?? [] }.sorted()
}

/// 1-based, like `%{monitor-id}`.
@MainActor private func monitorIdJson(_ monitor: any Monitor) -> Json {
    monitor.monitorId.map { .int($0 + 1) } ?? .null
}

/// The windows of `workspace`, by id, in the shape every event uses. A workspace that is gone has none.
@MainActor private func windowsJson(_ workspace: Workspace?) -> Json {
    .array((workspace?.allLeafWindowsRecursive ?? []).sorted { $0.windowId < $1.windowId }.map { .dict(subscribeWindowJson($0)) })
}

@MainActor func subscribeWindowJson(_ window: Window) -> [String: Json] {
    [
        "window-id": .uint32(window.windowId),
        "app-name": window.app.name.map(Json.string) ?? .null,
        "app-bundle-id": window.app.bundleId.map(Json.string) ?? .null,
    ]
}
