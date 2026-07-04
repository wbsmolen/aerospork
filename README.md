# aerospork

**An i3-like tiling window manager for macOS**

aerospork is a tiling window manager for macOS that provides i3-inspired window
management with a native macOS experience: fast workspace switching, TOML
configuration with live hot-reload, a lean settings GUI, and first-class support
for DisplayLink displays.

It is a fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace), trimmed
down to a single third-party dependency and reworked for smoothness and clean
multi-monitor / DisplayLink docking.

---

## Key Features

- **🪟 Tiling window management** — tree-based layout paradigm inspired by i3
- **⚡ Instant workspace switching** — virtual workspaces, no macOS Spaces animations
- **🔌 DisplayLink-aware** — stable per-display UUID identity, so workspace-to-monitor pinning survives DisplayLink docks that expose no vendor/model/serial
- **♻️ Config hot-reload** — edits to your config file apply immediately, no manual reload
- **⚙️ Settings GUI** — edit general options, gaps, key bindings, and monitor assignments visually
- **📝 Plain-text TOML config** — dotfiles friendly
- **🔧 CLI first** — full command-line interface with shell completion
- **🪶 Nearly dependency-free** — TOMLKit is the only third-party dependency; sockets, hotkeys, and volume control are native

---

## Installation

### Build from Source

**Debug build** (uses `~/.aerospork-debug.toml`):
```bash
./build-debug.sh
./run-debug.sh
```

**Release build** (uses `~/.aerospork.toml`):
```bash
./build-release.sh
# Output in .release/aerospork.app
```

### Requirements

- macOS 13.0 (Ventura) or later
- Swift 6.2+
- Accessibility permissions

---

## Quick Start

### Configuration

aerospork uses TOML configuration files:
- **Debug**: `~/.aerospork-debug.toml`
- **Release**: `~/.aerospork.toml`
- **Alternative**: `${XDG_CONFIG_HOME}/aerospork/aerospork.toml`

If you have no config file, a complete default config ships with the app
(`docs/config-examples/default-config.toml`) — so you get a working i3-style
keymap out of the box. Copy the parts you want into your own config to
customize. Saved edits (from your editor or the GUI) hot-reload automatically.

### Settings GUI

Open the settings window to configure aerospork visually:

```bash
aerospork config
```

The GUI provides:
- **General** — start at login, default layout/orientation, accordion padding, normalization toggles
- **Gaps** — inner/outer gaps
- **Key Bindings** — add/remove bindings per mode (written back to your config)
- **Workspaces & Monitors** — live monitor list with copyable DisplayLink UUIDs, plus workspace-to-monitor assignments

### CLI Usage

```bash
aerospork focus left                  # Focus window to the left
aerospork workspace 1                 # Switch to workspace 1
aerospork move-node-to-workspace 2    # Move window to workspace 2
aerospork layout tiles horizontal vertical  # Toggle layout mode
aerospork --help                      # Show all commands
```

---

## Development

### Build Commands

```bash
./build-debug.sh              # Build debug version to .debug/
./run-debug.sh                # Run aerospork.app debug build
./run-cli.sh [args]           # Run aerospork CLI
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
├── aerosporkApp/          # Main app entry point
├── AppBundle/             # Core window management logic
│   ├── tree/              # Tree data structure (Workspace, Window, Container)
│   ├── command/           # Command implementations
│   ├── config/            # Configuration parsing, writing, and hot-reload
│   ├── layout/            # Layout calculation engine
│   ├── model/             # Monitors, fingerprinting (incl. DisplayLink UUID)
│   ├── mouse/             # Mouse move/resize handling
│   └── ui/                # Settings GUI + menu bar (SwiftUI)
├── Cli/                   # Command-line client
├── Common/                # Shared utilities (incl. native Unix socket IPC)
└── PrivateApi/            # C shim for _AXUIElementGetWindow
```

See `CLAUDE.md` for detailed development guidance.

---

## Architecture

### Tree-Based Layout

aerospork manages windows in a tree structure similar to i3:
- **Workspaces** are root nodes
- **Containers** have orientation (horizontal/vertical) and layout (tiles/accordion)
- **Windows** are leaf nodes

### Virtual Workspaces

aerospork implements its own workspace system instead of using native macOS
Spaces, enabling instant workspace switching without animations and without
disabling System Integrity Protection (SIP).

### Monitor Identity & DisplayLink

Workspaces can be pinned to specific monitors. Normal displays are matched by
vendor ID / model / serial or name; DisplayLink (USB virtual) displays expose
none of those, so aerospork falls back to the stable per-display UUID from
`CGDisplayCreateUUIDFromDisplayID`. Assignments support a `uuid` match key to pin
a workspace to a specific DisplayLink panel — so two identical DisplayLink
monitors in a dock stay distinct. Screen-configuration changes are debounced to
handle DisplayLink's multi-stage connect/flap, and redundant window frame writes
are skipped to avoid unnecessary framebuffer churn over USB.

### Native, Dependency-Light

The only third-party dependency is **TOMLKit** (config parsing). Everything else
is native: Unix-socket IPC (POSIX), global hotkeys (Carbon), and volume control
(CoreAudio).

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
# Pin a workspace to a specific DisplayLink panel by its stable UUID:
4 = { fingerprint = { uuid = '37D8832A-2D66-02CA-B9F7-8F30A301B230' } }
```

Tip: the settings GUI's **Workspaces & Monitors** tab lists each connected
display's UUID with a copy button.

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

## License

MIT License

---

## Status

**Active Development** — aerospork is under active development. Features and
configuration format may change.
