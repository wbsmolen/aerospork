@testable import AppBundle
import Common
import SwiftUI
import XCTest

/// Does the settings UI actually *render*?
///
/// Everything else about these tabs is tested through `ConfigurationViewModel` — which is the data,
/// not the view. A `body` that force-unwraps, or a `Table` column that traps on an empty set, would
/// pass every one of those tests and still show the user a blank window or crash the app.
///
/// External verification is not available: walking the live window with System Events returns zero
/// elements for *every* tab, including ones that certainly have controls, so it cannot distinguish
/// "renders nothing" from "does not expose itself". `ImageRenderer` forces `body` evaluation
/// in-process, which is the part that can actually fail.
@MainActor
final class UIRenderSmokeTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    /// A v2 config in the shape the migration produces: most bindings generated, a few explicit.
    private static let v2 = """
        mod = 'alt'
        workspaces = '1-9'
        accordion-padding = 30

        [gaps]
        inner.horizontal = 8
        inner.vertical = 8

        [keys]
        alt-enter = 'exec-and-forget open -na Ghostty'

        [keys.service]
        esc = [ 'reload-config', 'mode main' ]

        [monitors]
        1 = 'main'

        [[on-window-detected]]
        if.app-id = 'com.apple.finder'
        run = ['layout floating']
        """

    private func loadedViewModel() -> ConfigurationViewModel {
        let vm = ConfigurationViewModel()
        vm.load(fromText: Self.v2)
        vm.markLoaded()
        return vm
    }

    /// Forces `body` to evaluate by rasterizing the view, and asserts it did not trap.
    ///
    /// **What this does and does not prove.** It catches the realistic failure: a `body` that traps
    /// -- a force-unwrap, an out-of-range access in a `Table`, a precondition on an empty collection.
    /// It does NOT prove pixels appeared, and the obvious stronger assertion is not available here.
    ///
    /// Asserting the bitmap is non-uniform was tried and removed: `Form` + `.formStyle(.grouped)`
    /// rasterizes to a uniform blank image under `ImageRenderer` in a headless test bundle, because
    /// that style needs a real window host. Measured with controls through the identical code path
    /// -- `Text` 137 distinct byte values, `Color.red` 3, `VStack { Text }` 65, but
    /// `Form { Toggle }.formStyle(.grouped)` exactly 1. Every settings tab is a grouped `Form`, so
    /// the assertion would have failed on all of them for a reason that has nothing to do with them.
    ///
    /// Nor is external verification available: walking the live settings window with System Events
    /// returns zero elements for *every* tab, including ones that certainly have controls.
    private func render(_ view: some View, _ label: String) {
        let renderer = ImageRenderer(content: view.frame(width: 900, height: 640))
        XCTAssertNotNil(renderer.cgImage, "\(label): body did not produce an image")
    }

    func testEveryTabRenders() {
        let vm = loadedViewModel()
        // The 77 rows the Keys tab shows for this config are generated, not written in the file --
        // exactly the case that used to render an empty table.
        XCTAssertGreaterThan(vm.displayBindings(mode: mainModeId).count, 10, "precondition: bindings to draw")

        render(GeneralSettingsTab(viewModel: vm), "General")
        render(GapsSettingsTab(viewModel: vm), "Gaps")
        render(KeyBindingsTab(viewModel: vm), "Keys")
        render(WorkspacesMonitorsTab(viewModel: vm), "Monitors")
        render(CallbacksTab(viewModel: vm), "Events")
        render(WindowRulesTab(viewModel: vm), "Window Rules")
    }

    /// The General tab's Appearance footer and Dock toggle are driven by `AppVisibility`, so the
    /// "both off" state renders a different branch than the default one. Both have to draw.
    func testGeneralTabRendersEitherVisibilityState() {
        let vm = loadedViewModel()
        render(GeneralSettingsTab(viewModel: vm), "General (default visibility)")

        vm.settings.general.showMenuBarIcon = false
        vm.settings.general.showDockIcon = false
        XCTAssertTrue(vm.appVisibility.dockIconIsForced, "precondition: the forced-Dock branch")
        render(GeneralSettingsTab(viewModel: vm), "General (both icons off)")
    }

    /// The Raw TOML tab, previously the one view excluded from this test.
    ///
    /// It was excluded because its button label called `getTextEditorToOpenConfig()`, so rendering
    /// it exercised LaunchServices rather than the view. That query is now memoized -- it was also
    /// re-running on every body evaluation, which is a real cost in a live window -- so the tab
    /// renders like any other.
    func testRawTomlTabRenders() {
        render(RawTomlTab(viewModel: loadedViewModel()), "Raw TOML")
        render(RawTomlTab(viewModel: ConfigurationViewModel()), "Raw TOML (empty)")
    }

    /// The connected-monitor list is empty on a headless runner, so render the geometry primitive
    /// directly with an asymmetric arrangement. That exercises scaling, negative origins, unequal
    /// panel sizes, ordering labels, and the highlighted main-display branch.
    func testMonitorArrangementRendersAsymmetricGeometry() {
        let rows = [
            ConfigurationViewModel.MonitorRow(
                name: "Studio Display",
                resolution: "2560 × 1440",
                uuid: "AAAAAAAA-0000-4000-8000-000000000001",
                position: 2,
                isMain: true,
                rect: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            ),
            ConfigurationViewModel.MonitorRow(
                name: "DisplayLink",
                resolution: "1920 × 1080",
                uuid: "BBBBBBBB-0000-4000-8000-000000000002",
                position: 1,
                rect: CGRect(x: -1920, y: 180, width: 1920, height: 1080),
            ),
        ]
        // Selected branch on purpose: it exercises the accent fill, the ring, and the main-bar
        // overlay, which the unselected render never builds.
        render(
            MonitorArrangementView(
                monitors: rows,
                selectedToken: rows[0].uuid ?? rows[0].name,
                onSelect: { _ in },
            ),
            "Monitor arrangement",
        )
    }

    /// The empty case is the one that traps: a `Table` or `List` built from an empty collection, and
    /// the "no bindings yet" placeholder path that only appears on a fresh config.
    func testTabsRenderWithAnEmptyViewModel() {
        let vm = ConfigurationViewModel()
        render(GeneralSettingsTab(viewModel: vm), "General (empty)")
        render(GapsSettingsTab(viewModel: vm), "Gaps (empty)")
        render(KeyBindingsTab(viewModel: vm), "Keys (empty)")
        render(WorkspacesMonitorsTab(viewModel: vm), "Monitors (empty)")
        render(CallbacksTab(viewModel: vm), "Events (empty)")
        render(WindowRulesTab(viewModel: vm), "Window Rules (empty)")
    }
}
