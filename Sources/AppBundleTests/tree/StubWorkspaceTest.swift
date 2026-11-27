@testable import AppBundle
import Common
import XCTest

/// Which workspace a monitor shows when nothing has been put on it.
///
/// The rule that matters: it must be a workspace the user can reach from the keyboard. The invent-a-
/// name fallback counts up from 1 and skips every bound name, so a config binding `1-9` produced
/// `10` -- a workspace with no keybinding, sitting on a monitor in front of the user.
///
/// Scope: these cover the *fresh pick*. `getStubWorkspace` first tries the monitor's previously
/// visible workspace, then any existing workspace whose windows already belong to this monitor --
/// deliberately including occupied ones, since showing a monitor its own windows back is the point.
/// Only when neither applies does the choice below happen.
@MainActor
final class StubWorkspaceTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// Focus moving inside the shown workspace re-shows it. That must not overwrite what the monitor
    /// showed before, which is what it goes back to when its workspace is taken away.
    func testReShowingTheVisibleWorkspaceKeepsThePreviousOne() {
        for name in ["A", "B"] { // windows keep both alive once hidden; "A" sorts first
            TestWindow.new(id: name == "A" ? 1 : 2, parent: Workspace.get(byName: name).rootTilingContainer)
            XCTAssertTrue(Workspace.get(byName: name).focusWorkspace())
        }
        XCTAssertTrue(Workspace.get(byName: "C").focusWorkspace())
        XCTAssertTrue(mainMonitor.setActiveWorkspace(Workspace.get(byName: "C")))
        assertEquals(getStubWorkspace(for: mainMonitor).name, "B")
    }

    func testAnIdleMonitorGetsTheLowestWorkspaceTheUserBound() {
        config.preservedWorkspaceNames = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
        assertEquals(getStubWorkspace(for: mainMonitor).name, "1")
    }

    /// Logical, not lexicographic: "2" must beat "10", and digits must beat letters.
    func testBoundNamesAreOrderedLogically() {
        config.preservedWorkspaceNames = ["A", "10", "2"]
        assertEquals(getStubWorkspace(for: mainMonitor).name, "2")
    }

    /// The reported symptom, stated directly: on the real config the two idle monitors read `10`
    /// and `11`, neither of which any binding could reach.
    func testTheChosenWorkspaceIsAlwaysOneTheUserCanReach() {
        let bound = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C"]
        config.preservedWorkspaceNames = bound
        let stub = getStubWorkspace(for: mainMonitor)
        XCTAssertTrue(bound.contains(stub.name), "idle monitor got '\(stub.name)', which has no keybinding")
    }

    /// With nothing bound there is no user intent to honour, so inventing a name is correct --
    /// and it must still be an empty one.
    func testWithNoBoundWorkspacesItStillInventsAnEmptyOne() {
        config.preservedWorkspaceNames = []
        let stub = getStubWorkspace(for: mainMonitor)
        XCTAssertFalse(stub.name.isEmpty)
        XCTAssertTrue(stub.isEffectivelyEmpty)
    }
}
