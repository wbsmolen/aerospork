# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

aerospork is an i3-like tiling window manager for macOS written in Swift. It uses macOS Accessibility APIs to manage windows in a tree-based layout paradigm. The project includes:
- A main application (aerosporkApp) that runs as a background service
- A CLI tool (`aerospork`) that communicates with the app via native Unix sockets
- TOML-based configuration system with hot-reload and a settings GUI
- DisplayLink-aware multi-monitor support

## Build Commands

### Debug Build
```bash
./build-debug.sh              # Build debug version to .debug/
./run-debug.sh                # Run the debug app (.debug/AeroSpork-Debug.app)
./run-cli.sh [args]           # Run aerospork CLI (forwards args to binary)
```

Debug builds use `~/.aerospork-debug.toml` instead of `~/.aerospork.toml` for configuration.

### Release Build
```bash
./build-release.sh            # Build release to .release/ using Xcode
./install-from-sources.sh     # Build and install as aerospork-dev brew cask (WIP)
```

### Testing & Code Quality
```bash
./run-tests.sh                # Run full test suite + lint checks
./run-swift-test.sh           # Run Swift tests only (swift test)
./format.sh                   # Format code with swiftformat + swiftlint
```

### Other Commands
```bash
./generate.sh                 # Regenerate generated files (*.xcodeproj, *Generated.swift)
./build-docs.sh               # Build site and man pages to .site/ and .man/
./build-shell-completion.sh   # Build shell completion to .shell-completion/
```

## Architecture

### Core Components

**Tree-Based Data Structure** (`Sources/AppBundle/tree/`)
- `TreeNode.swift`: Base class for all tree nodes (mutable double-linked structure)
- `Workspace.swift`: Top-level container representing a virtual workspace
- `TilingContainer.swift`: Container nodes with orientation (h/v) and layout (tiles/accordion)
- `MacWindow.swift`: Leaf nodes representing actual windows
- `MacApp.swift`: Application container nodes
- Tree uses parent-child relationships with MRU (most recently used) tracking

**Window Management Flow**
1. `GlobalObserver.swift` monitors NSWorkspace notifications (app launch/activate/hide/terminate)
2. Notifications trigger `runRefreshSession()` which synchronizes tree state with actual windows
3. Layout engine (`layout/layoutRecursive.swift`) calculates window positions/sizes
4. Refresh events are debounced (fixed 50ms) so bursts of accessibility notifications coalesce into a single layout pass

**Client-Server Architecture**
- `Sources/AppBundle/server.swift`: Unix socket server running in main app
- `Sources/Cli/_main.swift`: CLI client that connects to `/tmp/<bundle-id>-<user>.sock` — note the
  bundle id differs per build, so debug and release each have their own socket
  (`/tmp/com.wbs.aerospork.debug-<user>.sock` vs `/tmp/com.wbs.aerospork-<user>.sock`)
- IPC uses native POSIX `AF_UNIX` sockets with length-prefixed framing (`Sources/Common/util/UnixSocket.swift`), no third-party socket library
- Commands are parsed in `Sources/AppBundle/command/parseCommand.swift` and executed on server
- All commands implement the `Command` protocol

**Configuration System** (`Sources/AppBundle/config/`)
- `Config.swift`: Main config structure
- `parseConfig.swift`: the single canonical TOML parser (TOMLKit), mapping keys to `Config` via `WritableKeyPath`
- `ConfigurationWriter.swift`: comment-preserving writer used by the GUI (line-based, only rewrites UI-managed keys)
- `ConfigFileWatcher.swift`: hot-reload — watches the active config file and reloads on change
- Supports modes, hotkey bindings, workspace-to-monitor assignments, gaps, callbacks

> **Writer invariant — do not break this.** A section the user did not edit must be left byte for
> byte alone, so *saving without editing changes nothing*. The view model is a lossy projection of
> the config (per-monitor gap arrays collapse to their default, monitor fingerprints to a single
> string, monitor fallback lists to `.first`), so unconditionally re-serializing a section destroys
> whatever the UI can't express. This shipped as a real bug: a `{ fingerprint = { display_name,
> width, height } }` assignment was silently rewritten as a bare name regex. `ConfigurationWriter`
> guards every section on a `…Edited` flag from `ConfigurationViewModel`, and
> `testWriterNoOpSaveIsByteIdentical` enforces it.

**Layout System** (`Sources/AppBundle/layout/`)
- Recursive, synchronous layout algorithm in `layoutRecursive.swift`
- `MacApp.setFrame` skips redundant AX position/size writes when a window is already at the target frame (avoids framebuffer churn, important over DisplayLink/USB)
- Supports gaps (inner/outer), accordion padding, container orientation

**Hotkeys** (`Sources/AppBundle/config/`)
- Global hotkeys are registered with native Carbon `RegisterEventHotKey` (`HotkeyBinding.swift`)
- `Key.swift`: local keycode enum (Carbon `kVK_*` virtual keycodes); `keysMap.swift` maps key notation to `Key`
- Only the active mode's bindings are registered at a time

### Module Structure

```
Sources/
├── aerosporkApp/                 # Main app entry point
├── AppBundle/             # Core window management logic (library)
│   ├── tree/              # Tree data structure (Workspace, Window, TilingContainer)
│   ├── command/           # Command implementations (focus, move, resize, etc.)
│   ├── config/            # Configuration parsing, writing, hot-reload, hotkeys
│   ├── layout/            # Layout calculation engine
│   ├── model/             # Monitors + fingerprinting (incl. DisplayLink UUID)
│   ├── mouse/             # Mouse move/resize handling
│   ├── ui/                # Menu bar + settings (SwiftUI `Settings` scene, 7 tabs incl. raw TOML)
│   │                      #   SettingsChrome.swift owns every shared control; see the invariant below
│   └── util/              # Utilities, extensions, macOS API wrappers (incl. volume via CoreAudio)
├── Cli/                   # Command-line client
├── Common/                # Shared utilities between CLI and AppBundle (incl. Unix socket IPC)
└── PrivateApi/            # C wrapper for _AXUIElementGetWindow private API
```

### Key Design Patterns

**Tree Paradigm**: Windows and containers are organized in a tree structure similar to i3wm. Workspaces are roots, containers have orientation (h/v), windows are leaves.

**Virtual Workspaces**: AeroSpork doesn't use native macOS Spaces. It implements its own workspace emulation by hiding/showing windows, allowing instant switching without animations.

**Monitor Fingerprinting**: `MonitorFingerprint.fromScreen` identifies a display by, in order of reliability: the stable per-display UUID (`CGDisplayCreateUUIDFromDisplayID`), EDID vendor/model/serial (`CGDisplayVendorNumber`/`CGDisplayModelNumber`/`CGDisplaySerialNumber` — CoreGraphics, *not* the Intel-era `IODisplayConnect` IOKit class, which does not exist on Apple Silicon), `localizedName`, and size. `matches(patternData:)` checks `uuid` first because it is the only key that separates two otherwise identical panels. DisplayLink (USB virtual) displays expose no EDID — CoreGraphics returns `kDisplayVendorIDUnknown`/`kDisplayProductIDGeneric`/`0`, which are normalized to `nil`, so `uuid` is the only thing that pins a workspace to a specific DisplayLink panel, e.g. `[workspace-to-monitor-force-assignment.1.fingerprint]` with `uuid = "..."`. Fingerprint `width`/`height` are in **points**, the same unit as `%{monitor-width}`/`%{monitor-height}`. Read the values to write into a fingerprint from `aerospork list-monitors --format '%{monitor-fingerprint}'`.

**Thread-Per-Application**: Accessibility API calls for each app run on separate threads to avoid blocking.

**Config Hot-Reload**: `ConfigFileWatcher` watches the active config file (via `DispatchSource`) and reloads on change, so external editor edits and GUI saves apply without a manual `reload-config`. Self-writes from the settings GUI are suppressed for 500ms (`suppressNextSelfWrite`) so a single save doesn't reload twice.

**Settings GUI**: a SwiftUI `Settings` scene (singleton: two windows can't race on the config file), seven tabs. Structured controls **apply live** on a 600ms debounce, per macOS convention; there is no Save button. That is only safe because of the writer invariant above. The Raw TOML tab is the exception. It applies explicitly, since half-typed TOML is invalid most of the time, and it is the guarantee that no config key is unreachable from the GUI.

> **Shared chrome invariant.** `SettingsChrome.swift` holds every shared settings control and is
> the only copy of each: `NumberField`, `SettingsHint`, `SettingsFooter`, `ListActionBar`,
> `ContentUnavailableViewCompat`, `SectionLabel`, `Badge`, `StatusLabel`, `Banner`, `CodeEditor`,
> `CopyButton`. A tab uses what is there rather than growing its own. Status symbols and tints come
> from `StatusLabel.Kind` / `Banner.Kind`, never string literals in a tab.
> `UIChromeConsistencyTest` enforces both rules. `dev-docs/architecture.md` explains why they exist.

**In-app updates**: `ui/Updater.swift` wraps `SPUStandardUpdaterController`. Two things about it
are easy to get wrong. Sparkle's `SUFeedURL`/`SUPublicEDKey` **cannot** be set through
`INFOPLIST_KEY_*` in `project.yml`; that prefix only supports keys Xcode recognises and drops
third-party ones silently, so they come from the `info.properties` plist instead and
`build-release.sh` asserts both are present in the finished bundle. And Sparkle embeds a framework
with its own XPC helpers in `Contents/Frameworks`, so the release script signs nested code
deepest-first before sealing the bundle, copies with `cp -R` to keep the framework's symlinks, and
checks that every nested Mach-O is independently signed rather than rejecting nested code outright.

**Workspace memory across a restart**: `WorkspaceMemory.swift` persists window -> workspace, plus
the monitor each workspace was on, to `/tmp/<bundle-id>-<user>.state.json`.

> **Both halves, or neither.** A first version restored only the workspace *name* and was reverted:
> `Workspace.get(byName:)` mints a workspace whose `assignedMonitorPoint` is nil, and the only
> writers of that field run when a workspace becomes visible or is force-assigned — so
> `workspaceMonitor` fell through to `mainMonitor` and every restored workspace collapsed onto the
> main display. Worse than binding by location, which at least kept the monitor.
> `restoredWorkspace(forWindowId:bundleId:)` is the single entry point that does both, and
> `WorkspaceMemoryTest` fails if registration calls the name-only lookup.

The key is the `CGWindowID` and nothing else. It comes from a monotonic counter owned by
**WindowServer**, so it is stable across a restart of *this* process and meaningless afterwards. The
generation token is therefore WindowServer's pid and start time, **not** `kern.boottime`: the counter
restarts on log out, `killall WindowServer` and graphics faults, none of which reboot the machine,
and the kernel also *adjusts* `boottime` whenever the calendar clock is stepped. A composite key
(bundle id + title + index + frame) cannot substitute — `AXIdentifier` names a window *class*
(`TerminalWindowRestoration`, `FinderWindow`), so identical windows are genuinely indistinguishable
and a fuzzy key would permute them silently.

**MRU Tracking**: Tree nodes track most-recently-used order for focus navigation.

## Design System

`.claude/skills/aerospork-design/` is an invocable Agent Skill holding the design system: tokens,
27 web components, three click-through UI kits (settings window, menu bar, CLI), 18 specimen cards,
and the brand artwork. It was derived *from* `Sources/AppBundle/ui/`, so it documents the shipping
UI rather than proposing a different one: the Swift is the source of truth, and the web components
are a recreation for mocks and marketing.

Load it (`/aerospork-design`) before designing a new surface. `readme.md` there carries the content
fundamentals — voice, sentence case, "explain the consequence not the control", "name the state then
the recovery", which are the most distinctive part of the product and the part worth matching first.

The app icon lives in both places and must stay in step: `resources/Assets.xcassets/AppIcon.appiconset/`
is what the release build compiles (`project.yml` → `ASSETCATALOG_COMPILER_APPICON_NAME`), and
`resources/AppIcon.icns` is what `build-debug-app.sh` copies for the debug bundle. Both are generated
from `.claude/skills/aerospork-design/assets/icon/render.html`; see the README beside it
for the rebuild steps.

## Development Notes

### Running from Xcode
1. Open `Package.swift` (not `aerospork.xcodeproj`) in Xcode
2. Edit Scheme → Options → Console → Choose `Terminal`
   - This prevents Accessibility permission requests on every rebuild (debug binaries are unsigned)

### Code Generation
- Some source files have `Generated` suffix - these are auto-generated by `./generate.sh`
- `aerospork.xcodeproj` is also generated
- Run `./generate.sh --all` to regenerate everything

### Configuration Files
- Debug: `~/.aerospork-debug.toml`
- Release: `~/.aerospork.toml`
- Default config: `docs/config-examples/default-config.toml` (bundled into the release app; used when no user config exists)
- Config documentation: `docs/guide.adoc`, `docs/commands.adoc`

### Testing Utilities
- "Accessibility Inspector.app" (built into macOS) for inspecting window properties
- DeskPad or BetterDisplay 2 for emulating multiple monitors; a real DisplayLink dock for DisplayLink-specific testing
- `script/clean-project.sh` to clean when things go wrong

### Performance & Smoothness
- Layout is synchronous and simple; a fixed 50ms debounce (`RefreshDebouncer`) coalesces bursts of accessibility events into a single refresh
- `MacApp.setFrame` skips redundant AX writes when a window is already at its target frame. This avoids unnecessary framebuffer churn, which matters over DisplayLink/USB
- Screen-configuration changes (`GlobalObserver`) are debounced and rebalanced on monitor-set change, handling DisplayLink's multi-stage connect/flap

### Logging

Two channels, and the distinction matters:

- **`AppLog`** (`AppLog.swift`) — always on, `os.Logger`, subsystem `aeroSporkAppId` so debug
  and release builds are distinguishable, categories `config`, `server` and `session`. Writes at
  `.notice` / `.error` / `.fault`, which the unified log **persists**, so `log show --last 1h
  --predicate 'subsystem == "com.wbs.aerospork"'` answers a bug report after the fact. Because it is
  unconditional it must stay **cheap and rare**: config loaded/rejected, config warnings, socket
  lifecycle, CLI commands that exited non-zero. Never per-refresh, never per-window.
- **`debugLog`** (`Common/util/commonUtil.swift`) — verbose tracing, `@autoclosure` so the message is
  never built when off, gated at runtime on `AEROSPORK_DEBUG_LOG` (**not** `#if DEBUG`: the gate has
  to be runtime, because a build that ships to users can still be compiled with `DEBUG`). Writes at
  `.debug`, which the unified log does **not** persist. Those records exist only for a `log stream`
  that is already running. Safe anywhere, including hot paths.

`PerfInvariantsTest.testDebugLogDoesNotEvaluateItsMessageWhenGateIsOff` pins the autoclosure;
`testHotPathsContainNoUnconditionalPrint` pins the absence of bare `print` in hot files;
`BrandingTest.testLoggersUseTheBuildsOwnBundleId` pins the subsystem. User-facing capture
instructions live in `docs/guide.adoc` → *Troubleshooting and bug reports*.

## Dependencies

Managed via Swift Package Manager (Package.swift). The only third-party dependency is:
- **TOMLKit**: TOML parsing

Everything else is native: Unix-socket IPC (POSIX), global hotkeys (Carbon), volume control (CoreAudio), ordered collections (plain Swift).

External tools installed by `./script/install-dep.sh`:
- swiftformat: Code formatting
- swiftlint: Linting
- xcodegen: Generates `aerospork.xcodeproj` from `project.yml`
- complgen: Shell-completion generation
- bundler: Pulls in asciidoctor (Ruby) for the man pages and docs site

Not installed by that script: **swiftly**, the Swift toolchain manager that honours
`.swift-version`. Install it yourself (`brew install swiftly`); `script/setup.sh` uses it only if
it is present.

## Important Files to Know

- `Sources/AppBundle/GlobalObserver.swift`: Entry point for window events
- `Sources/AppBundle/tree/TreeNode.swift`: Core tree structure
- `Sources/AppBundle/layout/layoutRecursive.swift`: Layout algorithm
- `Sources/AppBundle/server.swift`: CLI/app communication
- `Sources/AppBundle/command/cmdManifest.swift`: Command registry
- `Sources/AppBundle/config/parseConfig.swift`: Configuration parser
- `Sources/AppBundle/runLoop.swift`: Main refresh session loop
- `Sources/AppBundle/ui/SettingsChrome.swift`: Every shared settings control, and the only copy of each
- `Sources/AppBundle/WorkspaceMemory.swift`: Window→workspace placement across a restart
- `.claude/skills/aerospork-design/readme.md`: Design system — voice, visual foundations, components

## Testing

Run tests with `./run-tests.sh` which:
1. Builds debug version
2. Runs `swift test` for unit tests
3. Validates CLI help/version output
4. Runs formatting and linting checks
5. Checks for uncommitted generated files

> **Toolchain:** on a beta macOS, the swiftly-pinned toolchain (`.swift-version`) cannot compile
> this project: the frontend spins at 100% CPU indefinitely on the TOMLKit manifest, writing
> nothing. It is the toolchain, not the SDK: setting `DEVELOPER_DIR` alone does not help, because
> `script/setup.sh` routes `swift` through `swiftly run swift`. Use the Xcode beta toolchain:
>
> ```bash
> # tests
> DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test
>
> # any build script (setup.sh honours AEROSPORK_SWIFT=xcrun as an escape hatch)
> DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
>   AEROSPORK_SWIFT=xcrun ./build-debug-app.sh
> ```

The suite (`AppBundleTests` + `CommonTests`) is fully headless — it
uses a fake window tree (`TestApp`/`TestWindow`) and a mock Accessibility layer
(`AxUiElementMock` + captured `axDumps/` fixtures), so it needs no real windows or
Accessibility permission. It covers tree operations, command logic, config parse/round-trip,
window-kind heuristics, socket codec, and DisplayLink monitor-fingerprint (UUID) matching.

See **`dev-docs/testing-strategy.md`** for the full long-term plan: coverage gaps, the
seams to add for headless layout/multi-monitor testing, the live-app e2e harness,
CI strategy, and the DisplayLink testing story.

## Common Gotchas

- Always use MainActor for tree operations and window management
- The tree structure is mutable and requires careful synchronization
- Window IDs come from private `_AXUIElementGetWindow` API
- macOS Accessibility permissions required for the app to function
- Debug builds are unsigned and must run from Terminal to avoid permission dialogs
- Layout calculations should handle monitor arrangement edge cases (vertical stacking, different widths)
