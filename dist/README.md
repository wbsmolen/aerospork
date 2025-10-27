# j4 Distribution

This directory contains a pre-built macOS application bundle for j4.

## Quick Start

1. **Download** the `j4.app` from this directory
2. **Move** `j4.app` to your `/Applications` folder
3. **Run** j4.app
4. **Grant** Accessibility permissions when prompted (required for window management)

## What's Included

- **j4.app**: Complete macOS application bundle
  - Executable: `Contents/MacOS/j4`
  - App Icon: `Contents/Resources/AppIcon.icns`
  - Metadata: `Contents/Info.plist`

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permissions

## Building from Source

If you prefer to build from source:

```bash
./build-debug.sh              # Build debug version
./run-debug.sh                # Run debug build
```

See the main [README.md](../README.md) for full build instructions.

## Configuration

j4 uses TOML configuration files:
- Config location: `~/.j4.toml`
- Alternative: `${XDG_CONFIG_HOME}/j4/j4.toml`

Open settings GUI:
```bash
j4 config
```

## License

MIT License - See LICENSE file in the repository root.
