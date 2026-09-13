# Architecture

## Definitions

**SPM.** Swift package manager and Swift build tool. In other words, `swift` CLI tool

## High level project infrastructure overview

- `../Sources`.
  The majority of AeroSpork source code. Managed by SPM `../Package.swift`
- `../Sources/AppBundle/`.
  The AeroSpork.app server. An SPM library, exposed to the `aerosporkApp` executable target.
- `../Sources/aerosporkApp/`.
  Thin app entry point (`@main`). SPM can't build a macOS App Bundle, so the release build is produced via the
  generated Xcode project. The Xcode project model lives in `../aerospork.xcodeproj/` and is generated from the
  `../project.yml` "skeleton" by `./generate.sh`. Keep as much code as possible in the `AppBundle` library.
- `../Sources/Cli/`.
  CLI client. Built purely with SPM; Xcode is not involved.
- `../Sources/Common/`.
  Shared code between server and client (command-line args parsing, util functions, and the native Unix-socket IPC).
- `../Sources/AppBundleTests/` and `../Sources/CommonTests/`.
  The two test targets. Both are headless.
- `../docs/`.
  Documentation sources for site and man pages in Asciidoc format https://asciidoc.org/

## client/server interaction

`aerospork` CLI binary is client. `AeroSpork.app` is server. Client and server talk to each other via predefined UNIX file.

Each time you run a CLI command:
1. Args are parsed by the client, args parsing errors are reported if any. Help is shown if `-h`/`--help` is passed.
1. If args are parsed successfully, the args are send to the server
1. Server parses the args once again, and runs the command
1. Server returns stdout, stderr, and exit code to the client
1. Client shows stdout, stderr, and ends the process with the requested exit code

## Commands subsystem

todo

../Sources/AppBundle/command/
../Sources/Common/cmdArgs/

Command checklist:
- [ ] Documentation in `../docs/aerospork-*` and `../docs/commands.adoc`
  - [ ] Check that site looks alright `./.site/commands.html`
  - [ ] Check that man page looks alright `./.man`
- [ ] Do `--window-id` and/or `--workspace` flags make sense for the command?
- [ ] Shell completion `../grammar/commands-bnf-grammar.txt`

## TOML Config parse subsystem

todo

../Sources/AppBundle/config/

## Tree Model subsystem

../Sources/AppBundle/tree/

A few invariants that are easy to break and expensive to rediscover:

- **Which workspaces exist.** `Config.persistentWorkspaces` (`workspaces`, `persistent-workspaces`,
  force-assignments) always exist; `Workspace.garbageCollectUnusedWorkspaces` creates and exempts them on
  every call, and releases every other empty invisible workspace. The binding-derived
  `preservedWorkspaceNames` only steers `getStubWorkspace` and is never materialized.
- **AeroSpork is not a managed app.** `MacApp.getOrRegister` returns nil for its own pid, so the Settings
  window is never bound to a workspace or hidden in a corner.
- **A registered window is never "new" again**, so its `on-window-detected` rules run inside
  `shieldedFromCancellation`: a refresh cancelled mid-rule would otherwise leave the rule half-applied
  permanently.
- **macOS's focus is read through `syncFocusFromMacOs`.** An unanswered read (`NativeFocusUnknown`) must
  not reach `updateFocusCache`, and a death macOS reacted to first is matched through
  `focusAdoptedAwayFrom`. Both are #39; `InvoluntaryFocusTest` pins them.

## Layout subsystem

todo

../Sources/AppBundle/layout/

## Workspace memory

`WorkspaceMemory.swift` persists window -> workspace, and the monitor each workspace was on, so a
restart does not scatter the layout. Written to `~/Library/Caches/<bundle-id>/workspace-memory.json`
at mode `0600`.

Three things about it are load-bearing:

- **Both halves, or neither.** `Workspace.get(byName:)` mints a workspace whose
  `assignedMonitorPoint` is nil, and the only writers of that field run when a workspace becomes
  visible or is force-assigned -- so a workspace restored by name alone reports `mainMonitor`, and a
  multi-monitor layout collapses onto one display. That shipped once and was reverted.
  `restoredWorkspace(forWindowId:bundleId:)` is the single entry point that does both.
- **The key is the `CGWindowID` and nothing else.** It comes from a counter owned by WindowServer, so
  it survives a restart of this process and nothing else. The generation token is WindowServer's pid
  and start time rather than `kern.boottime`, because the counter restarts on log out and on a
  graphics fault, neither of which reboots the machine.
- **Startup adds, never prunes.** At login AeroSpork races every other login item, so an app that has
  not answered Accessibility yet is absent from the first snapshot; writing that snapshot over the
  file deletes its entry, and the memory is only consulted while `isStartup`.

## UI subsystem

../Sources/AppBundle/ui/

Two surfaces, and neither is a window the app owns:

- **`MenuBarExtra`** (`MenuBar.swift`, `MenuBarLabel.swift`). The menu is a *remote control*, not a
  control panel: jump to a workspace, leave a binding mode, pause tiling, open Settings, quit.
  Anything that is configuration lives in Settings, which is why there is no "Reload config" or
  "Open config" row. The label is drawn chips, rasterized by `ImageRenderer` at 40pt and scaled
  down, never `N.square.fill` SF Symbols, which only exist for 0…50 and single capitals, so a
  workspace named `web` would have looked nothing like one named `3`. It follows the *menu bar's*
  appearance, which is not always the app's.
- **A SwiftUI `Settings` scene** (`ConfigurationWindow.swift` + `ConfigurationTabs/`), seven peer
  panes in the native macOS preference toolbar over one `ConfigurationViewModel`. The selection is
  restored with `AppStorage`. Structured panes auto-save on a 600ms debounce; Raw TOML applies
  explicitly. The view model is a lossy projection of the config, which is why the writer guards
  each section on an `…Edited` flag; see the writer invariant in `CLAUDE.md`.

The panes deliberately share navigation but not one generic layout. Forms use grouped native
controls; editable collections use inset tables and a shared action bar; Raw TOML wraps `NSTextView`
to retain native Find and undo while disabling prose substitutions. Its validation and highlighting
are cancellable/debounced, filesystem metadata is cached for the window lifetime, and the line
ruler's line-start index refreshes on the same 45ms debounce as highlighting before drawing only
visible labels; the Ln/Col readout counts newlines in place (column is a UTF-16 offset), so it stays
per-keystroke without a line-array rebuild.

**`SettingsChrome.swift` owns every shared control.** `NumberField`, `SettingsHint`,
`SettingsFooter`, `IconButton`, `PanelHeader`, `ListActionBar`, `ContentUnavailableViewCompat`,
`SectionLabel`, `Badge`, `StatusLabel`, `Banner`, `CodeEditor`, `CopyButton`. Nothing there holds state or touches the
config; it is presentation only.

That file exists because of a specific decay pattern. The panes were written at different times, and
each time one needed a small piece of chrome and didn't find it, it grew its own: three hand-rolled
+/- rows, caveat text in three different places, and two badges at two paddings (6/2 and 5/1) where
only one set a foreground colour or an accessibility label. `UIChromeConsistencyTest` scans `ui/`
for stray `Capsule()` badges and hardcoded status symbols, so a new one fails the test.

`StatusLabel.Kind` and `Banner.Kind` own the symbol/tint pairings. Red and green are the most
confusable pair on screen, so the symbol has to differ too, and that decision is made once rather
than per call site.

The web recreation of all of this — tokens, components, three click-through UI kits — lives in
`.claude/skills/aerospork-design/`. It is derived from this directory, so treat the Swift as the
source of truth and the web layer as documentation plus a prototyping surface.
