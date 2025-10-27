# j4

**An i3-like tiling window manager for macOS**

j4 is a tiling window manager for macOS that provides i3-inspired window management with a native macOS experience. Built with performance and usability in mind, j4 offers fast workspace switching, comprehensive configuration options, and a modern settings GUI.

---

## Key Features

- **🪟 Tiling Window Management** - Tree-based layout paradigm inspired by i3
- **⚡ Fast Workspace Switching** - Instant workspace changes without animations
- **⚙️ Settings GUI** - Visual configuration interface for all major settings
- **📝 Plain Text Configuration** - TOML-based config files, dotfiles friendly
- **🔧 CLI First** - Full command-line interface with shell completion
- **🎯 Accessibility-Based** - Uses macOS Accessibility APIs for window control

---

## Installation

### Build from Source

**Debug build** (uses `~/.j4-debug.toml`):
```bash
./build-debug.sh
./run-debug.sh
```

**Release build** (uses `~/.j4.toml`):
```bash
./build-release.sh
# Output in .release/j4.app
```

### Requirements

- macOS 13.0 (Ventura) or later
- Swift 6.2+
- Accessibility permissions

---

## Quick Start

### Configuration

j4 uses TOML configuration files:
- **Debug**: `~/.j4-debug.toml`
- **Release**: `~/.j4.toml`
- **Alternative**: `${XDG_CONFIG_HOME}/j4/j4.toml`

### Settings GUI

Open the settings window to configure j4 visually:

```bash
j4 config
```

The GUI provides access to:
- General settings (start at login, accordion padding)
- Workspace-to-monitor assignments
- Gaps configuration with preview
- Performance tuning
- Key bindings overview
- Advanced settings (read-only display)

### CLI Usage

```bash
j4 focus left              # Focus window to the left
j4 workspace 1             # Switch to workspace 1
j4 move-node-to-workspace 2  # Move window to workspace 2
j4 layout tiles            # Change layout mode
j4 --help                  # Show all commands
```

---

## Development

### Build Commands

```bash
./build-debug.sh              # Build debug version to .debug/
./run-debug.sh                # Run j4.app debug build
./run-cli.sh [args]           # Run j4 CLI
./build-release.sh            # Build release to .release/
```

### Testing

```bash
./run-tests.sh                # Full test suite + lint
./run-swift-test.sh           # Swift tests only
./format.sh                   # Format code with swiftformat
```

### Project Structure

```
Sources/
├── j4App/                 # Main app entry point
├── AppBundle/             # Core window management logic
│   ├── tree/              # Tree data structure (Workspace, Window, Container)
│   ├── command/           # Command implementations
│   ├── config/            # Configuration parsing + validation
│   ├── layout/            # Layout calculation engine
│   ├── monitoring/        # Performance monitoring
│   ├── cache/             # Caching infrastructure
│   └── ui/                # Settings GUI (SwiftUI)
├── Cli/                   # Command-line client
└── Common/                # Shared utilities
```

See `CLAUDE.md` for detailed development guidance.

---

## Architecture

### Tree-Based Layout

j4 manages windows in a tree structure similar to i3:
- **Workspaces** are root nodes
- **Containers** have orientation (horizontal/vertical) and layout (tiles/accordion)
- **Windows** are leaf nodes

### Virtual Workspaces

j4 implements its own workspace system instead of using native macOS Spaces. This enables:
- Instant workspace switching without animations
- No need to disable System Integrity Protection (SIP)
- Flexible workspace-to-monitor assignments

### Monitor Fingerprinting

Workspaces can be assigned to specific monitors using fingerprints (vendor ID, model, serial). This allows persistent workspace assignments across docking/undocking.

---

## Configuration Examples

### Basic Window Management

```toml
[mode.main.binding]
alt-h = 'focus left'
alt-j = 'focus down'
alt-k = 'focus up'
alt-l = 'focus right'

alt-shift-h = 'move left'
alt-shift-j = 'move down'
alt-shift-k = 'move up'
alt-shift-l = 'move right'
```

### Workspace Assignments

```toml
[workspace-to-monitor-force-assignment]
1 = 'main'
2 = 'main'
3 = 'secondary'
4 = 'secondary'
```

### Gaps

```toml
[gaps]
inner.horizontal = 10
inner.vertical = 10
outer.left = 10
outer.bottom = 10
outer.top = 10
outer.right = 10
```

---

## Performance

j4 includes several performance optimizations:

- **Layout Caching**: Memoization prevents redundant calculations
- **Adaptive Debouncing**: Adjusts delays based on workspace complexity
- **Background Calculation**: Complex layouts computed asynchronously
- **Window Property Caching**: Reduces Accessibility API calls

Performance can be tuned via the Settings GUI or config file.

---

## License

MIT License

---

## Status

**Active Development** - j4 is under active development. Features and configuration format may change.
