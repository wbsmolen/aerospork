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
Integrity Protection. It is configured in TOML, driven from a CLI, and ships a Settings window.

It is a fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace) by Nikita Bobko, which is
where the tree model, the workspace emulation and most of the command surface come from. Both are
MIT licensed; see [`legal/`](legal/).

<div align="center">
  <img src="docs/assets/layout-modes.png" alt="Tiles layout beside accordion layout" width="820">
</div>

## Quick start

1. Install with Homebrew:

   ```bash
   brew install --cask wbsmolen/tap/aerospork
   ```

2. Open AeroSpork. macOS asks for Accessibility permission, and AeroSpork quits.
3. Open System Settings > Privacy & Security > Accessibility, and enable AeroSpork.
4. Open AeroSpork again. It tiles the windows on your screen.
5. Try the default bindings: `alt-h/j/k/l` move the focus, `alt-shift-h/j/k/l` move a window,
   `alt-1` to `alt-9` switch workspaces, `alt-shift-2` sends a window to workspace 2, and
   `alt-slash` and `alt-comma` change the layout.
6. To change anything, open Settings from the menu bar icon.

Also disable "Displays have separate Spaces" in System Settings. The
[guide](https://aerospork.app/docs/guide.html#a-note-on-displays-have-separate-spaces) says why.
[Get started](https://aerospork.app/docs/guide.html#get-started) in the guide has the same steps in
more detail.

## How it differs from AeroSpace

The tree model, virtual workspaces, SIP-free operation, TOML config and the CLI come from AeroSpace
and work the same way. The table lists only the differences.

| | AeroSpace | AeroSpork |
|---|:---:|:---:|
| Monitor matching by hardware UUID / EDID | ❌ &nbsp;name, regex or number only | ✅ &nbsp;also pins DisplayLink panels |
| Settings window | ❌ &nbsp;"will never provide a GUI for configuration" | ✅ &nbsp;7 native panes |
| Notarized builds | ❌ | ✅ &nbsp;signed, notarized, stapled |
| Third-party dependencies | 4 | **2** |
| Config schema | one syntax | v2 shorthand, older syntax still parses |
| Windows keep their workspace across a restart | ❌ | ✅ &nbsp;with their monitor and layout |
| Command surface | **larger** | smaller |
| Maturity | **public beta, larger community** | younger fork |

<sub>Upstream column checked against
AeroSpace <code>main</code> on 2026-07-29: its README
says AeroSpace "will never provide a GUI for configuration" and that "it's not notarized", its
<code>Package.swift</code> declares four dependencies, and its guide documents monitor patterns as
main/secondary/number/regex only.</sub>

## Coming from AeroSpace

AeroSpork is a fork, not a drop-in replacement. Configs and scripts need small edits:

- Copy your config to `~/.aerospork.toml`. AeroSpork does not read `~/.aerospace.toml`, and with no
  AeroSpork config it runs its default config with no message.
- Rename `AEROSPACE_*` variables to `AEROSPORK_*`, and the `aerospace` CLI to `aerospork`.
- A config in the v1 spelling (`[mode.main.binding]`) is rewritten in the v2 spelling on first start.
  The original, with its comments, stays next to it as `<name>.pre-v2`.

[Switch from AeroSpace](https://aerospork.app/docs/guide.html#coming-from-aerospace) in the guide
lists every difference.

## Other ways to install

Download `aerospork-v<version>.zip`, the notarized universal (arm64 + x86_64) build, from the
[releases page](https://github.com/wbsmolen/aerospork/releases), and move `AeroSpork.app` to
`/Applications`. To use the CLI from a zip install, link it onto your `PATH` as the
[guide](https://aerospork.app/docs/guide.html#manual-installation) shows. AeroSpork needs macOS 13 or
later.

AeroSpork asks on its second launch whether to check for updates automatically, and
**Check for updates…** in the menu bar checks at once. The update check is the only network request
AeroSpork makes. The [privacy page](https://aerospork.app/privacy.html) lists what AeroSpork stores
and sends: no analytics, no telemetry, and no system profile. [CHANGELOG.md](CHANGELOG.md) lists the
changes in each release.

## Configure

AeroSpork reads `~/.aerospork.toml` or `~/.config/aerospork/aerospork.toml`. Without either, it runs
the [default config](docs/config-examples/default-config.toml), which ships inside the app. A saved
change applies at once. A starting point:

```toml
mod = "alt"                 # generates the i3 keymap: alt-h/j/k/l, alt-shift-h/j/k/l, ...
workspaces = "1-9"          # these nine always exist; alt-1..9 to switch, alt-shift-1..9 to move a window

[gaps]
inner = 8
outer = 8

[keys]                      # anything here overrides a generated binding
alt-shift-semicolon = "mode service"

[keys.service]
esc = ["reload-config", "mode main"]

# [monitors]                # pin a workspace to a monitor
# 2 = { uuid = "..." }      # from `aerospork list-monitors --format '%{monitor-fingerprint}'`

[on-window]                 # where a window goes when it appears
"com.apple.mail" = "move-node-to-workspace 3"
```

The Settings window edits the same file and keeps your comments. Open it from the menu bar icon, or
with `aerospork open-settings`. The [guide](https://aerospork.app/docs/guide.html) documents every
key. The same docs are in [`docs/`](docs/).

## Use the CLI

```bash
aerospork focus left                        # focus the window to the left
aerospork workspace 1                       # switch to workspace 1
aerospork move-node-to-workspace 2          # move the focused window to workspace 2
aerospork list-monitors                     # the connected monitors
aerospork --help
```

Every command has a man page and completions for bash, fish and zsh. The
[command reference](https://aerospork.app/docs/commands.html) lists them all.

## Get help

To report a bug, follow
[Troubleshooting and bug reports](https://aerospork.app/docs/guide.html#troubleshooting) in the guide,
then [open an issue](https://github.com/wbsmolen/aerospork/issues/new?template=bug_report.md). For a
security problem, see [SECURITY.md](SECURITY.md).

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

- **The DisplayLink problem** is `model/MonitorFingerprint.swift`. A display is matched on its
  per-display UUID when the pattern gives one. Otherwise every key the pattern gives (EDID vendor,
  model and serial from CoreGraphics, size, name) has to match.
  DisplayLink panels report no EDID at all, so the UUID is the only key that separates two of them.
  Screen reconfiguration is also debounced, because a dock connects in several stages and fires the
  change notification more than once.
- **The sluggishness** is two changes rather than a rewrite. Bursts of accessibility events coalesce
  into one layout pass on a 50ms debounce (`util/RefreshScheduler.swift`), and `MacApp.setFrame`
  skips the AX write when a window already sits at its target frame, which matters over a
  DisplayLink link where every write repaints a framebuffer. I have not published speedup numbers;
  `dev-docs/performance.md` says which measurements exist and why the benchmark could not settle
  the rest.
- **The drift** is mostly workspace lifecycle. Workspaces the config declares always exist; any other
  is created on demand and released when it empties, instead of being materialized for every name a
  keybinding mentions.

## Why these choices

If you compare AeroSpork with upstream, these are the reasons behind its stack. The stack itself is
in [`dev-docs/architecture.md`](dev-docs/architecture.md#tech-stack).

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
outside the process knows that a window belongs to one. AeroSpork remembers each window's workspace,
the monitor each workspace was on, and each workspace's layout, keyed on the window id that the macOS
window server issues. That id is stable for as long as the window server runs: an update, a crash or a
quit keeps it, and a logout, a reboot or an app that relaunches does not. Where the id is gone, there
is no honest way to recognize a window, because every terminal window reports the same accessibility
identifier. So AeroSpork places that window by its location and does not guess, and a window rule
(`[on-window]`) remains the way to state intent.

**The Xcode project is generated, not committed.** `project.yml` plus XcodeGen produces it, because
SwiftPM cannot build an app bundle but a checked-in `.pbxproj` is a merge conflict waiting to happen.
Debug builds skip Xcode entirely.

**The config writer is line-based on purpose.** Re-serializing the whole file would be far simpler,
and would destroy every comment plus anything the GUI cannot model, such as per-monitor gap arrays.
Instead it rewrites only the keys you changed, preserves what the panes cannot model (a rich
monitor fingerprint, a fallback list) field for field on every save, and refuses the few shapes it
cannot rewrite safely, pointing you at the Raw TOML pane. That is what makes a GUI safe to put on
top of a dotfile.

## Contribute

[CONTRIBUTING.md](CONTRIBUTING.md) says how to build AeroSpork, run the checks and open a pull
request.

## License

MIT. The original AeroSpace copyright is retained alongside the fork's in
[`LICENSE.txt`](LICENSE.txt). Active development; features and configuration may still
change.
