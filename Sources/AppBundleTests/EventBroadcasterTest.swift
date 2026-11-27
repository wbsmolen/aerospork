@testable import AppBundle
import Common
import Foundation
import os
import XCTest

@MainActor
final class EventBroadcasterTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }
    override func tearDown() async throws {
        EventBroadcaster.shared.removeAll(sending: serverAnswer(ExitCode.failure))
    }

    /// A subscriber that keeps every frame it is sent, decoded.
    private final class Recorder: Sendable {
        private let frames = OSAllocatedUnfairLock(initialState: [String]())
        func record(_ answer: ServerAnswer) -> Bool {
            frames.withLock { $0.append(answer.stdout) }
            return true
        }
        var all: [[String: Any]] {
            frames.withLock { $0 }.map { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] ?? [:] }
        }
    }

    private func subscribe(_ events: Set<SubscribeEvent>) -> (Subscriber, Recorder) {
        let recorder = Recorder()
        let subscriber = Subscriber(events: events, send: { recorder.record($0) }, hangUp: {})
        check(EventBroadcaster.shared.add(subscriber))
        return (subscriber, recorder)
    }

    func testTheSnapshotComesFirstAndOnlyTheAskedForEventsFollow() async {
        let workspace = Workspace.get(byName: "snap")
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let (subscriber, recorder) = subscribe([.modeChanged])

        EventBroadcaster.shared.emit(.focusChanged, ["workspace": .string("x")])
        EventBroadcaster.shared.emit(.modeChanged, ["mode": .string("resize"), "prev-mode": .string("main")])
        await subscriber.drain()

        let frames = recorder.all
        assertEquals(frames.map { $0["event"] as? String }, ["snapshot", "mode-changed"])
        assertEquals(frames.map { $0["version"] as? Int }, [1, 1])
        assertEquals(frames[1]["mode"] as? String, "resize")
        let workspaces = frames[0]["workspaces"] as? [[String: Any]] ?? []
        let snap = workspaces.first { $0["workspace"] as? String == "snap" }
        assertEquals((snap?["windows"] as? [[String: Any]])?.map { $0["window-id"] as? Int }, [1])
        assertEquals(frames[0]["focused-workspace"] as? String, focus.workspace.name)
    }

    /// The counter-check of `PerfInvariantsTest.testSubscribeEventsCostNothingWithoutASubscriber`: the gate is
    /// on who listens, not a mute button.
    func testAPayloadIsBuiltOnlyForASubscriberThatAskedForIt() {
        _ = subscribe([.modeChanged])
        var evaluated = false
        EventBroadcaster.shared.emit(.focusChanged, { evaluated = true; return [:] }())
        assertFalse(evaluated)
        EventBroadcaster.shared.emit(.modeChanged, { evaluated = true; return [:] }())
        assertTrue(evaluated)
    }

    /// A client that stops reading must not grow the window manager's memory without bound, or be waited on.
    func testAFullQueueDropsTheClient() async {
        // Every send blocks until the hang-up, as a write to a client that stopped reading does.
        let gate = DispatchSemaphore(value: 0)
        let hungUp = OSAllocatedUnfairLock(initialState: false)
        let subscriber = Subscriber(
            events: [.modeChanged],
            send: { _ in gate.wait(); gate.signal(); return false },
            hangUp: { hungUp.withLock { $0 = true }; gate.signal() },
        )
        check(EventBroadcaster.shared.add(subscriber)) // the snapshot takes one place
        for _ in 1 ..< Subscriber.maxQueuedFrames {
            EventBroadcaster.shared.emit(.modeChanged, [:])
        }
        assertEquals(EventBroadcaster.shared.subscribers.count, 1)
        assertFalse(hungUp.withLock { $0 })

        EventBroadcaster.shared.emit(.modeChanged, [:])
        assertTrue(EventBroadcaster.shared.subscribers.isEmpty)
        assertTrue(hungUp.withLock { $0 })
        await subscriber.drain()
    }

    func testTheSeventeenthSubscriberIsRefused() {
        for _ in 0 ..< EventBroadcaster.maxSubscribers { _ = subscribe([.modeChanged]) }
        assertFalse(EventBroadcaster.shared.add(Subscriber(events: [.modeChanged], send: { _ in true }, hangUp: {})))
    }

    func testTheMembershipDiffNamesOnlyTheWorkspacesThatChanged() {
        assertEquals(changedWorkspaces(from: ["a": [1, 2], "b": [3]], to: ["a": [1, 2], "b": [3]]), [])
        assertEquals(changedWorkspaces(from: ["a": [1, 2], "b": [3]], to: ["a": [1], "b": [2, 3]]), ["a", "b"])
        // A workspace that appears empty or is collected empty changed nothing.
        assertEquals(changedWorkspaces(from: ["a": [1]], to: ["a": [1], "c": []]), [])
        assertEquals(changedWorkspaces(from: ["a": [1], "c": [4]], to: ["a": [1]]), ["c"])
    }

    func testAMoveBetweenWorkspacesIsOneEventForEachSide() async {
        let a = Workspace.get(byName: "a")
        let b = Workspace.get(byName: "b")
        let window = TestWindow.new(id: 7, parent: a.rootTilingContainer)
        TestWindow.new(id: 8, parent: b.rootTilingContainer)
        let (subscriber, recorder) = subscribe([.workspaceWindowsChanged])
        assertTrue(EventBroadcaster.shared.tracksMembership)

        EventBroadcaster.shared.emitWorkspaceWindowsChanges() // nothing moved since the snapshot
        window.bind(to: b.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        EventBroadcaster.shared.emitWorkspaceWindowsChanges()
        await subscriber.drain()

        let events = recorder.all.dropFirst()
        assertEquals(events.map { $0["workspace"] as? String }, ["a", "b"])
        assertEquals(events.map { ($0["windows"] as? [[String: Any]])?.map { $0["window-id"] as? Int } }, [[], [7, 8]])

        EventBroadcaster.shared.remove(subscriber)
        assertFalse(EventBroadcaster.shared.tracksMembership)
    }
}
