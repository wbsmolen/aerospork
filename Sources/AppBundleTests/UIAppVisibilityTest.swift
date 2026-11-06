@testable import AppBundle
import Common
import Foundation
import XCTest

/// `show-menu-bar-icon` / `show-dock-icon`: the two keys that decide whether the GUI is reachable
/// at all.
///
/// The runtime half — `NSApp.setActivationPolicy` and `MenuBarExtra(isInserted:)` — needs a running
/// app and is not asserted here. What *is* asserted is the part that can brick a user: the rule
/// that decides what those two booleans mean together, and the fact that both keys survive a round
/// trip through the parser and the config writer.
@MainActor
final class UIAppVisibilityTest: XCTestCase {
    // MARK: - The rule

    /// The whole point. Two hidden icons would leave `aerospork open-settings` as the only way back
    /// into the window that owns the toggles — so the combination is refused, in favour of the
    /// request the user actually made (a clean menu bar).
    func testHidingBothIconsKeepsTheDockIcon() {
        let both = AppVisibility(showMenuBarIcon: false, showDockIcon: false)
        assertFalse(both.showsMenuBarIcon)
        assertTrue(both.showsDockIcon)
        assertTrue(both.dockIconIsForced)
    }

    /// The counter-check: the rule must be "never zero icons", not "the Dock icon is always on".
    func testEitherIconAloneIsAllowed() {
        let menuBarOnly = AppVisibility(showMenuBarIcon: true, showDockIcon: false)
        assertTrue(menuBarOnly.showsMenuBarIcon)
        assertFalse(menuBarOnly.showsDockIcon)
        assertFalse(menuBarOnly.dockIconIsForced)

        let dockOnly = AppVisibility(showMenuBarIcon: false, showDockIcon: true)
        assertTrue(dockOnly.showsDockIcon)
        // Asked for, not forced -- the GUI leaves the toggle enabled in this case.
        assertFalse(dockOnly.dockIconIsForced)

        let both = AppVisibility(showMenuBarIcon: true, showDockIcon: true)
        assertTrue(both.showsMenuBarIcon)
        assertTrue(both.showsDockIcon)
    }

    // MARK: - Config

    /// The defaults have to reproduce what `INFOPLIST_KEY_LSUIElement: YES` used to hard code, or
    /// upgrading grows a Dock icon nobody asked for.
    func testDefaultsAreMenuBarOnly() {
        let config = Config()
        assertTrue(config.showMenuBarIcon)
        assertFalse(config.showDockIcon)
        let visibility = AppVisibility(showMenuBarIcon: config.showMenuBarIcon, showDockIcon: config.showDockIcon)
        assertTrue(visibility.showsMenuBarIcon)
        assertFalse(visibility.showsDockIcon)
    }

    func testBothKeysParse() {
        switch parseConfig("show-menu-bar-icon = false\nshow-dock-icon = true\n") {
            case .failure(let errors): XCTFail(errors.descriptions.joined(separator: "\n"))
            case .success(let config):
                assertFalse(config.showMenuBarIcon)
                assertTrue(config.showDockIcon)
        }
    }

    // MARK: - The GUI toggles reach the file

    /// A toggle that does not survive `ConfigurationWriter` is a toggle that reverts itself on the
    /// next reload, which is worse than not having it.
    func testTogglingWritesBothKeysAndTheyParseBack() {
        let base = "accordion-padding = 30\n"
        let vm = ConfigurationViewModel()
        vm.markLoaded()

        vm.settings.general.showMenuBarIcon = false
        vm.settings.general.showDockIcon = true
        let out = ConfigurationWriter.render(baseText: base, from: vm)

        switch parseConfig(out) {
            case .failure(let errors): XCTFail("\(errors.descriptions)\n\(out)")
            case .success(let config):
                assertFalse(config.showMenuBarIcon)
                assertTrue(config.showDockIcon)
        }
    }

    /// ...and an untouched pair must not append two lines to everyone's config file on the first
    /// unrelated edit. Same invariant `testWriterNoOpSaveIsByteIdentical` protects, one section on.
    func testUntouchedVisibilityKeysAreNotWritten() {
        let base = "accordion-padding = 30\n"
        let vm = ConfigurationViewModel()
        vm.markLoaded()
        vm.settings.general.accordionPadding = 42

        let out = ConfigurationWriter.render(baseText: base, from: vm)
        XCTAssertFalse(out.contains("show-menu-bar-icon"), out)
        XCTAssertFalse(out.contains("show-dock-icon"), out)
    }
}
