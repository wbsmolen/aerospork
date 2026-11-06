@testable import AppBundle
import AppKit
import Common
import XCTest

/// Tiles narrower than an app allows. The app clamps the size and grows the window from its top-left,
/// so before this the window covered its neighbours and ran off the monitor -- onto the next one.
@MainActor
final class MinimumSizeTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        config.gaps = .zero
    }

    func testMinimumIsGivenAndTheOthersShrinkInProportion() {
        let thirds = distribute([1000 / 3, 1000 / 3, 1000 / 3], minimums: [0, 600, 0], total: 1000)
        assertEquals(thirds.map { ($0 * 1000).rounded() / 1000 }, [200, 600, 200]) // thirds don't divide exactly
        assertEquals(distribute([500, 250, 250], minimums: [0, 400, 0], total: 1000), [400, 400, 200])
        // A child pushed under its own minimum by the first pass is pinned too.
        assertEquals(distribute([400, 300, 300], minimums: [0, 600, 250], total: 1000), [150, 600, 250])
    }

    func testMinimumsThatDoNotFitKeepTheProportionalSplit() {
        assertEquals(distribute([500, 500], minimums: [700, 700], total: 1000), [500, 500])
    }

    func testLayoutPlansAroundALearnedMinimum() async throws {
        let workspace = focus.workspace
        let windows = (0 ..< 3).map { LayoutTestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer) }
        XCTAssertTrue(windows[1].noteRefusedSize(asked: CGSize(width: 640, height: 1080), got: CGSize(width: 1000, height: 1080)))

        try await workspace.layoutWorkspace()

        assertEquals(windows.map { $0.singleAppliedFrame() }, [
            CGRect(x: 0, y: 0, width: 460, height: 1080),
            CGRect(x: 460, y: 0, width: 1000, height: 1080),
            CGRect(x: 1460, y: 0, width: 460, height: 1080),
        ])
        assertEquals(windows[1].hWeight, 640) // the user's proportions survive
    }

    func testWindowsTooWideForTheMonitorStayOnIt() async throws {
        let workspace = focus.workspace
        let windows = (0 ..< 2).map { LayoutTestWindow.new(id: UInt32($0), parent: workspace.rootTilingContainer) }
        for w in windows { _ = w.noteRefusedSize(asked: CGSize(width: 960, height: 1080), got: CGSize(width: 1200, height: 1080)) }

        try await workspace.layoutWorkspace()

        assertEquals(windows[0].singleAppliedFrame(), CGRect(x: 0, y: 0, width: 1200, height: 1080))
        assertEquals(windows[1].singleAppliedFrame(), CGRect(x: 720, y: 0, width: 1200, height: 1080)) // not x: 960, ending at 2160
    }

    func testRefusalsOnlyRaiseTheMinimum() {
        let workspace = focus.workspace
        let window = LayoutTestWindow.new(id: 0, parent: workspace.rootTilingContainer)
        let tall = CGSize(width: 500, height: 900)
        XCTAssertTrue(window.noteRefusedSize(asked: CGSize(width: 300, height: 900), got: tall))
        XCTAssertFalse(window.noteRefusedSize(asked: CGSize(width: 300, height: 900), got: tall)) // nothing new: no re-split
        XCTAssertFalse(window.noteRefusedSize(asked: CGSize(width: 200, height: 900), got: CGSize(width: 450, height: 900)))
        assertEquals(window.observedMinSize, CGSize(width: 500, height: 0))
    }

    func testADragBelowTheMinimumLowersIt() {
        let window = LayoutTestWindow.new(id: 0, parent: focus.workspace.rootTilingContainer)
        _ = window.noteRefusedSize(asked: CGSize(width: 300, height: 900), got: CGSize(width: 2000, height: 900))

        window.noteCurrentSize(CGSize(width: 800, height: 900))
        assertEquals(window.observedMinSize, CGSize(width: 800, height: 0))

        window.noteCurrentSize(CGSize(width: 1500, height: 900)) // larger says nothing
        assertEquals(window.observedMinSize, CGSize(width: 800, height: 0))
    }

    func testAWindowWithNoMinimumLearnsNothingFromItsSize() {
        let window = LayoutTestWindow.new(id: 0, parent: focus.workspace.rootTilingContainer)
        window.noteCurrentSize(CGSize(width: 800, height: 900))
        assertNil(window.observedMinSize)
    }

    func testTheCommandsThatResetALayoutForgetMinimums() async throws {
        let workspace = focus.workspace
        let window = LayoutTestWindow.new(id: 0, parent: workspace.rootTilingContainer)
        let refused = (asked: CGSize(width: 300, height: 900), got: CGSize(width: 2000, height: 900))

        _ = window.noteRefusedSize(asked: refused.asked, got: refused.got)
        _ = try await BalanceSizesCommand(args: BalanceSizesCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)
        assertNil(window.observedMinSize)

        _ = window.noteRefusedSize(asked: refused.asked, got: refused.got)
        _ = try await FlattenWorkspaceTreeCommand(args: FlattenWorkspaceTreeCmdArgs(rawArgs: [])).run(.defaultEnv, .emptyStdin)
        assertNil(window.observedMinSize)
    }
}
