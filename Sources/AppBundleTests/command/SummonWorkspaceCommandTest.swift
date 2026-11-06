@testable import AppBundle
import Common
import XCTest

@MainActor
final class SummonWorkspaceCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseCommand("summon-workspace").errorOrNil, "ERROR: Argument '<workspace>' is mandatory")
    }

    private func threeMonitors() {
        testMonitors = (0 ..< 3).map { i in
            let rect = Rect(topLeftX: CGFloat(i) * 1000, topLeftY: 0, width: 1000, height: 1000)
            return MonitorImpl(monitorAppKitNsScreenScreensId: i + 1, name: "m\(i)", rect: rect, visibleRect: rect)
        }
    }

    /// Summoning from another monitor left that monitor empty, and the next `gcMonitors` then rearranged
    /// every monitor, shuffling workspaces that had nothing to do with it.
    func testSummoningFromAnotherMonitorTradesPlacesAndTouchesNothingElse() async throws {
        threeMonitors()
        defer { testMonitors = [defaultTestMonitor] }
        let (a, b, c) = (Workspace.get(byName: "a"), Workspace.get(byName: "b"), Workspace.get(byName: "c"))
        check(testMonitors[0].setActiveWorkspace(a))
        check(testMonitors[1].setActiveWorkspace(b))
        check(testMonitors[2].setActiveWorkspace(c))
        check(a.focusWorkspace())

        assertEquals(try await parseCommand("summon-workspace c").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode, 0)
        gcMonitors()

        assertEquals(testMonitors.map(\.activeWorkspace.name), ["c", "b", "a"])
        assertEquals(focus.workspace.name, "c")
    }

    /// The same two commands' other half: a hidden workspace was not on the monitor it is "leaving", so
    /// that monitor must keep what it shows. It was replaced by a stub, behind a fatal `check`.
    func testMovingAHiddenWorkspaceLeavesItsOldMonitorAlone() async throws {
        threeMonitors()
        defer { testMonitors = [defaultTestMonitor] }
        let (a, b) = (Workspace.get(byName: "a"), Workspace.get(byName: "b"))
        check(testMonitors[0].setActiveWorkspace(a))
        check(testMonitors[1].setActiveWorkspace(b))
        check(a.focusWorkspace())
        let hidden = Workspace.get(byName: "hidden")
        hidden.assignMonitor(testMonitors[0])
        _ = TestWindow.new(id: 5, parent: hidden.rootTilingContainer)

        let result = try await parseCommand("move-workspace-to-monitor --workspace hidden 2").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(result.exitCode, 0)
        assertEquals(testMonitors[0].activeWorkspace.name, "a")
        assertEquals(testMonitors[1].activeWorkspace.name, "hidden")
    }
}
