@testable import AppBundle
import Common
import XCTest

@MainActor
final class WorkspaceGcTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// Focus can name a workspace that is no longer registered: one collected while something still held
    /// it, then focused. Reading `focus` re-creates it. Inside the GC filter that write went into the
    /// dictionary the filter was replacing, so the focused workspace was created and dropped again.
    func testTheFocusedWorkspaceSurvivesWhenItsNameIsNotRegistered() {
        let stale = Workspace.get(byName: "focused")
        Workspace.garbageCollectUnusedWorkspaces() // empty, invisible, unfocused: collected
        XCTAssertNil(Workspace.existing(byName: "focused"), "precondition: the name is not registered")
        check(stale.focusWorkspace())
        _ = Workspace.get(byName: "other") // an empty one, so the filter has something to ask about

        Workspace.garbageCollectUnusedWorkspaces()

        assertEquals(Workspace.all.count(where: { $0.name == "focused" }), 1)
    }
}
