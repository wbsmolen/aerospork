# j4 Distribution

This directory contains a pre-built macOS application bundle for j4.

## Distribution Note

**j4 is distributed outside the Mac App Store** because it requires Accessibility API access for window management, which is not available to sandboxed Mac App Store apps. The app uses automatic code signing and notarization for secure distribution outside the App Store.

### Why Not App Store?

macOS Accessibility API (required for window manipulation) is blocked in sandboxed apps. This is a fundamental limitation affecting all advanced window managers. Apps like Rectangle, Amethyst, yabai, and Moom 4 use the same distribution approach.

### Security

The app is:
- Signed with a valid Apple Developer ID certificate (automatic signing)
- Notarized by Apple for Gatekeeper verification
- Requires explicit user permission for Accessibility access

## Quick Start

1. **Download** the `j4.app` from this directory or GitHub releases
2. **Move** `j4.app` to your `/Applications` folder
3. **Run** j4.app (you may need to right-click → Open the first time)
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
