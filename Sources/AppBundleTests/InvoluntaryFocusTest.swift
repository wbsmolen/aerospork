@testable import AppBundle
import AppKit
import Common
import Foundation
import XCTest

/// The paths that move focus, or move a window between workspaces, without the user asking.
///
/// Issue #39 -- "windows getting focus at random" -- was all of them compounding. A transient
/// Accessibility timeout made a live window look closed; collecting it handed focus to whatever the
/// workspace's MRU happened to be; and the MRU had itself been rewritten by bookkeeping rebinds that
/// nobody would call a focus change. None of it was reproducible on demand, and none of it logged
/// anything, so these tests pin the individual pieces instead.
@MainActor
final class InvoluntaryFocusTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        resetFocusCacheForTests()
    }

    // MARK: - Not collecting windows that are merely unresponsive

    /// The conservative default is the whole fix. `refreshAndGetAliveWindowIds` stops tracking every
    /// window this answers `true` for, and `refresh()` then unbinds it and moves focus -- so an
    /// element we cannot interrogate must never be assumed dead. Only a real `AXUIElement` has the
    /// `AXError` needed to say otherwise, and it says so only for failures that are not the timeout.
    func testAnElementWeCannotInterrogateIsNeverAssumedDead() {
        XCTAssertFalse(FakeAxElement().isDestroyed())
    }

    /// The decision the #39 fix turns on, table-driven from what `_AXUIElementGetWindow` returns on
    /// macOS 26 and 27.
    func testOnlyAnUnansweredReadKeepsAWindowWhoseIdCannotBeRead() {
        XCTAssertFalse(axErrorMeansDestroyed(.success))
        XCTAssertFalse(
            axErrorMeansDestroyed(.cannotComplete),
            "a busy app's window was treated as closed -- that is issue #39",
        )
        XCTAssertTrue(axErrorMeansDestroyed(.illegalArgument), "what a closed window actually reports was not treated as closed")
        XCTAssertTrue(axErrorMeansDestroyed(.invalidUIElement))
        XCTAssertTrue(axErrorMeansDestroyed(.failure), "an unexpected code should cost a re-registration, not a ghost window")
    }

    /// The regression guard for the call site, which needs a live `AXUIElement` and so cannot be
    /// exercised here. `containingWindowId()` collapses `.illegalArgument` (the window is gone) and
    /// `.cannotComplete` (the app missed the 1s `axMessagingTimeout`) into the same `nil`, and using
    /// it to decide liveness is what collected live windows out of busy apps.
    func testTheAliveWindowFilterDoesNotDecideLivenessFromContainingWindowId() throws {
        let body = try sourceBody("private func refreshAndGetAliveWindowIds", in: "Sources/AppBundle/tree/MacApp.swift", length: 2600)
        XCTAssertTrue(body.contains("isDestroyed()"), "the alive-window filter stopped using isDestroyed()")
        XCTAssertFalse(
            body.contains("containingWindowId() != nil"),
            "liveness is being decided from containingWindowId() again -- see issue #39",
        )
    }

    /// The CLI/hotkey minimize path bypasses the branch that records the workspace.
    ///
    /// `MacosNativeMinimizeCommand` binds straight into the global `macosMinimizedWindowsContainer`,
    /// so by the time `normalizeLayoutReason` sees the window its `nodeWorkspace` is already nil and
    /// the recorded name would be nil too -- leaving `macos-native-minimize` to teleport the window
    /// on restore while cmd-M and the Dock send it home. A source check, for the same reason as the
    /// one above: the command needs a real `MacApp` and cannot be driven headlessly.
    func testTheMinimizeCommandRecordsTheWorkspaceBeforeLeavingIt() throws {
        let source = try String(
            contentsOf: projectRoot.appending(path: "Sources/AppBundle/command/impl/MacosNativeMinimizeCommand.swift"),
            encoding: .utf8,
        )
        let record = try XCTUnwrap(
            source.range(of: "prevWorkspaceName: window.nodeWorkspace?.name"),
            "the minimize command stopped recording the workspace it is leaving",
        )
        let bind = try XCTUnwrap(source.range(of: "bind(to: macosMinimizedWindowsContainer"))
        XCTAssertTrue(
            record.upperBound < bind.lowerBound,
            "the workspace must be recorded BEFORE the bind -- afterwards `nodeWorkspace` is already nil",
        )
    }

    // MARK: - Focus only follows the window that actually had it

    /// Why `MacWindow.garbageCollect` cannot ask `focus.windowOrNil` whether the dying window had
    /// focus: by the time it runs, the window is out of the tree and the derived focus has *already*
    /// fallen back to the workspace's most recent window. `focusedWindowId` still names the window
    /// focus was assigned to, which is the question the guard needs answered.
    func testFocusedWindowIdStillNamesTheWindowAfterTheModelHasDriftedOffIt() {
        let workspace = Workspace.get(byName: "ws")
        let focused = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let other = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)

        XCTAssertTrue(focused.focusWindow())
        assertEquals(focusedWindowId, 1)
        assertEquals(focus.windowOrNil?.windowId, 1)

        focused.unbindFromParent() // what garbageCollect does before it asks

        assertEquals(focus.windowOrNil?.windowId, other.windowId, additionalMsg: "the derived focus should have moved on")
        assertEquals(focusedWindowId, 1, additionalMsg: "but the stored focus must still name the window that died")
    }

    /// The decision that issue #39 actually turned on. A background window dying must not move the
    /// user; the focused one dying must.
    func testOnlyTheDeathOfTheFocusedWindowMovesFocus() {
        let workspace = Workspace.get(byName: "ws")
        let elsewhere = Workspace.get(byName: "elsewhere")
        let focused = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let background = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 3, parent: elsewhere.rootTilingContainer)
        XCTAssertTrue(focused.focusWindow())

        XCTAssertFalse(
            shouldRestoreFocusAfterDeath(of: background.windowId, on: workspace),
            "a background window dying moved the user",
        )
        XCTAssertTrue(shouldRestoreFocusAfterDeath(of: focused.windowId, on: workspace))
        XCTAssertFalse(
            shouldRestoreFocusAfterDeath(of: focused.windowId, on: elsewhere),
            "a death on a workspace the user is not on moved the user",
        )
        XCTAssertFalse(shouldRestoreFocusAfterDeath(of: focused.windowId, on: nil))
    }

    /// cmd-W in an app with windows on several workspaces. macOS keys the app's next window, which is
    /// on another workspace, and `updateFocusCache` follows it BEFORE `refresh()` collects the window
    /// that closed -- so by the time the death is seen, `focusedWindowId` already names the new
    /// window. Asking only "was the dying window the focused one?" left the user on the other
    /// workspace with nothing to bring them back.
    func testTheFocusedWindowClosingAfterMacOsMovedUsOffItsWorkspaceStillRestores() {
        let (home, _, closing) = focusThenLetMacOsMoveUsAway()

        closing.unbindFromParent() // what garbageCollect does before it asks
        XCTAssertTrue(
            shouldRestoreFocusAfterDeath(of: closing.windowId, on: home),
            "the focused window closed and the user was left on the workspace macOS jumped to",
        )
    }

    /// The bound on the rule above: only the window macOS moved us off explains the move.
    func testMacOsMovingUsAwayDoesNotMakeABackgroundWindowsDeathMoveUsBack() {
        let (home, _, _) = focusThenLetMacOsMoveUsAway()
        let background = TestWindow.new(id: 4, parent: home.rootTilingContainer)

        background.unbindFromParent()
        XCTAssertFalse(shouldRestoreFocusAfterDeath(of: background.windowId, on: home))
    }

    /// ...and only for a second, like the clause it replaced. An app slower than that to report the
    /// death leaves the user where macOS put them.
    func testMacOsMovingUsAwayOnlyExplainsADeathForASecond() {
        let (home, _, closing) = focusThenLetMacOsMoveUsAway()
        focusAdoptedAwayFrom?.date = .distantPast

        closing.unbindFromParent()
        XCTAssertFalse(shouldRestoreFocusAfterDeath(of: closing.windowId, on: home), "the one-second bound never expired")
    }

    /// A window that dies late behind a workspace switch the USER made must not drag them back --
    /// which the old "the workspace focus just left, within a second" clause would have done the
    /// moment it became reachable: close a slow window, press a workspace hotkey, and the death lands
    /// after the switch. A hotkey switch goes through `setFocus`, not `updateFocusCache`, so it leaves
    /// no record for the death to match.
    func testAWindowDyingBehindAWorkspaceSwitchTheUserMadeDoesNotUndoIt() {
        let home = Workspace.get(byName: "home")
        let other = Workspace.get(byName: "other")
        let closing = TestWindow.new(id: 1, parent: home.rootTilingContainer)
        TestWindow.new(id: 2, parent: home.rootTilingContainer)
        TestWindow.new(id: 3, parent: other.rootTilingContainer)

        updateFocusCache(closing)
        XCTAssertTrue(other.focusWorkspace()) // alt-2
        _prevFocusedWorkspaceName = home.name // what `refreshModel` records for that switch
        defer { _prevFocusedWorkspaceName = nil }

        closing.unbindFromParent()
        XCTAssertFalse(
            shouldRestoreFocusAfterDeath(of: closing.windowId, on: home),
            "a window closing late undid the workspace switch the user asked for",
        )
    }

    /// The #201 guard skips the restore's force-focus when focus is on a window of the dying window's
    /// own app, which is only right while focus is still on the dead window's workspace. After macOS
    /// moved us to ANOTHER window of the same app -- the cmd-W case above, in Chrome -- skipping the push
    /// would leave the keyboard on a window parked off screen.
    /// A source check: `garbageCollect` needs a real `MacApp`.
    func testTheRestorePushesFocusWhenMacOsMovedUsToAnotherWorkspaceEvenInTheSameApp() throws {
        let body = try sourceBody("func garbageCollect(skipClosedWindowsCache", in: "Sources/AppBundle/tree/MacWindow.swift", length: 3200)
        XCTAssertTrue(
            body.contains("if focus.workspace != deadWindowWorkspace || focus.windowOrNil?.app.pid != app.pid"),
            "the #201 pid guard no longer lets the push through when focus is on another workspace",
        )
    }

    // MARK: - An unanswered focus read is not "no focused window"

    /// Chrome has a window on each workspace; the user switches; Chrome is too busy to answer the
    /// next focused-window read, then answers with the window it had before the switch.
    ///
    /// Treated as `nil`, the unanswered read recorded "macOS has no focused window" and expired the
    /// in-flight focus request, so the stale answer that followed counted as macOS changing its mind
    /// -- and the user bounced back across the switch.
    func testAnAppTooBusyToAnswerDoesNotBounceTheUserBackAcrossAWorkspaceSwitch() async throws {
        let here = Workspace.get(byName: "here")
        let there = Workspace.get(byName: "there")
        let staying = TestWindow.new(id: 1, parent: here.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: there.rootTilingContainer)
        appForTests = TestApp.shared
        defer { TestApp.shared.focusedWindowReadTimesOut = false }

        TestApp.shared.focusedWindow = staying
        try await syncFocusFromMacOs() // macOS and the model agree
        assertEquals(focus.workspace.name, here.name)

        XCTAssertTrue(there.focusWorkspace()) // the user switches
        // The request went out; the read below waits out the whole second, so the grace is spent.
        expectNativeFocus(target.windowId, deadline: Date().addingTimeInterval(-1))

        TestApp.shared.focusedWindowReadTimesOut = true
        try await syncFocusFromMacOs()

        TestApp.shared.focusedWindowReadTimesOut = false
        try await syncFocusFromMacOs() // the stale answer

        assertEquals(
            focus.workspace.name,
            there.name,
            additionalMsg: "an unanswered read let the app's stale answer undo the switch",
        )
    }

    // MARK: - Bookkeeping rebinds are not focus changes

    /// The other half of the MRU compensation. The fullscreen container hangs off the workspace, so
    /// binding into it promotes the window all the way up the MRU chain -- unlike the minimized
    /// container, which is global.
    func testAWindowGoingFullscreenDoesNotStealTheWorkspaceMru() async throws {
        let workspace = Workspace.get(byName: "ws")
        let stays = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let fullscreening = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        stays.markAsMostRecentChild()
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, stays.windowId)

        fullscreening.nativeState = (fullscreen: true, minimized: false)
        try await normalizeLayoutReason()

        assertEquals(
            workspace.mostRecentWindowRecursive?.windowId,
            stays.windowId,
            additionalMsg: "a window going fullscreen became the workspace's focus fallback",
        )
    }

    /// The third bookkeeping rebind, cmd-H with `automatically-unhide-macos-hidden-apps` off. Its
    /// container also hangs off the workspace, so without the compensation hiding an app made its
    /// window the workspace's focus fallback. Unreachable headlessly until `isMacosAppHidden` became
    /// a seam: the branch read `macAppUnsafe`, which traps on a `TestWindow`.
    func testHidingAnAppDoesNotStealTheWorkspaceMru() async throws {
        config.automaticallyUnhideMacosHiddenApps = false
        let workspace = Workspace.get(byName: "ws")
        let stays = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let hiding = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        stays.markAsMostRecentChild()

        hiding.appHidden = true
        try await normalizeLayoutReason()
        XCTAssertTrue(hiding.parent === workspace.macOsNativeHiddenAppsWindowsContainer, "the test needs the hidden-app branch taken")
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, stays.windowId, additionalMsg: "hiding an app stole the MRU")

        hiding.appHidden = false
        try await normalizeLayoutReason()
        assertEquals(hiding.nodeWorkspace?.name, workspace.name)
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, stays.windowId, additionalMsg: "unhiding an app stole the MRU")
    }

    /// Sending a window home must not strand it. Restoring to its own workspace instead of the
    /// focused one means it can land somewhere invisible, where `layoutWorkspaces` parks it in the
    /// corner -- while macOS still has the keyboard on it. Something has to reconcile that, and the
    /// only candidate is the next `updateFocusCache`. It could not, because the refresh that first
    /// saw the window focused recorded it as "last known" even though the adopt had failed (the
    /// window was still in the global minimized container, so it had no workspace to focus onto).
    /// That spent the one signal that would have retried.
    func testUnMinimizingOntoAnInvisibleWorkspaceStillConverges() async throws {
        let home = Workspace.get(byName: "home")
        let away = Workspace.get(byName: "away")
        let window = TestWindow.new(id: 1, parent: home.rootTilingContainer)
        TestWindow.new(id: 2, parent: away.rootTilingContainer) // keeps `home` and `away` alive

        window.nativeState = (fullscreen: false, minimized: true)
        try await normalizeLayoutReason()
        XCTAssertTrue(away.focusWorkspace())

        // macOS un-minimizes it and reports it focused, in the refresh BEFORE the model moves it out
        // of the global container. There is nothing to focus onto yet.
        updateFocusCache(window)
        assertEquals(focus.workspace.name, away.name)

        window.nativeState = (fullscreen: false, minimized: false)
        try await normalizeLayoutReason()
        assertEquals(window.nodeWorkspace?.name, home.name)

        // Now it has a workspace. This refresh must still be able to act on it.
        updateFocusCache(window)
        assertEquals(
            focus.workspace.name,
            home.name,
            additionalMsg: "macOS kept the keyboard on a window parked off-screen and nothing could reach it",
        )
    }

    /// Minimizing and restoring a background window must not make it the workspace's focus fallback.
    /// `TreeNode.bind` promotes whatever it binds to the front of the MRU, all the way to the root,
    /// and `Workspace.toLiveFocus()` reads exactly that -- so before the compensation, un-minimizing
    /// redefined which window the workspace considered focused, and `runSession` pushed that to macOS.
    func testRestoringAMinimizedWindowDoesNotStealTheWorkspaceMru() async throws {
        let workspace = Workspace.get(byName: "ws")
        let stays = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let minimized = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        stays.markAsMostRecentChild()
        assertEquals(workspace.mostRecentWindowRecursive?.windowId, stays.windowId)

        minimized.nativeState = (fullscreen: false, minimized: true)
        try await normalizeLayoutReason()
        assertEquals(minimized.nodeWorkspace?.name, nil, additionalMsg: "the window should be in the global minimized container")

        minimized.nativeState = (fullscreen: false, minimized: false)
        try await normalizeLayoutReason()

        assertEquals(minimized.nodeWorkspace?.name, workspace.name)
        assertEquals(
            workspace.mostRecentWindowRecursive?.windowId,
            stays.windowId,
            additionalMsg: "un-minimizing a window promoted it over the window the user was actually in",
        )
    }

    /// A window minimized on one workspace comes back to *that* workspace. The minimized container
    /// is global -- it hangs off `NilTreeNode`, not off a workspace -- so the restore used
    /// `focus.workspace` and teleported the window to wherever the user happened to be. That is also
    /// a window→workspace change, which is why these events showed up as `workspace-memory.json`
    /// writes in the issue report.
    func testAMinimizedWindowComesBackToItsOwnWorkspaceNotTheFocusedOne() async throws {
        let home = Workspace.get(byName: "home")
        let away = Workspace.get(byName: "away")
        let window = TestWindow.new(id: 1, parent: home.rootTilingContainer)
        TestWindow.new(id: 2, parent: away.rootTilingContainer) // keeps `away` from being collected

        window.nativeState = (fullscreen: false, minimized: true)
        try await normalizeLayoutReason()

        XCTAssertTrue(away.focusWorkspace())
        assertEquals(focus.workspace.name, away.name)

        window.nativeState = (fullscreen: false, minimized: false)
        try await normalizeLayoutReason()

        assertEquals(window.nodeWorkspace?.name, home.name, additionalMsg: "the window followed focus instead of going home")
    }

    /// `prevWorkspaceName` is stamped once, on the way into the unconventional container, and never
    /// rewritten. So trusting it unconditionally on the way out silently undid any move the user made
    /// while the window was fullscreen or its app hidden -- both of those containers hang off the
    /// workspace, so the window's own `nodeWorkspace` is live and is the authority there.
    func testMovingAFullscreenWindowToAnotherWorkspaceIsNotUndoneWhenItExitsFullscreen() async throws {
        let home = Workspace.get(byName: "home")
        let away = Workspace.get(byName: "away")
        let window = TestWindow.new(id: 1, parent: home.rootTilingContainer)
        TestWindow.new(id: 2, parent: away.rootTilingContainer)

        window.nativeState = (fullscreen: true, minimized: false)
        try await normalizeLayoutReason()
        assertEquals(window.nodeWorkspace?.name, home.name)

        // What `move-node-to-workspace` does to a tiled window.
        window.bind(to: away.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)

        window.nativeState = (fullscreen: false, minimized: false)
        try await normalizeLayoutReason()

        assertEquals(
            window.nodeWorkspace?.name,
            away.name,
            additionalMsg: "exiting fullscreen dragged the window back to where it was before the move",
        )
    }

    // MARK: - macOS is the tiebreaker when the model has drifted

    /// Once the model drifts away from macOS while macOS's answer stays put, nothing used to pull it
    /// back: the adopt was gated purely on "macOS is reporting something different than last time".
    /// `runSession` then pushed the drift out to macOS, so the two disagreed and neither corrected
    /// the other. Comparing against the model as well makes macOS win, which is the direction of
    /// truth `updateFocusCache` already documents.
    func testMacOsCorrectsAModelThatDriftedWhileItsOwnAnswerStayedPut() {
        let workspace = Workspace.get(byName: "ws")
        let native = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let drifted = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)

        updateFocusCache(native) // macOS says window 1, and we agree
        assertEquals(focusedWindowId, native.windowId)

        _ = drifted.focusWindow() // the model moves on its own -- a rebind, a normalization, anything
        assertEquals(focusedWindowId, drifted.windowId)

        updateFocusCache(native) // macOS says window 1 again, unchanged from its point of view

        assertEquals(focusedWindowId, native.windowId, additionalMsg: "the model was left disagreeing with macOS")
    }

    /// The bound on the rule above. Focus on an empty workspace is legitimately "no window", while
    /// macOS goes on reporting the last window it had -- so treating that disagreement as drift adopts
    /// that window and bounces the user straight back off the workspace they just switched to. The
    /// rule's same-workspace clause is what rejects it: the window macOS still names is, by
    /// definition, on another workspace.
    func testSwitchingToAnEmptyWorkspaceIsNotUndoneByMacOsStillNamingTheOldWindow() {
        let populated = Workspace.get(byName: "populated")
        let empty = Workspace.get(byName: "empty")
        let window = TestWindow.new(id: 1, parent: populated.rootTilingContainer)

        updateFocusCache(window)
        assertEquals(focus.workspace.name, populated.name)

        XCTAssertTrue(empty.focusWorkspace())
        assertEquals(focus.workspace.name, empty.name)
        assertEquals(focusedWindowId, nil)

        updateFocusCache(window) // macOS has not moved: it still reports the only window it knows

        assertEquals(focus.workspace.name, empty.name, additionalMsg: "the empty workspace switch was undone")
    }

    /// A workspace switch must survive the app being slow to accept focus.
    ///
    /// `MacApp.nativeFocus` issues its AX writes asynchronously and gives the app one second to
    /// agree. Past that, `pendingNativeFocus` expires and macOS is trusted again -- and macOS is
    /// still naming the window on the workspace we just LEFT. Treating that as model drift adopts
    /// it, which drags the user back and then forward again when the write finally lands: the
    /// switch reads as delayed or as a bounce. Exactly the apps this whole change is about
    /// (Chromium, Electron) are the ones slow enough to hit it.
    func testASlowAppAcceptingFocusLateDoesNotUndoAWorkspaceSwitch() {
        let here = Workspace.get(byName: "here")
        let there = Workspace.get(byName: "there")
        let staying = TestWindow.new(id: 1, parent: here.rootTilingContainer)
        let target = TestWindow.new(id: 2, parent: there.rootTilingContainer)

        updateFocusCache(staying) // macOS and the model agree
        assertEquals(focus.workspace.name, here.name)

        XCTAssertTrue(there.focusWorkspace()) // the user switches workspace
        assertEquals(focus.workspace.name, there.name)

        // The request went out, the app has not answered, and the grace has run out.
        expectNativeFocus(target.windowId, deadline: Date().addingTimeInterval(-1))
        updateFocusCache(staying) // macOS reports the old window -- unchanged, from its side

        assertEquals(
            focus.workspace.name,
            there.name,
            additionalMsg: "a slow app undid the workspace switch",
        )
    }

    /// `closedWindowsCache` reapplies every monitor's visible workspace when a cached window is
    /// re-detected, so a cache that outlives a workspace switch silently undoes it later. Commands
    /// and clicks reset it; a switch that came from macOS -- adopted inside a refresh, where none of
    /// those resets run -- did not.
    func testMacOsMovingFocusToAnotherWorkspaceDropsTheClosedWindowsCache() {
        let here = Workspace.get(byName: "here")
        let there = Workspace.get(byName: "there")
        let a = TestWindow.new(id: 1, parent: here.rootTilingContainer)
        let b = TestWindow.new(id: 2, parent: there.rootTilingContainer)

        updateFocusCache(a)
        cacheClosedWindowIfNeeded(window: a)
        XCTAssertFalse(isClosedWindowsCacheEmpty, "the test needs a populated cache")

        updateFocusCache(b)
        XCTAssertTrue(isClosedWindowsCacheEmpty, "a macOS-driven workspace switch kept a cache that can undo it")
    }

    /// Restoring to the remembered workspace must not resurrect one that has been collected.
    ///
    /// `Workspace.get(byName:)` mints on a miss, and a minted workspace has no
    /// `assignedMonitorPoint`, so it reports `mainMonitor` whatever display the original was on.
    /// Minimizing the last window on a workspace makes it empty, and empty invisible workspaces are
    /// collected -- so the naive restore parks the window on the main display. Falling back to the
    /// live focused workspace is no worse than the behaviour this replaced.
    func testAMinimizedWindowDoesNotResurrectACollectedWorkspace() async throws {
        let home = Workspace.get(byName: "home")
        let away = Workspace.get(byName: "away")
        let window = TestWindow.new(id: 1, parent: home.rootTilingContainer)
        TestWindow.new(id: 2, parent: away.rootTilingContainer)

        window.nativeState = (fullscreen: false, minimized: true)
        try await normalizeLayoutReason()

        XCTAssertTrue(away.focusWorkspace())
        Workspace.garbageCollectUnusedWorkspaces() // `home` is now empty and invisible
        assertEquals(Workspace.existing(byName: home.name), nil, additionalMsg: "the test needs `home` collected")

        window.nativeState = (fullscreen: false, minimized: false)
        try await normalizeLayoutReason()

        assertEquals(window.nodeWorkspace?.name, away.name, additionalMsg: "a collected workspace was resurrected")
    }

    /// `killall` must always be able to end the process.
    ///
    /// `interceptTermination` sets `SIG_IGN`, which removes the kernel's fallback -- so if its
    /// handler cannot run, SIGTERM does nothing at all. Putting the source on `.main` is the obvious
    /// and wrong choice: the cleanup needs the main actor, but a main queue blocked in a synchronous
    /// WindowServer round trip is exactly the state a user reaches for `killall` in. XCTest cannot
    /// send signals in-process, so this pins the structure instead.
    func testTerminationCannotBeBlockedByABusyMainQueue() throws {
        let source = try String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/util/appBundleUtil.swift"), encoding: .utf8)
        let start = try XCTUnwrap(
            source.range(of: "func interceptTermination"),
            "interceptTermination was renamed; re-point this test rather than deleting it",
        )
        let end = try XCTUnwrap(source.range(of: "source.resume()", range: start.upperBound ..< source.endIndex))
        let handler = withoutComments(source[start.lowerBound ..< end.upperBound])
        let queueDeclaration = withoutComments(source.split(separator: "\n").filter { $0.contains("let terminationQueue") }.joined(separator: "\n"))

        for mainQueue in [".main", "DispatchQueue.main"] {
            XCTAssertFalse(
                handler.contains("queue: \(mainQueue)") || queueDeclaration.contains("= \(mainQueue)"),
                "the signal source is on the main queue (\(mainQueue)) -- a wedged main queue would make SIGTERM a no-op",
            )
        }
        XCTAssertTrue(handler.contains("wait(timeout:"), "the handler must exit on a deadline, not only when the cleanup completes")
        XCTAssertTrue(
            handler.contains("_exit(_signal)"),
            "the deadline path must `_exit`: `exit` runs atexit handlers underneath a main thread still stuck in the cleanup",
        )
        XCTAssertTrue(
            handler.replacingOccurrences(of: "_exit(_signal)", with: "").contains("exit(_signal)"),
            "the path where the cleanup finished must still exit",
        )
    }

    // MARK: - Helpers

    /// Focus a window on `home`, then have macOS move focus to a window on `other` -- what `refresh`
    /// sees after cmd-W, before it collects the closed window.
    private func focusThenLetMacOsMoveUsAway() -> (home: Workspace, other: Workspace, closing: TestWindow) {
        let home = Workspace.get(byName: "home")
        let other = Workspace.get(byName: "other")
        let closing = TestWindow.new(id: 1, parent: home.rootTilingContainer)
        TestWindow.new(id: 2, parent: home.rootTilingContainer) // the successor
        let keyedByMacOs = TestWindow.new(id: 3, parent: other.rootTilingContainer)

        updateFocusCache(closing)
        assertEquals(focus.workspace.name, home.name)
        updateFocusCache(keyedByMacOs)
        assertEquals(focus.workspace.name, other.name, additionalMsg: "the test needs macOS to have moved us")
        return (home, other, closing)
    }
}
