# CLAUDE.md

AeroSpork is an i3-like tiling window manager for macOS in Swift: a background app that manages windows
through the Accessibility APIs, a CLI (`aerospork`) that talks to it over a Unix socket, and a TOML config
with hot reload and a Settings window. This file is an index for agents that write code here. The human docs are the
source: `CONTRIBUTING.md`, `dev-docs/development.md`, `dev-docs/architecture.md`, `dev-docs/testing.md`.

The full project rules, each with its reason and its pinning test, load from here:

@dev-docs/architecture.md

## Commands

```bash
AEROSPORK_SWIFT=xcrun ./run-tests.sh          # full suite + CLI checks + lint + generated-files check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test   # Swift tests only
./format.sh                                    # swiftformat rewrites, then swiftlint (run-tests.sh only lints)
./generate.sh [--all]                          # regenerate *Generated.swift and aerospork.xcodeproj
AEROSPORK_SWIFT=xcrun ./build-debug-app.sh     # .debug/AeroSpork-Debug.app (needed for Accessibility)
./launch-debug-app.sh                          # open that bundle
./run-debug.sh                                 # run the bare binary .debug/aerosporkApp
./run-cli.sh <args>                            # the debug CLI
./build-docs.sh                                # .site/ and .man/
./build-shell-completion.sh                    # regenerate shell-completion/
./build-release.sh --build-version X.Y.Z       # .release/, Release configuration
```

Toolchain: use Xcode's, through `AEROSPORK_SWIFT=xcrun`. The swiftly toolchain pinned by `.swift-version` can
spin at 100% CPU forever on a beta macOS. `dev-docs/development.md#toolchain` is the only full copy of the rule.

Debug builds use bundle ID `com.wbs.aerospork.debug`, config `~/.aerospork-debug.toml`, socket
`/tmp/com.wbs.aerospork.debug-<user>.sock`. Release: `com.wbs.aerospork`, `~/.aerospork.toml`.

## Before you touch X, read Y

All anchors are in `dev-docs/architecture.md`.

| Area | Read | Pinning test |
|---|---|---|
| `config/ConfigurationWriter.swift`, `ui/ConfigurationViewModel.swift` | `#the-writer-invariant` | `ConfigTest.testWriterNoOpSaveIsByteIdentical`, `ConfigSafetyWriterFuzzTest` |
| Any pane in `ui/ConfigurationTabs/`, `ui/SettingsChrome.swift` | `#shared-chrome`, `#fonts-in-drawing-code` | `UIChromeConsistencyTest`, `PerfInvariantsTest.testDrawingCodeDoesNotAskForFonts` |
| `WorkspaceMemory.swift`, `MacWindow.getOrRegister` | `#workspace-memory`, `#both-halves-or-neither` | `WorkspaceMemoryTest` |
| `TilingContainer.awayWindows`, minimize, hide, fullscreen | `#away-windows` | `AwayWindowTest` |
| Native tabs, `MacApp.swift` window lists, Finder | `#native-tabs` | `NativeTabsTest` |
| Focus, `getNativeFocusedWindow.swift`, `focus.swift` | `#taking-focus-from-macos` | `InvoluntaryFocusTest`, `FocusCacheTest` |
| `on-window-detected`, popups, retries | `#window-rules-run-to-the-end` | `WindowDetectionRetryTest` |
| Workspace creation and garbage collection | `#which-workspaces-exist` | `PersistentWorkspacesTest`, `PerfInvariantsTest` |
| `layout/refresh.swift`, `util/RefreshScheduler.swift` | `#refresh-and-layout` | `RefreshSchedulerTest`, `AxWriteTest` |
| `model/MonitorFingerprint.swift`, `[monitors]` | `#monitors-and-fingerprints` | `MonitorFingerprintTest`, `MonitorIdentityTest` |
| `initAppBundle.swift`, opening Settings | `#aerospork-never-manages-itself` | `OwnWindowsAndSingleInstanceTest`, `OpenSettingsTest` |
| A new or renamed command | `#add-a-command` | `CliSurfaceTest`, `ShellCompletionGrammarTest` |
| `server.swift`, `Common/util/UnixSocket.swift` | `#client-and-server` | `UnixSocketTest`, `ServerProtocolTest`, `CliConnectionTest` |
| `AppLog`, `debugLog`, `print` | `#logging` | `PerfInvariantsTest`, `BrandingTest.testLoggersUseTheBuildsOwnBundleId` |
| Strings that name AeroSpace | `#upstream-names-live-in-one-file` | `BrandingTest` |
| `ui/Updater.swift`, `project.yml`, `build-release.sh`, `updates-site/` | `#in-app-updates` | `ReleaseFeedTest` |
| `.claude/skills/aerospork-design/` | `#design-system`, `#rebuild-the-design-kit-bundle` | `DesignKitParityTest` |

## Invariants

Tripwires, inline in case the import above does not load:

- **Writer invariant.** A config section the user did not edit stays byte for byte the same, so a save with no
  edit changes nothing. The view model is lossy. Guard each section on `edited(section)`, and `refusal`
  reads every render back. A fingerprint assignment was once rewritten as a bare name regex.
  `testWriterNoOpSaveIsByteIdentical`, `ConfigSafetyWriterFuzzTest`.
- **Both halves, or neither.** Restore a window's workspace and that workspace's monitor together, only through
  `restoredWorkspace(forWindowId:bundleId:)`, never `Workspace.get(byName:)` alone, or every restored workspace
  lands on the main monitor. `WorkspaceMemoryTest.testWindowRegistrationDoesNotUseTheNameOnlyLookup`.

One line each, the rest:

- Shared Settings controls exist once, in `SettingsChrome.swift`. Status symbols come from `StatusLabel.Kind` /
  `Banner.Kind`. A section footer is a `SettingsHint`. `UIChromeConsistencyTest`.
- Declared workspaces (`Config.persistentWorkspaces`) always exist. `preservedWorkspaceNames` stays lazy.
  `setUpWorkspacesForTests` zeroes both. `PersistentWorkspacesTest`, `PerfInvariantsTest`.
- `MacApp.getOrRegister` returns nil for AeroSpork's own pid. A second copy of a build exits before it binds the
  socket. Open Settings with `openSettingsWindow()`, not `SettingsLink`. `OwnWindowsAndSingleInstanceTest`.
- Session entry points call `syncFocusFromMacOs`, never `updateFocusCache`. An unanswered read throws
  `NativeFocusUnknown` and leaves the cache alone (#39). `InvoluntaryFocusTest`.
- Window rules run inside `shieldedFromCancellation`. A retry nothing else would trigger goes through
  `scheduleFollowUpRefresh`. `WindowDetectionRetryTest`.
- Away windows leave through `leaveTilesForMacos`, come back through `takeAwaySlot`. Places are "what preceded
  it", never indexes. `AwayWindowTest`.
- A native tab group is one tile. `takePlace` moves it with the selection. Tabs send `AXMainWindowChanged`.
  `NativeTabsTest`.
- Workspace memory is keyed by `CGWindowID` alone, generation = WindowServer pid + start time. Every first
  registration asks. Startup saves never prune. The file lives in `~/Library/Caches`, never `/tmp`.
  `WorkspaceMemoryTest`.
- Refresh: fixed 50 ms debounce, at most one running and one waiting. An event never cancels a running refresh,
  a session does. Sessions go one at a time through `sessionGate` and none awaits another. `RefreshSchedulerTest`.
- `MacApp.setFrame` skips writes when the frame already matches. `AxWriteTest`.
- Monitor matching checks `uuid` first. DisplayLink has no EDID, so `uuid` is the only pin. Sizes are points.
  `MonitorFingerprintTest`.
- Only `config/upstreamMigration.swift` spells the upstream name. `BrandingTest`.
- `AppLog` is always on and must stay rare. `debugLog` is an `@autoclosure` gated at runtime on
  `AEROSPORK_DEBUG_LOG`, not `#if DEBUG`. No bare `print` in hot files. `PerfInvariantsTest`.
- Sparkle keys come from `project.yml`'s `info:` block, never `INFOPLIST_KEY_*`. Nested code is signed
  deepest-first. Copy frameworks with `cp -R`. `build-release.sh` checks. `ReleaseFeedTest`.
- The two default configs (`resources/`, `docs/config-examples/`) are identical. `DefaultConfigParityTest`.
- Every command has `docs/aerospork-<name>.adoc`. Run `./generate.sh` after you edit one. `CliSurfaceTest`.

## Gotchas

- Never create an `NSFont` in drawing code: keep fonts in a `static let`. A fresh system font could be a broken
  object on macOS 27 debug builds, and CoreText's exception kills the whole window manager.
- Tree operations and window management run on the `MainActor`.
- Finder's `AXWindows` is empty on macOS 27. Test against Finder itself, not only a throwaway `NSWindow` app.
- Never edit `updates-site/appcast.xml` by hand. It is signed and builds require a signed feed. A wrong signature
  fails silently for 20 days. Re-sign with `sign_update` (`script/publish-release.sh` does it).
- Debug and release builds have different bundle IDs and run side by side, both managing the same windows.
  Quit one before you launch the other.
- The bare SwiftPM binary is unsigned. `build-debug-app.sh` signs the bundle when it finds an identity, and
  falls back to ad hoc, which makes macOS ask for Accessibility again after each rebuild.
- `dev-docs/performance.md` and `docs/guide.adoc` stay at their paths: tests cite them.
- Do not run a debug copy or anything that grabs windows unasked: the owner works on this Mac.

## Design work

`.claude/skills/aerospork-design/` is an invocable skill (`/aerospork-design`) holding the design system:
tokens, web components, three click-through UI kits, specimen cards and the brand artwork. It was derived from
`Sources/AppBundle/ui/`, so it documents the shipping UI rather than proposing a different one: the Swift is
the source of truth. Load it before you design a new surface. Its `readme.md` carries the content fundamentals
(voice, sentence case, "explain the consequence, not the control", "name the state, then the recovery"),
which are the part worth matching first.

The app icon lives in `resources/Assets.xcassets/AppIcon.appiconset/` (release) and `resources/AppIcon.icns`
(debug bundle). Both come from `.claude/skills/aerospork-design/assets/icon/render.html`. The README beside it
has the rebuild steps.
