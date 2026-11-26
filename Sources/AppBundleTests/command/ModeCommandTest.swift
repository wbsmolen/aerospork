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

    /// A mode switch or a reload unregistered every key and registered it again, so a press queued
    /// across the gap was dropped and the combo reached the focused app meanwhile.
    func testHotkeyRegistrationPlanKeepsSharedBindings() {
        func binding(_ modifiers: NSEvent.ModifierFlags, _ key: Key, _ notation: String) -> HotkeyBinding {
            HotkeyBinding(modifiers, key, [parseCommand("focus left").cmdOrDie], descriptionWithKeyNotation: notation)
        }
        let altH = binding([.option], .h, "alt-h")
        let altJ = binding([.option], .j, "alt-j")
        let altK = binding([.option], .k, "alt-k")
        let target = [altH, altJ, altK].reduce(into: [String: HotkeyBinding]()) { $0[$1.descriptionWithKeyCode] = $1 }

        // alt-h is kept, alt-l goes, and alt-j and alt-k are new.
        var plan = hotkeyRegistrationPlan(current: [1: altH.descriptionWithKeyCode, 2: "alt-l"], target: target)
        assertEquals(plan.unregister, [2])
        assertEquals(plan.register.map(\.descriptionWithKeyNotation), ["alt-j", "alt-k"])

        // alt-k failed to register last time (another app owns it), so it is not current and is tried again.
        plan = hotkeyRegistrationPlan(current: [1: altH.descriptionWithKeyCode, 3: altJ.descriptionWithKeyCode], target: target)
        assertEquals(plan.unregister, [])
        assertEquals(plan.register.map(\.descriptionWithKeyNotation), ["alt-k"])

        // `enable off` is the nil mode, which has no bindings: everything goes.
        plan = hotkeyRegistrationPlan(current: [1: altH.descriptionWithKeyCode, 3: altJ.descriptionWithKeyCode], target: [:])
        assertEquals(plan.unregister, [1, 3])
        assertEquals(plan.register.map(\.descriptionWithKeyNotation), [])
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
