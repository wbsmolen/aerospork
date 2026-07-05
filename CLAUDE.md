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
./run-debug.sh                # Run aerospork.app debug build
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
- `Sources/Cli/_main.swift`: CLI client that connects to `/tmp/aerospork-<user>.sock`
- IPC uses native POSIX `AF_UNIX` sockets with length-prefixed framing (`Sources/Common/util/UnixSocket.swift`) — no third-party socket library
- Commands are parsed in `Sources/AppBundle/command/parseCommand.swift` and executed on server
- All commands implement the `Command` protocol

**Configuration System** (`Sources/AppBundle/config/`)
- `Config.swift`: Main config structure
- `parseConfig.swift`: the single canonical TOML parser (TOMLKit), mapping keys to `Config` via `WritableKeyPath`
- `ConfigurationWriter.swift`: comment-preserving writer used by the GUI (line-based, only rewrites UI-managed keys)
- `ConfigFileWatcher.swift`: hot-reload — watches the active config file and reloads on change
- Supports modes, hotkey bindings, workspace-to-monitor assignments, gaps, callbacks

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
│   ├── ui/                # UI components (menu bar, settings window)
│   └── util/              # Utilities, extensions, macOS API wrappers (incl. volume via CoreAudio)
├── Cli/                   # Command-line client
├── Common/                # Shared utilities between CLI and AppBundle (incl. Unix socket IPC)
└── PrivateApi/            # C wrapper for _AXUIElementGetWindow private API
```

### Key Design Patterns

**Tree Paradigm**: Windows and containers are organized in a tree structure similar to i3wm. Workspaces are roots, containers have orientation (h/v), windows are leaves.

**Virtual Workspaces**: AeroSpork doesn't use native macOS Spaces. It implements its own workspace emulation by hiding/showing windows, allowing instant switching without animations.

**Monitor Fingerprinting**: Monitors are identified by vendor ID, model, and serial number, enabling persistent workspace assignments in docking setups. DisplayLink (USB virtual) displays report nil vendor/model/serial, so they are identified by the stable per-display UUID from `CGDisplayCreateUUIDFromDisplayID` (see `MonitorFingerprint.displayUUID`). Workspace-to-monitor assignments support a `uuid` fingerprint match key to pin a workspace to a specific DisplayLink panel, e.g. `[workspace-to-monitor-force-assignment.1.fingerprint]` with `uuid = "..."`.

**Thread-Per-Application**: Accessibility API calls for each app run on separate threads to avoid blocking.

**Config Hot-Reload**: `ConfigFileWatcher` watches the active config file (via `DispatchSource`) and reloads on change, so external editor edits and GUI saves apply without a manual `reload-config`.

**MRU Tracking**: Tree nodes track most-recently-used order for focus navigation.

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
- `MacApp.setFrame` skips redundant AX writes when a window is already at its target frame — this avoids unnecessary framebuffer churn, which matters over DisplayLink/USB
- Screen-configuration changes (`GlobalObserver`) are debounced and rebalanced on monitor-set change, handling DisplayLink's multi-stage connect/flap

## Dependencies

Managed via Swift Package Manager (Package.swift). The only third-party dependency is:
- **TOMLKit**: TOML parsing

Everything else is native: Unix-socket IPC (POSIX), global hotkeys (Carbon), volume control (CoreAudio), ordered collections (plain Swift).

External tools (installed via scripts in `./script/install-dep.sh`):
- swiftformat: Code formatting
- swiftlint: Linting
- asciidoctor (Ruby): Man page generation
- swiftly: Swift version management (uses `.swift-version` file)

## Important Files to Know

- `Sources/AppBundle/GlobalObserver.swift`: Entry point for window events
- `Sources/AppBundle/tree/TreeNode.swift`: Core tree structure
- `Sources/AppBundle/layout/layoutRecursive.swift`: Layout algorithm
- `Sources/AppBundle/server.swift`: CLI/app communication
- `Sources/AppBundle/command/cmdManifest.swift`: Command registry
- `Sources/AppBundle/config/parseConfig.swift`: Configuration parser
- `Sources/AppBundle/runLoop.swift`: Main refresh session loop

## Testing

Run tests with `./run-tests.sh` which:
1. Builds debug version
2. Runs `swift test` for unit tests
3. Validates CLI help/version output
4. Runs formatting and linting checks
5. Checks for uncommitted generated files

> **Toolchain:** tests build against the macOS SDK, so on a beta macOS use the matching
> Xcode beta or `swift test` may hang silently. Run:
> `DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.2.app/Contents/Developer xcrun swift test`

The suite (~98 XCTest functions in `Sources/AppBundleTests/`) is fully headless — it
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
