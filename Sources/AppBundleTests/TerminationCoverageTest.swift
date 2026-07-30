@testable import AppBundle
import XCTest

/// Quitting has to put hidden workspaces' windows back on screen, whichever way it is asked to
/// stop. Hidden workspaces are emulated by parking windows off screen, so a quit that skips
/// `beforeTermination` leaves them there and the next launch files them under whatever workspace
/// covers those coordinates -- the layout appears to have been lost.
///
/// This was broken in every release build: the handlers were registered inside `if isDebug`, one of
/// the two was `SIGKILL` (which POSIX does not allow anyone to catch, so it never ran), and SIGTERM
/// was absent. Only the menu bar's Quit item cleaned up.
///
/// Source-scanning rather than behavioural: registering real handlers or terminating the app is not
/// something a unit test can do, but the two ways this regressed are both visible in the text.
final class TerminationCoverageTest: XCTestCase {
    private var initSource: String {
        (try? String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/initAppBundle.swift"), encoding: .utf8)) ?? ""
    }

    func testSigtermIsIntercepted() {
        XCTAssertTrue(
            initSource.contains("interceptTermination(SIGTERM)"),
            """
            SIGTERM is not intercepted. It is what killall, logout, restart and shut down send, so
            without it those quits skip beforeTermination() and windows come back on the wrong
            workspace.
            """,
        )
    }

    func testSigkillIsNotPretendedToBeCatchable() {
        XCTAssertFalse(
            initSource.contains("interceptTermination(SIGKILL)"),
            """
            SIGKILL cannot be caught -- POSIX forbids it, and signal() fails silently. Registering
            it does nothing except make the termination path look covered when it is not.
            """,
        )
    }

    func testTerminationHandlersAreNotDebugOnly() {
        // The registrations must not sit inside the `if isDebug` block. That block ends at the
        // first line that closes it, so anything after that closing brace applies to both builds.
        let lines = initSource.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let debugBlockStart = lines.firstIndex(where: { $0.contains("if isDebug {") }) else {
            return XCTFail("Could not find the `if isDebug` block in initAppBundle.swift")
        }
        guard let debugBlockEnd = lines[debugBlockStart...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "}" }) else {
            return XCTFail("Could not find the end of the `if isDebug` block")
        }
        let insideDebugBlock = lines[debugBlockStart ... debugBlockEnd].joined(separator: "\n")
        XCTAssertFalse(
            insideDebugBlock.contains("interceptTermination("),
            """
            Termination handlers are registered inside `if isDebug`, so a release build traps
            nothing. That is the configuration that shipped, and it meant every release quit except
            the menu bar item skipped the cleanup.
            """,
        )
    }

    /// AppKit-initiated quits never reach a POSIX signal handler at all.
    func testAppKitQuitsAreCovered() {
        let delegate = (try? String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/AppDelegate.swift"), encoding: .utf8)) ?? ""
        XCTAssertTrue(
            delegate.contains("applicationShouldTerminate"),
            """
            No applicationShouldTerminate. An AppleEvent quit, Force Quit, logout, restart and shut
            down are AppKit-initiated and send no signal, so they would skip the cleanup entirely.
            """,
        )
        XCTAssertTrue(
            delegate.contains("beforeTermination"),
            "The delegate must actually run the cleanup, not merely exist.",
        )
    }
}
