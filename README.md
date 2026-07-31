<div align="center">

<img src="docs/assets/readme-banner.png" alt="AeroSpork — an i3-like tiling window manager for macOS" width="820">

<p>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-000?logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE.txt"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

</div>

AeroSpork is an i3-style tiling window manager for macOS. Windows are leaves of a layout tree,
workspaces are emulated rather than mapped onto native Spaces, and nothing requires disabling System
Integrity Protection. It is configured in TOML, driven from a CLI, and ships a settings GUI.

It is a fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace) by Nikita Bobko, which is
where the tree model, the workspace emulation and most of the command surface come from. Both are
MIT licensed; see [`legal/`](legal/).

<div align="center">
  <img src="docs/assets/layout-modes.png" alt="Tiles layout beside accordion layout" width="820">
</div>

## Why I forked it

I ran AeroSpace daily on four monitors behind a DisplayLink dock, and three things wore me down. It
felt sluggish. Long sessions drifted, so state that was correct at login was not correct by the
evening. And the DisplayLink panels were a coin flip: workspaces came back on the wrong screens
after every undock, because monitors are matched by name, regex or index, and none of those survive
a redock. Two identical displays are indistinguishable to a name match.

I sent the monitor work upstream as
[PR #1526](https://github.com/nikitabobko/AeroSpace/pull/1526) in July 2025. It was closed the next
day without review. That is the maintainer's call on their own project, and upstream is clear that
it keeps a deliberately small surface, so I kept the work here instead.

What that turned into, in this codebase:

- **The DisplayLink problem** is `model/MonitorFingerprint.swift`. A display is matched on the
  per-display UUID first, then EDID vendor/model/serial from CoreGraphics, then name, then size.
  DisplayLink panels report no EDID at all, so the UUID is the only key that separates two of them.
  Screen reconfiguration is also debounced, because a dock connects in several stages and fires the
  change notification more than once.
- **The sluggishness** is two changes rather than a rewrite. Bursts of accessibility events coalesce
  into one layout pass on a 50ms debounce (`util/RefreshDebouncer.swift`), and `MacApp.setFrame`
  skips the AX write when a window already sits at its target frame, which matters over a
  DisplayLink link where every write repaints a framebuffer. I have not published speedup numbers;
  `dev-docs/performance.md` says which measurements exist and why the benchmark could not settle
  the rest.
- **The drift** is mostly workspace lifecycle. Workspaces are created on demand and released when
  they empty, instead of being materialized for every name a keybinding mentions.

## Tech stack

| Concern | Implementation |
|---|---|
| Language | Swift, 6.0 language mode (`Package.swift`); `.swift-version` pins toolchain 6.4 |
| Minimum OS | macOS 13.0 (Ventura) |
| UI | SwiftUI: a `MenuBarExtra` and a `Settings` scene |
| Third-party dependencies | TOMLKit (config parsing) and Sparkle (in-app updates) |
| CLI/app IPC | POSIX `AF_UNIX` stream socket, length-prefixed framing (`Sources/Common/util/UnixSocket.swift`) |
| Global hotkeys | Carbon `RegisterEventHotKey` (`config/HotkeyBinding.swift`) |
| Volume control | CoreAudio (`util/SystemVolume.swift`) |
| Display identity | CoreGraphics `CGDisplayCreateUUIDFromDisplayID`, `CGDisplayVendorNumber`, `CGDisplayModelNumber`, `CGDisplaySerialNumber` |
| Window IDs | C shim over the private `_AXUIElementGetWindow` (`Sources/PrivateApi/`) |
| Build | SwiftPM for the CLI and debug builds; XcodeGen plus `xcodebuild` for the `.app`, since SwiftPM cannot produce a bundle |

### Why these choices

If you are weighing this against upstream, the reasoning matters more than the table.

**Two dependencies instead of four, and each removal was a wrapper going away.** BlueSocket was
wrapping a local Unix socket, so it became `AF_UNIX` directly. HotKey was wrapping Carbon's
`RegisterEventHotKey`, which is one call plus the bookkeeping to unregister it. ISSoundAdditions was wrapping CoreAudio.
swift-collections supplied one ordered dictionary. The ANTLR-generated shell grammar parsed command
strings that `/bin/bash -c` already parses. Every one of those is a thing that can break on an OS
update, or need a version bump before the app can be rebuilt, in exchange for code the platform
already provides. Sparkle is the one addition, and only because there is no App Store update path
to inherit.

**Display identity comes from CoreGraphics, not IOKit.** Upstream reads EDID through
`IOServiceMatching("IODisplayConnect")`. That IOKit class does not exist on Apple Silicon, so the
iterator yields nothing and vendor/model/serial come back `nil` for every display. CoreGraphics
returns the same values and adds the per-display UUID, which is the only field that survives a
DisplayLink dock.

**The private `_AXUIElementGetWindow` stays, and it costs something.** It is the only way to get a
window id that is stable across refreshes, and window identity is what the whole tree is keyed on.
The price is that the Mac App Store is permanently out: private symbols fail review, and the
Accessibility APIs this app is built on do not work in a sandbox anyway. Hence Developer ID signing,
notarization, and Sparkle rather than TestFlight.

**Workspace placement survives a restart of AeroSpork.** Workspaces are emulated, so nothing
outside the process knows a window belongs to one; at a cold start a window is bound by where it
physically sits, and the workspace chosen for each monitor is the first key-bound name in sort order
— which a named workspace like `A` can never be. Placement is now remembered, keyed on the window id
the macOS window server issues. That id is stable for exactly as long as that server runs, so an
update, a crash or a Quit keeps it and a logout, a reboot or an application relaunching does not.
Where the id is gone there is no honest way to recognise a window — every terminal window reports the
same accessibility identifier — so it falls back to placing by location rather than guessing, and
`on-window-detected` remains the way to state intent.

**The Xcode project is generated, not committed.** `project.yml` plus XcodeGen produces it, because
SwiftPM cannot build an app bundle but a checked-in `.pbxproj` is a merge conflict waiting to happen.
Debug builds skip Xcode entirely.

**The config writer is line-based on purpose.** Re-serializing the whole file would be far simpler,
and would destroy every comment plus anything the GUI cannot model, such as per-monitor gap arrays.
Instead it rewrites only the keys you changed and refuses edits it cannot represent, pointing you at
the raw TOML tab. That is what makes a GUI safe to put on top of a dotfile.

```
Sources/
├── aerosporkApp/    # app entry point (@main)
├── AppBundle/       # the window manager: tree/, layout/, command/, config/, model/, mouse/, ui/
├── Cli/             # command-line client
├── Common/          # shared with the CLI, incl. the socket implementation
└── PrivateApi/      # C shim for _AXUIElementGetWindow
```

## Differences from AeroSpace

The tree model, virtual workspaces, SIP-free operation, TOML config and the CLI are inherited and
behave the same way. Only the deltas are listed.

| | AeroSpace | AeroSpork |
|---|:---:|:---:|
| Monitor matching by hardware UUID / EDID | ❌ &nbsp;name, regex or number only | ✅ &nbsp;also pins DisplayLink panels |
| Settings GUI | ❌ &nbsp;"will never provide a GUI for configuration" | ✅ &nbsp;7 tabs |
| Notarized builds | ❌ | ✅ &nbsp;signed, notarized, stapled |
| Third-party dependencies | 4 | **2** |
| Config schema | one syntax | v2 shorthand, older syntax still parses |
| Windows keep their workspace across a restart | ❌ | ✅ &nbsp;also their monitor |
| Command surface | **larger** | smaller |
| Maturity | **public beta, larger community** | younger fork |

<sub>Upstream column checked against
<a href="https://github.com/nikitabobko/AeroSpace">nikitabobko/AeroSpace</a> <code>main</code> on 2026-07-29: its README
says AeroSpace "will never provide a GUI for configuration" and that "it's not notarized", its
<code>Package.swift</code> declares four dependencies, and its guide documents monitor patterns as
main/secondary/number/regex only.</sub>

**Config schema.** `mod` plus `workspaces` generates the usual i3 keymap, and `[keys]`, `[monitors]`
and `[on-window]` replace the longer upstream spellings. An existing config is migrated once on
first launch, and only when the result is proven to parse to the same effective configuration;
otherwise the file is left alone. The original is kept beside it as `*.pre-v2`.

**Settings GUI.** Seven tabs over a comment-preserving writer that only rewrites the keys you
changed, so opening Settings and changing nothing leaves the file byte-identical and editing one
section never rewrites another. A raw TOML tab validates against the same parser the app uses at
startup, so no config key is unreachable from the GUI.

### Coming from AeroSpace

A fork, not a drop-in replacement. Configs and scripts need small edits.

- `AEROSPACE_*` environment variables are gone and not aliased. A script reading
  `$AEROSPACE_FOCUSED_WORKSPACE` gets an empty string with no error. The names are
  `AEROSPORK_FOCUSED_WORKSPACE`, `AEROSPORK_PREV_WORKSPACE`, `AEROSPORK_WINDOW_ID` and
  `AEROSPORK_WORKSPACE`.
- `if.during-aerospace-startup` is spelled `if.during-aerospork-startup`. Unknown keys are fatal, so
  the old spelling fails at startup and names the line.
- Feature parity is a non-goal. The fork carries less surface area than upstream.

## Installation

Download the notarized universal (arm64 + x86_64) build from the
[releases page](https://github.com/wbsmolen/aerospork/releases), move `AeroSpork.app` to
`/Applications`, and grant Accessibility permission when prompted. A Homebrew cask is published at
[`wbsmolen/tap`](https://github.com/wbsmolen/homebrew-tap):

```bash
brew install --cask wbsmolen/tap/aerospork
```

Both the tap and this repository are public, so either route works without a GitHub account.

Installed copies check for updates themselves through [Sparkle](https://sparkle-project.org),
against a signed appcast served from
[`aerospork.app/appcast.xml`](https://aerospork.app/appcast.xml). Updates are verified against an
EdDSA public key in the app's Info.plist, so a build refuses anything it cannot verify. Automatic
checking is off until you allow it; **Check for Updates…** in the menu bar checks on demand. There
is no App Store update path to inherit, because the Accessibility APIs this app is built on do not
work in a sandbox.

Because update checks are the only network request AeroSpork can make, and the Accessibility
permission it needs is a broad one, [aerospork.app/privacy.html](https://aerospork.app/privacy.html)
sets out exactly what is stored, what is sent, and what is not: no analytics, no telemetry, and no
system profile.

## Configuration

AeroSpork reads whichever of these exists, and reports an error at startup if both do:
`~/.aerospork.toml` or `${XDG_CONFIG_HOME}/aerospork/aerospork.toml` (`XDG_CONFIG_HOME` defaults to
`~/.config`). With neither, it falls back to a complete default bundled in the app, also checked in
as [`docs/config-examples/default-config.toml`](docs/config-examples/default-config.toml). Saved
changes hot-reload, so you never need to run `reload-config` by hand.

```toml
mod = "alt"                 # generates the i3 keymap: alt-h/j/k/l, alt-shift-h/j/k/l, ...
workspaces = "1-9"          # alt-1..9 to switch, alt-shift-1..9 to move a window

[gaps]
inner = 8
outer = 8

[keys]                      # anything here overrides a generated binding
alt-enter = "exec-and-forget open -na Ghostty"

[monitors]                  # pin a workspace to a screen
1 = "main"
2 = { uuid = "AAAAAAAA-0000-4000-8000-000000000001" }

[on-window]                 # where a window goes when it appears
"com.apple.mail" = "move-node-to-workspace 3"
```

Run `aerospork list-monitors --format '%{monitor-fingerprint}'` to get the values to paste into
`[monitors]`. Open the GUI from the menu bar icon, with **⌘,** while AeroSpork is frontmost, or via
`aerospork open-settings`, which is also valid in config and so bindable. Structured tabs apply live
on a 600ms debounce; the raw TOML tab has an explicit Apply, because half-typed TOML is invalid most
of the time.

## CLI

36 subcommands, with man pages and bash/fish/zsh completion. `exec-and-forget` is documented as a
37th command but is config-only.

```bash
aerospork focus left                        # focus the window to the left
aerospork workspace 1                       # switch workspace
aerospork move-node-to-workspace 2          # move the focused window
aerospork layout tiles horizontal vertical  # cycle layout
aerospork list-monitors                     # connected displays and how they are identified
aerospork --help
```

Troubleshooting: `aerospork config --config-path` prints the file actually loaded. A path inside the
`.app` bundle means no user config is loaded, either because you have none or because yours failed to
parse; `aerospork reload-config --dry-run` parses without applying and says which. `aerospork
--version` reports both client and server. Logs go to the unified log, with no files and nothing to
enable:

```bash
log show --last 1h --predicate 'subsystem == "com.wbs.aerospork"' --style compact
```

Use `com.wbs.aerospork.debug` for a debug build and add `AND category == "config"` to narrow.
`AEROSPORK_DEBUG_LOG=1` adds a verbose per-refresh trace. It is written at `.debug` level, which
the unified log does not persist, so run the binary directly and read its stderr. See
*Troubleshooting and bug reports* in [the guide](docs/guide.adoc) for what to attach to a report.

## Development

```bash
./build-debug.sh     # SwiftPM debug build into .debug/ (uses ~/.aerospork-debug.toml)
./build-release.sh   # signed release; needs a Developer ID Application certificate
./run-tests.sh       # tests, format and lint
./build-docs.sh      # man pages and docs site
```

The suite is headless, using a fake window tree and a mocked Accessibility layer, so it needs no real
windows and no Accessibility permission. `Package.swift` uses SE-0439 trailing commas, so the floor is
Swift 6.1 (Xcode 16.3); `.swift-version` pins 6.4 for reproducibility.

[`.claude/skills/aerospork-design/`](.claude/skills/aerospork-design/) holds the design system:
tokens, components, three click-through UI kits and the brand artwork. It is derived from
`Sources/AppBundle/ui/`, so the Swift is the source of truth. Read it before adding a settings
surface. `UIChromeConsistencyTest` enforces the two rules that matter: shared controls live in
[`SettingsChrome.swift`](Sources/AppBundle/ui/SettingsChrome.swift) and a tab never grows its own
copy, and status symbols come from `StatusLabel.Kind` rather than string literals.

[`CONTRIBUTING.md`](CONTRIBUTING.md) covers the gate and the invariants the tests enforce.
[`dev-docs/`](dev-docs/) has architecture notes, contributor setup including code signing, testing
strategy and performance measurement.

## License

MIT. The original AeroSpace copyright is retained alongside the fork's in
[`LICENSE.txt`](LICENSE.txt). Active development; features and configuration may still
change.
