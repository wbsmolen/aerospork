# Architecture

This document describes how AeroSpork is built, and it is the one home of the project rules. Each
rule has three parts: the rule, the reason for it, and the test that fails when you break it. Read
the section for an area before you change code in that area.

`dev-docs/development.md` tells you how to build. `dev-docs/testing.md` tells you how the tests work.

## Tech stack

| Concern | Implementation |
|---|---|
| Language | Swift, 6.0 language mode (`Package.swift`); `.swift-version` pins toolchain 6.4 |
| Minimum OS | macOS 13.0 (Ventura) |
| UI | SwiftUI/AppKit: a `MenuBarExtra` and a native pane-toolbar `Settings` scene |
| Third-party dependencies | TOMLKit (config parsing) and Sparkle (in-app updates) |
| CLI/app IPC | POSIX `AF_UNIX` stream socket, length-prefixed framing (`Sources/Common/util/UnixSocket.swift`) |
| Global hotkeys | Carbon `RegisterEventHotKey` (`config/HotkeyBinding.swift`) |
| Volume control | CoreAudio (`util/SystemVolume.swift`) |
| Display identity | CoreGraphics `CGDisplayCreateUUIDFromDisplayID`, `CGDisplayVendorNumber`, `CGDisplayModelNumber`, `CGDisplaySerialNumber` |
| Window IDs | C shim over the private `_AXUIElementGetWindow` (`Sources/PrivateApi/`) |
| Build | SwiftPM for the CLI and debug builds; XcodeGen plus `xcodebuild` for the `.app`, since SwiftPM cannot produce a bundle |

The README section "Why these choices" gives the reasons for this stack.

## Modules

| Path | What it holds |
|---|---|
| `Sources/aerosporkApp/` | The thin entry point of the app (`@main`). |
| `Sources/AppBundle/` | Almost all app code, as a SwiftPM library. Keep new code here, not in the entry point. |
| `Sources/Cli/` | The `aerospork` command-line client. SwiftPM builds it. Xcode is not involved. |
| `Sources/Common/` | Code that the app and the CLI share: argument parsing, utilities, the Unix-socket IPC. |
| `Sources/PrivateApi/` | A C wrapper for the private `_AXUIElementGetWindow` function. |
| `Sources/AppBundleTests/`, `Sources/CommonTests/` | The two test targets. Both run with no windows and no Accessibility permission. |
| `docs/` | AsciiDoc sources of the site, the man pages and the CLI help text. |

SwiftPM cannot build a macOS app bundle, so the release build uses an Xcode project.
`generate.sh` writes `aerospork.xcodeproj` from `project.yml`. Do not edit the project by hand.

Inside `Sources/AppBundle/`:

| Folder | What it holds |
|---|---|
| `tree/` | The tree: `TreeNode`, `Workspace`, `TilingContainer`, `Window`, `MacWindow`, `MacApp`. |
| `command/` | The command implementations (`impl/`), the registry (`cmdManifest.swift`) and output formatting. |
| `config/` | The parser, the writer, hot reload, bindings and keys. |
| `layout/` | The refresh loop (`refresh.swift`) and the layout algorithm (`layoutRecursive.swift`). |
| `model/` | Monitors and their fingerprints. |
| `mouse/` | Mouse move and resize. |
| `ui/` | The menu bar and the Settings window. |
| `util/` | Wrappers for macOS APIs, including Accessibility, CoreAudio volume and the refresh scheduler. |

## Client and server

The `aerospork` CLI is the client, and the app is the server. They talk over an `AF_UNIX` socket at
`/tmp/<bundle-id>-<user>.sock`. Each build has its own bundle ID, so the debug build and the release
build have separate sockets (`com.wbs.aerospork.debug` and `com.wbs.aerospork`).

A CLI command goes through these steps:

1. The client parses the arguments. It prints help for `-h` and `--help`, and it reports a parse
   error and exits.
2. The client sends the arguments to the server as one frame: a 4-byte big-endian length, then JSON
   (`ClientRequest` in `Common/model/clientServer.swift`).
3. The server parses the arguments again and runs the command in a session.
4. The server sends back stdout, stderr and an exit code (`ServerAnswer`).
5. The client prints the output and exits with that code.

The framing is native POSIX code in `Common/util/UnixSocket.swift`. There is no third-party socket
library.

**Rule.** Both ends check with `getpeereid` that the other end runs as the same user, and hang up if
it does not. **Reason.** The socket is in `/tmp`, so the file system alone does not keep other users
out. **Test.** `UnixSocketTest`, `SocketCodecTest`, `CliConnectionTest`, `ServerProtocolTest`.

**Rule.** A disabled server answers only `enable`. The server refuses `exec-and-forget` from the CLI.
**Reason.** The refusal keeps a shell command from looking like a window-manager subcommand. It is not
a security boundary: a process that can reach the socket can already write the config. `SECURITY.md`
explains the trust model. **Test.** `ServerProtocolTest.testExecOverSocketGetsBadArgs` pins the
refusal.

## Commands

Every command implements the `Command` protocol (`command/Command.swift`): it has its parsed
arguments, and a `run` function that runs on the main actor and returns success or failure.

| Part | Where |
|---|---|
| The argument types and parsers | `Sources/Common/cmdArgs/`, registered in `cmdArgsManifest.swift` |
| The implementations | `Sources/AppBundle/command/impl/`, registered in `cmdManifest.swift` |
| The parser on the server | `command/parseCommand.swift` |
| `--format` variables and JSON output | `command/format.swift`, `command/formatToJson.swift` |
| The man page and the `--help` text | `docs/aerospork-<name>.adoc` |
| Shell completion | `grammar/commands-bnf-grammar.txt` |

### Add a command

1. Add the argument parser to `Sources/Common/cmdArgs/` and register it in `cmdArgsManifest.swift`.
2. Add the implementation to `Sources/AppBundle/command/impl/` and register it in `cmdManifest.swift`.
3. Decide whether `--window-id` and `--workspace` apply to the command.
4. Add `docs/aerospork-<name>.adoc` with a `:manpurpose:` line and a `tag::synopsis` region, and list
   the command in `docs/commands.adoc`. Keep the purpose line on one line, with no double quotes and
   no backslashes.
5. Run `./generate.sh`. It writes the `--help` text from the page. Commit the changed
   `*Generated.swift` files.
6. Add the command to `grammar/commands-bnf-grammar.txt`, run `./build-shell-completion.sh`, and
   commit `shell-completion/`.
7. Run `./build-docs.sh`, then examine `.site/commands.html` and the page in `.man/`.

**Test.** `CliSurfaceTest` fails when a command has no page or a page has no command.
`ShellCompletionGrammarTest` checks the grammar. `run-tests.sh` fails when the generated files are
out of date.

## Configuration

`config/parseConfig.swift` is the only TOML parser. It uses TOMLKit and maps each key to `Config`
through a `WritableKeyPath`. `parseConfigV2.swift` reads the v2 spelling (`mod`, `workspaces`, `keys`,
`monitors`, `on-window`). When a config has only the v1 spelling, `migrateConfigV2.swift` rewrites it
in the v2 spelling on first start.

`ConfigFileWatcher` watches the config file with a `DispatchSource` and reloads it when it changes.
It watches the file the user edits, not `configUrl`: when a broken config makes AeroSpork use the
bundled default, `configUrl` points into the app bundle, which never changes. After the Settings
window writes the file, `suppressNextSelfWrite` makes the watcher ignore events for 500 ms, so one
save causes one reload.

The default config exists twice: `resources/default-config.toml` (bundled in the app) and
`docs/config-examples/default-config.toml` (included in the guide). **Test.**
`DefaultConfigParityTest` fails when the two differ.

### The writer invariant

**Rule.** The Settings window must leave a section of the config that the user did not edit byte for
byte unchanged. A save with no edit changes nothing.

**Reason.** The view model is a lossy projection of the config. It collapses per-monitor gap arrays
to their default, a monitor fingerprint to one string, and a monitor fallback list to its first
entry. If the writer serializes a section again with no edit, it destroys what the panes cannot
show. This happened: a `{ fingerprint = { display_name, width, height } }` assignment became a bare
name regex.

`ConfigurationWriter.swift` is line based and works key by key. It rewrites only gaps and window
rules as whole sections, and it writes a new section in the v2 spelling. It protects each section in
three ways:

- It writes a section only when `edited(section)` in `ConfigurationViewModel` is true, that is, when
  `settings != loaded`. The view model has one struct for each section.
- `refusal` reads each render back before the writer writes it. An edited section must say what the
  panes say. Every other top-level key must say what it said before.
- When an edit touches a spelling that the writer cannot edit, the writer refuses that edit. It does
  not refuse the spelling until an edit touches it.

**Test.** `ConfigTest.testWriterNoOpSaveIsByteIdentical`, `ConfigSafetyWriterFuzzTest`,
`ConfigurationWriterSafetyTest`.

### Upstream names live in one file

**Rule.** `config/upstreamMigration.swift` holds every string that spells the name of the upstream
product: its config path, the `AEROSPACE_*` variables, its CLI and its keys.

**Reason.** AeroSpork reads an AeroSpace config and warns about AeroSpace names, so it must spell
them somewhere. One file keeps that out of the rest of the code. **Test.** `BrandingTest` exempts that
file and no other, and fails when the exemption is no longer necessary.

## Tree model

Workspaces are the roots of the tree. A `TilingContainer` has an orientation (`h` or `v`) and a
layout (`tiles` or `accordion`). A window is a leaf. Each node keeps its children in most recently
used order, which focus navigation reads. AeroSpork does not use macOS Spaces: it shows and hides
windows to emulate workspaces, so a workspace switch has no animation.

### Tree operations run on the main actor

**Rule.** Run every tree operation and every window-management call on the `MainActor`.
**Reason.** The tree is a mutable, doubly linked structure with no locks. Accessibility calls for each
app run on a thread of their own, so that a slow app cannot block the main thread. They hand their
results back to the main actor. **Test.** The Swift compiler checks the isolation.

### Which workspaces exist

**Rule.** A workspace that the config declares is in `Config.persistentWorkspaces` and always exists.
A config declares a workspace with `workspaces` (with or without `mod`), `persistent-workspaces`, or a
pin to a monitor. `garbageCollectUnusedWorkspaces` creates and exempts each one on every call, and
releases every other empty workspace that is not visible. Keep this set separate from
`preservedWorkspaceNames`, the names that bindings use, which `getStubWorkspace` reads. That set must
stay lazy.

**Reason.** A user who declares workspaces 1 to 9 expects to see all nine, even when they are empty. A
workspace that only a binding names must not exist before the user goes to it.

**Test.** `PersistentWorkspacesTest`, `PerfInvariantsTest.testPickingAStubDoesNotInstantiateEveryBoundName`.
`setUpWorkspacesForTests` empties both sets, because the bundled default declares 1 to 9.

### AeroSpork never manages itself

**Rule.** `MacApp.getOrRegister` returns nil for the pid of AeroSpork. `initAppBundle` exits when an
older copy with the same bundle ID runs (`runningCopyToYieldTo`), before it binds the CLI socket.
Open Settings through `openSettingsWindow()`, which activates the app and brings the window to the
front, not through `SettingsLink`.

**Reason.** If AeroSpork managed itself, the Settings window would be bound to a workspace or moved
off screen. Two copies of one build fought over every window, and the second took the socket. The
check uses the bundle ID, so the debug build and the release build still run side by side.

**Test.** `OwnWindowsAndSingleInstanceTest`, `OpenSettingsTest`.

### Taking focus from macOS

**Rule.** Both session entry points call `syncFocusFromMacOs`, never `updateFocusCache` directly. When
an app does not answer the read of its focused window, the read throws `NativeFocusUnknown` and the
focus cache stays as it is. `updateFocusCache` runs before `refresh()` collects dead windows, so
AeroSpork matches a window death that macOS reacted to first through `focusAdoptedAwayFrom`. Only a
cross-workspace adopt that macOS drove records that value. A switch from a binding goes through
`setFocus` and must never match it.

**Reason.** When the unanswered read passed nil on, AeroSpork spent `lastKnownNativeFocusedWindowId`
and workspace switches bounced back (#39).

**Test.** `InvoluntaryFocusTest`, `FocusCacheTest`.

### Window rules run to the end

**Rule.** A window in `MacWindow.allWindowsMap` is never new again, so `on-window-detected` rules (at
registration and in `validateStillPopups`) run inside `shieldedFromCancellation`. A retry that no
other event would cause goes through `scheduleFollowUpRefresh`, whose delay a later event does not
restart.

**Reason.** A refresh cancelled in the middle of a rule left the rule half applied, and the window
never got a second chance.

**Test.** `WindowDetectionRetryTest`.

### Away windows

**Rule.** A window that macOS takes out of the tiles (minimized, hidden with its app, or in native
fullscreen), or one that is not back yet after a restart, stays in `TilingContainer.awayWindows`. It
leaves through `leaveTilesForMacos` and comes back through `takeAwaySlot`, to its place and at its
share of the split, in any order. A place is "the window that came before it", not an index.

**Reason.** An index goes stale as windows open and close. A frozen tree includes the away windows, so
places outlive a restart. AeroSpork does not flatten a container that holds an away window. It still
removes an empty container, and gives the away windows of that container to the parent.

**Test.** `AwayWindowTest`.

### Native tabs

**Rule.** A native tab group takes one tile, however many tabs it has. `findBackgroundTabs` in
`MacApp.swift` records each background tab against the selected tab in `backgroundTabs`. The
background tabs wait in the container for hidden apps and keep no place of their own. `takePlace`
moves the tile to the tab that becomes selected. A new tab takes its tile at registration, not on the
next refresh.

**Reason.** macOS makes each tab a window with its own `CGWindowID`, but the user sees one window.
These Accessibility facts shape the code:

- Only the selected tab is on the window list of the app and has an `AXTabGroup` child. The other
  tabs stay alive off the list, and their frames go stale until they are selected.
- A tab selection sends `AXMainWindowChanged`, not `AXFocusedWindowChanged`.
- A minimized group is the only time that every tab is on the list.
- Some refreshes lay out first, so a tab that waited for the next refresh would squeeze the row for
  one frame.
- On macOS 27 the `AXWindows` attribute of Finder is empty, so `listedWindows` reads the children of
  Finder instead. Test against Finder itself, not only against a throwaway `NSWindow` app, which
  lists its windows normally.

**Test.** `NativeTabsTest`.

## Refresh and layout

`GlobalObserver.swift` watches the workspace notifications of macOS (an app launches, activates, hides
or quits). Each event asks `RefreshScheduler` for a refresh. The refresh brings the tree in step with
the real windows, and then `layoutRecursive.swift` computes the frame of each node.

**Rule.** `RefreshScheduler` waits 50 ms after the last event, so a burst of events causes one
refresh. At most one refresh runs and one waits, and their flags merge. An event never cancels a
running refresh. A session does. Sessions run one at a time through `sessionGate`, and no session may
wait for another.

**Reason.** An earlier version cancelled the running refresh on each event. Under a steady stream of
events, refreshes started and never finished, so no layout happened (`dev-docs/performance.md`,
item 8). A session that waited for another session would deadlock on `sessionGate`.

**Test.** `RefreshSchedulerTest`, including `testNoCommandStartsANestedSession`.

**Rule.** `MacApp.setFrame` skips the Accessibility writes when a window already has the target
frame. **Reason.** Each write costs a round trip to the app, and a redundant write redraws the frame
buffer, which is slow over DisplayLink and USB. **Test.** `AxWriteTest`.

A change of the monitor configuration has its own debounce in `GlobalObserver`, and AeroSpork
rebalances the workspaces when the set of monitors changes. That handles DisplayLink, which connects
in several stages and can flap.

## Monitors and fingerprints

`MonitorFingerprint.fromScreen` identifies a monitor by these keys, most reliable first:

1. The stable UUID of the display (`CGDisplayCreateUUIDFromDisplayID`).
2. The EDID vendor, model and serial (`CGDisplayVendorNumber`, `CGDisplayModelNumber`,
   `CGDisplaySerialNumber`). These are CoreGraphics calls. The Intel-era `IODisplayConnect` IOKit
   class does not exist on Apple Silicon.
3. `localizedName`.
4. The size, in points.

**Rule.** `matches(patternData:)` checks `uuid` first. **Reason.** The UUID is the only key that
separates two otherwise identical panels. A DisplayLink display has no EDID: CoreGraphics returns
`kDisplayVendorIDUnknown`, `kDisplayProductIDGeneric` and `0`, which AeroSpork normalizes to nil. So the
UUID is the only way to pin a workspace to one DisplayLink panel, for example `1 = { uuid = "..." }`
in `[monitors]`. The sub-table spelling `[monitors.1.fingerprint]` also parses, but the Settings
window refuses to edit that row.

Fingerprint `width` and `height` are in points, the unit of `%{monitor-width}` and
`%{monitor-height}`. To read the values for a fingerprint, run
`aerospork list-monitors --format '%{monitor-fingerprint}'`.

**Test.** `MonitorFingerprintTest`, `MonitorIdentityTest`.

## Workspace memory

`WorkspaceMemory.swift` keeps, across a restart of AeroSpork, the workspace of each window, the
monitor of each workspace, and the tiling tree of each workspace. It writes them to
`~/Library/Caches/<bundle-id>/workspace-memory.json` with mode `0600`.

**Rule.** Keep the file in `~/Library/Caches`, not in `/tmp`. **Reason.** The socket in `/tmp` is a
meeting point whose security comes from the permissions on the socket. This file is read at startup
and acted on, so a file planted in a directory that everyone can write would decide where the windows
of another user go. **Test.** `WorkspaceMemoryTest.testTheDefaultLocationIsNotWorldWritable`,
`testTheStateFileIsNotReadableByOtherUsers`.

**Rule.** The key is the `CGWindowID` and nothing else. The generation token is the pid and start
time of WindowServer, not `kern.boottime`. **Reason.** WindowServer owns a monotonic counter that
hands out the IDs, so an ID is stable across a restart of AeroSpork and has no meaning after
WindowServer restarts. The counter restarts on log out, on `killall WindowServer` and on a graphics
fault, and none of those reboots the machine. The kernel also adjusts `boottime` when the calendar
clock is stepped. A composite key (bundle ID, title, index and frame) cannot replace the ID:
`AXIdentifier` names a window class (`TerminalWindowRestoration`, `FinderWindow`), so identical
windows are truly the same to it, and a fuzzy key would swap them with no warning. **Test.**
`WorkspaceMemoryTest.testStateFromAnotherWindowServerSessionRestoresNothing`,
`testTheSessionTokenNamesTheRunningWindowServer`.

**Rule.** Every first registration of a window asks the memory, not only startup, and an entry is
spent once a registration uses it. **Reason.** An app that answers Accessibility late after a restart
still gets its windows back. IDs only grow within one WindowServer session, so nothing registered
later can match a spent entry. A live window that AeroSpork collected by mistake and detects again
does not go back to where it was at launch. **Test.**
`WorkspaceMemoryTest.testAnEntryIsSpentByTheRegistrationThatUsesIt`.

**Rule.** The save at startup adds entries and never removes them. **Reason.** At login AeroSpork
starts at the same time as the other login items, so an app that does not answer in time is absent
from the first snapshot. A save of that snapshot over the file would delete the entries of that app.
**Test.** `WorkspaceMemoryTest.testTheStartupSaveDoesNotPruneWindowsThatHaveNotAppearedYet`.

The rest of the restore works like this:

- `restoreVisibleWorkspaces` puts each monitor back on the workspace it showed. The focused monitor
  is the exception: it keeps the workspace that focus took from macOS.
- `restoreLayout` builds the whole tiling tree of a workspace again from the file each time a window
  arrives, so apps can answer in any order, and normalization can flatten a half-filled container in
  between. It stops when the user changes a layout (`stopRestoringLayouts`). It shares
  `restoreTilingTree` and the `Frozen*` types with the cache that the lock screen uses.
- `restoreState` puts back the state of a window that is not in the tree.
- A window rule does not run again on a remembered window, unless the rule says
  `if.during-aerospork-startup = true`.

### Both halves, or neither

**Rule.** Restore the workspace of a window and the monitor of that workspace together, through
`restoredWorkspace(forWindowId:bundleId:)`. Never restore the name alone.

**Reason.** A first version restored only the workspace name, and was reverted.
`Workspace.get(byName:)` makes a workspace whose `assignedMonitorPoint` is nil, and only code that
runs when a workspace becomes visible or is pinned writes that field. So `workspaceMonitor` used
`mainMonitor`, and every restored workspace moved to the main monitor. That was worse than a
placement by location, which at least kept the monitor.

**Test.** `WorkspaceMemoryTest.testWindowRegistrationDoesNotUseTheNameOnlyLookup` fails if
registration calls the name-only lookup. `testARestoredWorkspaceKeepsItsMonitor`.

## Settings window

The Settings window is a SwiftUI `Settings` scene (`ConfigurationWindow.swift` and
`ConfigurationTabs/`), so only one can exist and two windows cannot race on the config file. It has
seven peer panes in the native toolbar of macOS preferences, over one `ConfigurationViewModel`.
`AppStorage` remembers the selected pane.

The structured panes apply live, 600 ms after the last change, as macOS settings do. There is no Save
button. That is safe only because of [the writer invariant](#the-writer-invariant).

The Raw TOML pane applies only when you click Apply, because half-typed TOML is invalid most of the
time. Its editor wraps `NSTextView`, so it keeps native Find and undo, and it disables prose
substitutions. It has horizontal scrolling, line numbers, TOML highlighting, a section menu, the
cursor position and the exact diagnostics of the parser. The Raw TOML pane is the reason that no
config key is out of reach of the Settings window. Its validation and highlighting wait until the
user stops typing, and the line ruler draws only the visible lines. `dev-docs/performance.md`, items 9 to 16, has
the details.

The panes share navigation, but not one layout. Forms use grouped native controls. Collections use
inset tables and the shared action bar.

### Shared chrome

**Rule.** `SettingsChrome.swift` holds every shared control of the Settings window, and is the only
copy of each. A pane uses what is there and does not grow its own copy. Status symbols and tints come
from `StatusLabel.Kind` and `Banner.Kind`, never from string literals in a pane. A section footer is
a `SettingsHint`. An icon-only control gets its hit target from `settingsHitTarget()`, and a state
change that does not move focus is announced through `settingsAnnounce(_:)`. `CodeEditor` is not shared: only Raw TOML uses it, so it is in `RawTomlTab.swift`.

**Reason.** The panes were written at different times. Each time one needed a small control and did
not find it, it grew its own. The result was three hand-made +/- rows, caveat text in three places,
and two badges with two different paddings (6/2 and 5/1), of which only one had a foreground color or
an accessibility label. `StatusLabel.Kind` and `Banner.Kind` make the symbol and tint decision once:
red and green are the pair that people confuse most, so the symbol must differ too. A plain `Text` in
a section footer appears right-aligned at full brightness, and only in a real Settings window, so an
off-screen render does not show the fault.

**Test.** `UIChromeConsistencyTest` scans `ui/` for stray `Capsule()` badges, status symbols in string
literals, and footers that are not a `SettingsHint`.

### Fonts in drawing code

**Rule.** Never create an `NSFont` inside drawing code. Keep each font in a `static let`.

**Reason.** In a debug build on macOS 27, a new system font was now and then a broken object, and
CoreText raised an exception that Swift cannot catch. It stopped the whole window manager after a few
pane switches. A release build survived the same stress test, but the rule applies to both.

**Test.** `PerfInvariantsTest.testDrawingCodeDoesNotAskForFonts` checks the two places that draw text
by hand.

## Menu bar

The menu bar extra is `MenuBar.swift` and `MenuBarLabel.swift`. The menu is a remote control, not a
control panel: go to a workspace, leave a binding mode, pause tiling, open Settings, quit. Everything
that is configuration is in Settings, so the menu has no "Reload config" or "Open config" item.

The label shows a chip for the visible workspace on each monitor and marks the focused one.
`ImageRenderer` draws the chips at 40 pt and scales them down. The label does not use the
`N.square.fill` SF Symbols, which exist only for 0 to 50 and single capital letters, so a workspace
named `web` would look nothing like one named `3`. The label follows the appearance of the menu bar,
which is not always the appearance of the app.

**Rule.** Publish the tray values only when they change (`setIfChanged`). **Reason.** Each write
invalidates `MenuBarExtra`, and the label then draws a new image on the main thread, up to 20 times a
second. **Test.** `PerfInvariantsTest.testTrayDoesNotPublishWhenNothingChanged`.

## In-app updates

`ui/Updater.swift` wraps `SPUStandardUpdaterController` from Sparkle.

**Rule.** Set `SUFeedURL` and `SUPublicEDKey` in the `info:` `properties:` block of `project.yml`,
never through `INFOPLIST_KEY_*`. **Reason.** Xcode supports that prefix only for keys it knows, and
drops other keys with no error. A build without `SUFeedURL` never finds an update. **Test.**
`build-release.sh` checks that both keys are in the finished bundle.

**Rule.** Sign the nested code deepest first before you seal the bundle, copy the framework with
`cp -R`, and check that each nested Mach-O file has its own signature. **Reason.** Sparkle puts a
framework with its own XPC helpers in `Contents/Frameworks`. `cp -r` replaces the symlinks of the
framework with copies, and the bundle format becomes ambiguous. **Test.** `build-release.sh` checks
each nested signature.

**Rule.** Never edit `updates-site/appcast.xml` by hand. To change it, re-sign it with `sign_update`
and deploy it again. **Reason.** Builds set `SURequireSignedFeed`, so a build refuses a feed that is
not signed. A wrong signature does not fail loudly: clients report an error for 20 days and offer no
update. `publish-release.sh` checks the feed that the site serves. **Test.** `ReleaseFeedTest`.

## Logging

AeroSpork has two log channels.

**`AppLog`** (`AppLog.swift`) is always on. It is an `os.Logger` with the subsystem `aeroSporkAppId`,
so debug and release records are separate, and the categories `config`, `server` and `session`. It
writes at `.notice`, `.error` and `.fault`, which the unified log keeps, so
`log show --last 1h --predicate 'subsystem == "com.wbs.aerospork"'` can answer a bug report later.

**Rule.** Keep `AppLog` cheap and rare. Use it for the startup record, a config that loaded or was
rejected, config warnings, bindings that did not register, socket events, a second copy that exits,
CLI commands that exited with an error, and focus changes that AeroSpork made on its own (`session`).
Never use it for each refresh or each window. **Reason.** It is unconditional, and the unified log
keeps every record.

**`debugLog`** (`Common/util/commonUtil.swift`) is the verbose trace. It writes at `.debug`, which the
unified log does not keep, so the records exist only for a `log stream` that is already running. It
is safe anywhere, including hot paths.

**Rule.** `debugLog` takes its message as an `@autoclosure`, so it does not build the message when
the trace is off. The trace is on only when `AEROSPORK_DEBUG_LOG` is set at run time, not under
`#if DEBUG`. **Reason.** A build that ships to users can still be compiled with `DEBUG`, so a
compile-time gate is not enough. **Test.**
`PerfInvariantsTest.testDebugLogDoesNotEvaluateItsMessageWhenGateIsOff`.

**Rule.** No bare `print` in a hot file. **Reason.** An unconditional `print` in
`forceAssignedMonitor` wrote to stdout many times per refresh, and the CLI printed `[DEBUG]` lines on
every call. **Test.** `PerfInvariantsTest.testHotPathsContainNoUnconditionalPrint`.

**Rule.** Every logger uses the bundle ID of its own build. **Test.**
`BrandingTest.testLoggersUseTheBuildsOwnBundleId`.

`dev-docs/development.md`, "Read a debug build's logs", has the commands. User-facing instructions are
in `docs/guide.adoc`, "Troubleshooting and bug reports".

## Design system

`.claude/skills/aerospork-design/` is the design system: tokens, web components, three click-through
UI kits (Settings window, menu bar, CLI), specimen cards and the brand artwork. It comes from
`Sources/AppBundle/ui/`, so it documents the shipping UI and does not propose a different one. The
Swift is the source of truth, and the web components are a recreation for mocks and marketing.
Start with its `readme.md`, which holds the voice of the product.

**Rule.** A few user-visible strings must match between the Swift and the kit, and also appear in the
built bundle `_ds_bundle.js`. When the Swift changes one, change the kit too. Do not delete the entry
in the test. **Test.** `DesignKitParityTest`.

### Rebuild the design kit bundle

`_ds_bundle.js` is the compiled form of `components/**/*.jsx` and `ui_kits/**/*.jsx`, which mocks
load. The claude.ai design project that the kit syncs with (see `github.md`) builds it. No script in
this repository builds it.

The bundle has one block for each source file, under a `// <path>` comment. Each block is that file
compiled by Babel with the classic React transform: JSX becomes `React.createElement` calls, and
string literals stay as they are. Its exports go to `__ds_scope`.

To change a string or a small piece of logic:

1. Edit the `.jsx` source.
2. Make the same edit in the block for that file in `_ds_bundle.js`.
3. Run the Swift tests. `DesignKitParityTest` checks the strings in both places.

For a larger change, compile the edited file with Babel and the React preset in classic mode, and
replace the body of its block. Keep the `try` wrapper, the `__ds_scope` lines and the
`Object.assign(__ds_scope, ...)` line of the block as they are. Or sync the kit with its design
project, which builds the whole bundle again.

The app icon exists in two places, and both must stay the same:
`resources/Assets.xcassets/AppIcon.appiconset/` (the release build) and `resources/AppIcon.icns` (the
debug bundle). Both come from `.claude/skills/aerospork-design/assets/icon/render.html`. The README
next to it has the steps.
