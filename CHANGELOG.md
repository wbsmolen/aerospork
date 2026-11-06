# Changelog

Notable changes to AeroSpork, newest first. This file starts at 1.2.0; notes for earlier releases are on the [releases page](https://github.com/wbsmolen/aerospork/releases).

## Unreleased

### Windows stay on their own workspace

- A hidden workspace's windows no longer show up on another monitor. AeroSpork used to park them only in a bottom corner, and when both bottom corners of a monitor touched another display, they sat in plain view there. It now picks a spot for each window, by its size, that no other monitor can see, including off the right or left edge.
- A window that an app won't shrink to fit its tile no longer spills over its neighbours or onto the next monitor. AeroSpork learns the smallest size the app accepts, gives it that, and shrinks the other tiles to make room. If the minimums can't all fit, each window is kept on its own monitor.
- A window the system draws fully transparent no longer takes up an empty tile. It is set aside after a second and comes back to the tiling once it is visible again.
- On quit, a window from a hidden workspace goes back to its workspace's monitor instead of the monitor it was parked against.
- A restart keeps your arrangement. Each monitor comes back showing the workspace it showed, not just the focused one, and an app that answers slowly after a restart gets its windows back on the right workspace instead of the focused one. Minimized windows are remembered too.
- Startup no longer switches the first workspace to accordion when it holds more than three windows. `default-root-container-layout` decides.
- When two monitors trade places, each workspace stays with its physical monitor.
- `summon-workspace` from another monitor trades the two workspaces, and no longer leaves that monitor empty, which could shuffle every monitor.
- `move-workspace-to-monitor` on a hidden workspace no longer replaces what its old monitor is showing.
- A window that first looked like a popup goes to the workspace it appeared on, even if you have switched away by the time it is recognized.
- `close` on a window that asks about unsaved changes no longer turns it into a new window on the focused workspace with its rules run again.

### Responsiveness

- Much lower idle CPU. A refresh no longer asks the system about every running process, which was most of what AeroSpork did while idle.
- Fewer refreshes. A command used to be followed at once by a second full pass; now it is one, coalesced with whatever else happened.
- A steady stream of window events can no longer keep restarting a refresh so that none ever finishes.
- Two fast hotkeys now run strictly in order, so the first can no longer push a stale focus after the second.
- Reading window state takes fewer round trips to each app, and moving or resizing windows ourselves no longer costs an extra read per notification.

### Reliability

- AeroSpork no longer quits when a CLI command is interrupted (Ctrl-C, or a status-bar timeout) before the reply arrives.
- Un-fullscreening or un-minimizing a window can no longer be cancelled by the layout pass that follows it.
- The first wake after launch no longer rebalances workspaces across monitors as if the displays had changed.
- `move --window-id N --boundaries all-monitors-outer-frame` moves window N, not the focused window.
- A monitor fingerprint that names a display no longer skips its `width` and `height`, so two panels with the same name can be told apart by size.
- `focus` can no longer leave floating windows detached, which could crash the app later, if a window stops answering partway through.

### Config and Settings

- A binding added or removed in Raw TOML is no longer undone by the next change in another pane, and the other panes show what Raw TOML applied.
- A window rule still waiting for its command no longer loses other rule edits made alongside it. They are all written once that rule has a command.
- `mode <name>` fails when the config has no such mode, instead of leaving no hotkeys registered. A reload that removes the mode you are in goes back to `main`.
- Converting a config from v1 to v2 happens once at startup. `reload-config --dry-run` and Settings saves no longer rewrite the file that way.
- Settings keeps one backup each time it is opened, plus one per Raw TOML apply. Autosave used to rotate all five backups out within seconds.
- A hotkey that can't be registered, usually because another app owns it, is recorded in the log.
- `start-at-login` only asks macOS to change something when it needs changing, instead of on every reload.
- A Settings change that can't be made to how the file is written is refused with a message. Some, such as a binding in an inline table, used to report success and write nothing.
- A multi-line value, a quoted key or an inline table no longer locks the whole file out of the Settings panes. Only an edit that touches that spelling is refused.
- Changing a monitor pin, an environment variable, the key mapping preset or `inherit-env-vars` now changes that one line. Comments stay and other rows are not re-spelled.
- Editing gaps keeps `[gaps]` where it is in the file, instead of moving it to the top.
- Settings writes new sections as `[keys]`, `[monitors]` and `[on-window]`, including in an older config. Sections that already exist are edited where they are.
- A window rule whose matcher is its own `[on-window-detected.if]` table can be edited in Settings.
- Saving without a change no longer rewrites a file that mixes line endings. Editing such a file in the panes is refused, because it would change every line.
- A Raw TOML apply that was refused no longer takes effect on the next change in another pane.

## 1.2.0 (2026-09-13)

Fixes focus moving to another window when an app is slow to respond ([#39](https://github.com/wbsmolen/aerospork/issues/39)), and several problems with configs migrated from AeroSpace ([#40](https://github.com/wbsmolen/aerospork/issues/40)).

### Upgrade notes

- Every workspace named in `workspaces` (with or without `mod`), in `persistent-workspaces`, or pinned to a monitor now exists even while empty. The default config declares `1-9`, so all nine appear in `list-workspaces --all`, the menu bar and `workspace next`/`prev` from launch. A workspace reached only through a binding is still created when you switch to it and released once empty.
- Starting AeroSpork while it is already running prints "AeroSpork is already running" and exits. Debug and release builds can still run side by side.
- AeroSpork no longer manages its own windows, so the settings window is never tiled or moved to a workspace.
- `config-version`, `auto-reload-config`, `on-mode-changed` and `focus-follows-mouse` are reported and ignored. Previously any of them made AeroSpork reject the whole config and run its default.

### Focus and unresponsive apps

- A window whose app is slow to answer Accessibility requests is no longer treated as closed. Previously it was dropped, focus moved to another window, and the window could come back on a different workspace.
- Focus moves after a window closes only if that window was focused. If macOS moves focus to another workspace because of the close, AeroSpork brings it back.
- A late answer from a busy app no longer pulls you back across a workspace switch.
- A minimized window comes back on its own workspace rather than the one you are on.
- While an app is hung, a workspace switch waits about a second for it, not a second per window.
- `killall AeroSpork` exits within 10 seconds even when AeroSpork itself is stuck.

### Window rules

- A rule applies without clicking the window when the app was still starting, or when the window first looked like a popup.
- A rule's command list always runs to the end. Previously a refresh at the wrong moment could stop it after `layout tiling`.

### Callbacks

- `exec-and-forget` run from `on-focused-workspace-changed` now receives `AEROSPORK_FOCUSED_WORKSPACE` and `AEROSPORK_PREV_WORKSPACE`, so the documented replacement for `exec-on-workspace-change` works.

### Settings

- Settings comes to the front when opened from the menu, with `aerospork open-settings`, or by opening AeroSpork again from Finder or Spotlight.
- A change made just before closing the window is saved instead of dropped.
- A saved change takes effect on screen immediately.
- The General pane says which settings apply only to new workspaces, and that turning off a normalization does not undo earlier changes.

### Coming from AeroSpace

- `persistent-workspaces` is supported.
- When only an AeroSpace config exists, AeroSpork says that it is running its default config.
- A string `if` in `[[on-window-detected]]` is rejected with an error that names the table form.
- A command that still uses `AEROSPACE_*` variables or the `aerospace` CLI loads with a warning naming the line.
- The guide has a new "Coming from AeroSpace" section.

### Troubleshooting

- AeroSpork logs a startup record with its version and whether verbose tracing is on, and logs focus changes it makes on its own under the `session` category.
- The troubleshooting guide and bug report template give the right log subsystem for release builds and explain how to capture a verbose trace.
