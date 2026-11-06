@testable import AppBundle
import AppKit
import Common
import XCTest

/// Only bindings of the active mode are registered, so being "in" a mode with none means no hotkey
/// answers, including the one that would get you out. Modes here have no bindings, so nothing is
/// registered with the system.
@MainActor
final class ModeCommandTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        activateMode(mainModeId)
    }

    override func tearDown() async throws { activateMode(mainModeId) }

    func testSwitchingToAMissingModeFailsAndStaysPut() async throws {
        let result = try await parseCommand("mode no-such-mode").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode, 1)
        assertEquals(result.stderr, ["The config has no mode 'no-such-mode'"])
        assertEquals(activeMode, mainModeId)
    }

    func testSwitchingToARealModeStillWorks() async throws {
        config.modes["resize"] = .zero
        let result = try await parseCommand("mode resize").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode, 0)
        assertEquals(activeMode, "resize")
    }

    /// `reloadConfig` re-activates whatever was active, and the new config may not have it.
    func testAReloadThatDropsTheActiveModeFallsBackToMain() {
        config.modes["resize"] = .zero
        activateMode("resize")
        config.modes["resize"] = nil
        activateMode(activeMode)
        assertEquals(activeMode, mainModeId)
    }

    /// `enable off` is a nil mode, and a reload must not switch the app back on.
    func testADisabledAppStaysDisabled() {
        activateMode(nil)
        activateMode(activeMode)
        assertNil(activeMode)
    }

    /// `zip` stops at the shorter list, so a binding equalled any longer binding it was a prefix of.
    func testBindingsWithDifferentCommandCountsAreNotEqual() {
        let left: [any Command] = [parseCommand("focus left").cmdOrDie]
        let both = left + [parseCommand("focus right").cmdOrDie]
        XCTAssertNotEqual(
            HotkeyBinding([.option], .h, left, descriptionWithKeyNotation: "alt-h"),
            HotkeyBinding([.option], .h, both, descriptionWithKeyNotation: "alt-h"),
        )
        XCTAssertEqual(
            HotkeyBinding([.option], .h, left, descriptionWithKeyNotation: "alt-h"),
            HotkeyBinding([.option], .h, left, descriptionWithKeyNotation: "alt-h"),
        )
    }
}
