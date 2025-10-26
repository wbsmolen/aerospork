# AeroSpork

**An i3-like tiling window manager for macOS, focused on performance and user experience**

AeroSpork is a fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace) by nikitabobko, enhanced with significant performance improvements, a polished settings GUI, and refined stability features.

---

## What is AeroSpork?

AeroSpork builds on the solid foundation of AeroSpace to provide an even better tiling window management experience for macOS. While maintaining compatibility with AeroSpace configurations, AeroSpork adds:

### Key Enhancements

- **🚀 26-53% Performance Improvements**
  - Thread-per-application architecture to circumvent macOS blocking AX API
  - Intelligent layout caching with memoization
  - Adaptive debouncing based on system load
  - Background layout calculation for complex workspaces

- **⚙️ Settings GUI**
  - Full settings interface for all configuration options (except keyboard shortcuts)
  - Monitor fingerprinting for persistent workspace-to-monitor assignments
  - Visual gaps preview
  - Configuration validation before saving

- **🔍 Enhanced Debugging**
  - Comprehensive performance monitoring and metrics
  - Structured logging with os.log
  - Debug builds with enhanced telemetry

- **✅ Configuration Safety**
  - Pre-save validation prevents invalid configs
  - TOML format and comment preservation
  - Automatic backups before writing

---

## Key Features (Inherited from AeroSpace)

- **Tiling window manager** based on a tree paradigm
- **i3-inspired** keybindings and workflow
- **Fast workspace switching** without animations, no need to disable SIP
- **Virtual workspaces** - AeroSpork uses its own workspace emulation instead of macOS Spaces
- **Plain text configuration** - Dotfiles friendly TOML format
- **CLI first** - Full command-line interface with manpages and shell completion

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
# Installs to Applications folder
```

### Requirements

- macOS 12.0 (Monterey) or later
- Swift 6.2+
- Accessibility permissions

---

## Configuration

AeroSpork uses TOML configuration files:
- **Debug**: `~/.aerospork-debug.toml`
- **Release**: `~/.aerospork.toml`

Create your config file based on the patterns from the original AeroSpace project, or use the Settings GUI to manage most options.

### Opening Settings GUI

```bash
# Launch the settings window
aerospork config
```

---

## Development

### Build Commands

```bash
./build-debug.sh              # Build debug version to .debug/
./run-debug.sh                # Run AeroSpace.app debug build
./run-cli.sh [args]           # Run aerospork CLI
./build-release.sh            # Build release to .release/
```

### Testing

```bash
./run-tests.sh                # Full test suite + lint
./run-swift-test.sh           # Swift tests only
./format.sh                   # Format code
```

### Project Structure

```
Sources/
├── AeroSporkApp/          # Main app entry point
├── AppBundle/             # Core window management logic
│   ├── tree/              # Tree data structure
│   ├── command/           # Command implementations
│   ├── config/            # Configuration parsing + validation
│   ├── layout/            # Layout calculation engine
│   ├── monitoring/        # Performance monitoring
│   ├── cache/             # Caching infrastructure
│   └── ui/                # Settings GUI
├── Cli/                   # Command-line client
└── Common/                # Shared utilities
```

See `CLAUDE.md` for detailed development guidance.

---

## Performance

AeroSpork achieves **26-53% performance improvements** over stock AeroSpace through:

1. **Thread-per-Application**: Accessibility API calls run in parallel
2. **Layout Caching**: Memoization prevents redundant calculations
3. **Adaptive Debouncing**: Delays adjust based on workspace complexity
4. **Background Calculation**: Complex layouts (>10 windows) computed async

Benchmarks show:
- **Medium workspaces** (6-10 windows): 26% faster
- **Complex workspaces** (15+ windows): 53% faster

---

## Credits

**Original Project**: [AeroSpace](https://github.com/nikitabobko/AeroSpace) by [nikitabobko](https://github.com/nikitabobko)

AeroSpork maintains the core functionality and philosophy of AeroSpace. All credit for the foundational window management system goes to the original AeroSpace project and its contributors.

---

## License

Same as original AeroSpace project (MIT License)

---

## Status

**Active Development** - AeroSpork is being actively developed with a focus on performance, stability, and user experience. Breaking changes may occur as we refine features and architecture.
