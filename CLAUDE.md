# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AeroSpork is a fork of AeroSpace - an i3-like tiling window manager for macOS written in Swift. It uses macOS Accessibility APIs to manage windows in a tree-based layout paradigm. The project includes:
- A main application (AeroSporkApp) that runs as a background service
- A CLI tool (`aerospork`) that communicates with the app via Unix sockets
- TOML-based configuration system
- Performance monitoring and optimization features

## Build Commands

### Debug Build
```bash
./build-debug.sh              # Build debug version to .debug/
./run-debug.sh                # Run AeroSpace.app debug build
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
4. Performance optimizations include background layout calculation for complex workspaces (>10 windows)

**Client-Server Architecture**
- `Sources/AppBundle/server.swift`: Unix socket server running in main app
- `Sources/Cli/_main.swift`: CLI client that connects to `/tmp/aerospork-<user>.sock`
- Commands are parsed in `Sources/AppBundle/command/parseCommand.swift` and executed on server
- All commands implement the `Command` protocol

**Configuration System** (`Sources/AppBundle/config/`)
- `Config.swift`: Main config structure
- `parseConfig.swift`: TOML parser using TOMLKit
- Supports modes, hotkey bindings, workspace-to-monitor assignments, callbacks
- Performance tuning via `PerformanceConfig`
- New feature: Workspace profiles for different monitor setups

**Layout System** (`Sources/AppBundle/layout/`)
- Recursive layout algorithm in `layoutRecursive.swift`
- `LayoutCache.swift` and `LayoutMemoizer.swift` for performance optimization
- `BackgroundLayoutCalculator.swift` for async layout calculation (complex workspaces)
- Supports gaps (inner/outer), accordion padding, container orientation

**Performance Monitoring** (`Sources/AppBundle/monitoring/`)
- `PerformanceMonitor.swift`: Comprehensive metrics collection system
- `PerformanceMetrics.swift`: Metrics for refresh cycles, layout calculations, cache hits/misses
- Adaptive debouncing based on system load
- Background task tracking

### Module Structure

```
Sources/
├── AeroSporkApp/          # Main app entry point
├── AppBundle/             # Core window management logic (library)
│   ├── tree/              # Tree data structure (Workspace, Window, TilingContainer)
│   ├── command/           # Command implementations (focus, move, resize, etc.)
│   ├── config/            # Configuration parsing and structures
│   ├── layout/            # Layout calculation engine
│   ├── monitoring/        # Performance monitoring
│   ├── cache/             # Window property and layout caching
│   ├── ui/                # UI components (status bar, settings window)
│   └── util/              # Utilities, extensions, macOS API wrappers
├── Cli/                   # Command-line client
├── Common/                # Shared utilities between CLI and AppBundle
└── PrivateApi/            # C wrapper for _AXUIElementGetWindow private API
```

### Key Design Patterns

**Tree Paradigm**: Windows and containers are organized in a tree structure similar to i3wm. Workspaces are roots, containers have orientation (h/v), windows are leaves.

**Virtual Workspaces**: AeroSpork doesn't use native macOS Spaces. It implements its own workspace emulation by hiding/showing windows, allowing instant switching without animations.

**Monitor Fingerprinting**: Monitors are identified by vendor ID, model, and serial number, enabling persistent workspace assignments in docking setups.

**Thread-Per-Application**: Performance optimization where accessibility API calls for each app run on separate threads to avoid blocking.

**MRU Tracking**: Tree nodes track most-recently-used order for focus navigation.

## Development Notes

### Running from Xcode
1. Open `Package.swift` (not `AeroSpork.xcodeproj`) in Xcode
2. Edit Scheme → Options → Console → Choose `Terminal`
   - This prevents Accessibility permission requests on every rebuild (debug binaries are unsigned)

### Code Generation
- Some source files have `Generated` suffix - these are auto-generated by `./generate.sh`
- `AeroSpork.xcodeproj` is also generated
- Run `./generate.sh --all` to regenerate everything

### Configuration Files
- Debug: `~/.aerospork-debug.toml`
- Release: `~/.aerospork.toml`
- Default config: `docs/config-examples/default-config.toml`
- Config documentation: `docs/guide.adoc`, `docs/commands.adoc`

### Testing Utilities
- "Accessibility Inspector.app" (built into macOS) for inspecting window properties
- DeskPad or BetterDisplay 2 for emulating multiple monitors
- `script/clean-project.sh` to clean when things go wrong

### Performance Considerations
- Layout calculations can be expensive for workspaces with many windows
- Background layout calculation enabled for >10 windows when `config.performanceConfig.useBackgroundLayoutCalculation` is true
- Cache systems (WindowPropertyCache, LayoutMemoizer) reduce redundant work
- PerformanceMonitor tracks metrics and can adapt debouncing delays

## Dependencies

Managed via Swift Package Manager (Package.swift):
- TOMLKit: TOML parsing
- HotKey: Global hotkey handling
- BlueSocket: Unix socket communication
- swift-collections: Advanced collection types
- ISSoundAdditions: Sound/volume control
- ShellParserGenerated: Local package for shell command parsing

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

Individual test suites in `Sources/AppBundleTests/` covering tree operations, config parsing, shell parsing, and command execution.

## Common Gotchas

- Always use MainActor for tree operations and window management
- The tree structure is mutable and requires careful synchronization
- Window IDs come from private `_AXUIElementGetWindow` API
- macOS Accessibility permissions required for the app to function
- Debug builds are unsigned and must run from Terminal to avoid permission dialogs
- Layout calculations should handle monitor arrangement edge cases (vertical stacking, different widths)
