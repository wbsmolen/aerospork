# Changelog

Notable changes to AeroSpork, newest first. This file starts at 1.2.0; notes for earlier releases are on the [releases page](https://github.com/wbsmolen/aerospork/releases).

## 1.3.2 (2026-11-06)

A restart now brings back your whole layout, floating windows can be moved and resized from the keyboard, and updates require a signed feed.

### Upgrade notes

- A window rule no longer runs again on a window that was already open when AeroSpork restarted, because that could undo a move you made by hand. Rules with `if.during-aerospork-startup = true` still do.
- AeroSpork now refuses an update feed that isn't signed. The feed at aerospork.app is, so nothing changes unless you serve your own.

### A restart keeps everything

- Nested containers, each container's layout and orientation, and which windows are fullscreen in AeroSpork all come back, on top of the order and sizes 1.3.1 added. It doesn't matter which app answers first.
- A floating window stays where you put it when AeroSpork quits, instead of moving to the center of its monitor. That holds on a hidden workspace too, and after a crash.
- A minimized window keeps its place across any number of restarts, not just the first.
- An app that answers late still gets its place back, until you change a layout. From then on a late window goes wherever a new one would, so it can't undo what you just did.

### Floating windows

- `move` moves a floating window by 50 points and stops at the edge of its monitor. `--boundaries all-monitors-outer-frame` takes it on to the next monitor.
- `resize` resizes a floating window. `smart` changes its width and `smart-opposite` its height, and it stays on its monitor.
- Directional `focus` works on a workspace that has only floating windows. It used to find nothing.
- Switching to a workspace with only floating windows focuses the most recent one, not whichever came first.

### Other fixes

- `focus --window-id` brings back a minimized window or a window of a hidden app, and `macos-native-minimize --window-id` unminimizes one. Both used to do nothing.
- `move-mouse` after another command in the same binding goes to where the window is now, not where it was.
- A learned minimum window size is asked about again whenever the windows in its row change, so one that has since come down no longer stays. An accordion's minimum now counts its padding, so windows in one no longer overlap their neighbours by it.
- An app that turns into a regular app without launching or activating, like a background agent opening a window, is noticed within 30 seconds rather than whenever it is next activated.
- Adding a section to a config with no final newline and removing it leaves the file as it was.
- `resize` on a window in an accordion says why it can't, rather than claiming the window is floating.

## 1.3.1 (2026-11-06)

Fixes a crash when removing a window rule in Settings, and brings back window order and sizes after a restart.

### Fixes

- Removing a window rule in Settings could quit AeroSpork, leaving hidden workspaces' windows off screen until it was opened again. A text field still being edited could also write into the rule below the one removed.
- A restart keeps the order of the windows on each workspace, the sizes you dragged them to, and which ones were floating. Nested containers and a workspace's own layout still start fresh.
- On quit, a window from a hidden workspace could be parked off screen again after it had been restored, and an app that failed to answer left every window after it off screen.
- A learned minimum window size can now come down. Dragging a window smaller than the minimum on record lowers it, and `balance-sizes` and `flatten-workspace-tree` forget it. A minimum that is still real is learned again on the next layout.
- Settings no longer writes the config, reloads it and takes a backup when nothing changed. Merely opening it could do that, and each one pushed a real backup out of the five kept.
- Changing a gap and changing it back leaves your config as it was. Gaps keep the short `inner = 0` spelling when the values match, instead of expanding to six lines.
- A refresh no longer asks LaunchServices for AeroSpork's own activation policy or for each app's name.

## 1.3.0 (2026-11-05)

Fixes windows showing up on the wrong workspace or monitor, an invisible window holding an empty tile, and a restart scrambling your arrangement. Also makes each refresh cheaper, and makes Settings safer with your config file.

### Upgrade notes

- AeroSpork now asks once whether to check for updates automatically: on the first launch after this update, or the second launch of a new install. A setting told the update framework never to check and never to ask, so you only got an update by choosing **Check for Updates…**.
- Startup no longer switches the first workspace to accordion when it holds more than three windows. `default-root-container-layout` decides.
- `%{monitor-fingerprint}` now prints a table you can paste into `[monitors]`, as the docs always said it could. Anything parsing the old `vendor:… name:…` output needs updating.
- `mode <name>` fails when the config has no such mode, instead of leaving no hotkeys registered. A reload that removes the mode you are in goes back to `main`.
- Runtime error reports are written to `~/Library/Logs/com.wbs.aerospork/`, not to a directory in `/tmp` shared with other accounts.

### Windows stay on their own workspace

- A hidden workspace's windows no longer show up on another monitor. AeroSpork used to park them only in a bottom corner, and when both bottom corners of a monitor touched another display, they sat in plain view there. It now picks a spot for each window, by its size, that no other monitor can see, including off the right or left edge.
- A window that an app won't shrink to fit its tile no longer spills over its neighbours or onto the next monitor. AeroSpork learns the smallest size the app accepts, gives it that, and shrinks the other tiles to make room. If the minimums can't all fit, each window is kept on its own monitor.
- A window the system draws fully transparent no longer takes up an empty tile. It is set aside after a second and comes back to the tiling once it is visible again.
- On quit, a window from a hidden workspace goes back to its workspace's monitor instead of the monitor it was parked against.
- A restart keeps your arrangement. Each monitor comes back showing the workspace it showed, not just the focused one, and an app that answers slowly after a restart gets its windows back on the right workspace instead of the focused one. Minimized windows are remembered too.
- When two monitors trade places, each workspace stays with its physical monitor.
- `summon-workspace` from another monitor trades the two workspaces, and no longer leaves that monitor empty, which could shuffle every monitor.
- `move-workspace-to-monitor` on a hidden workspace no longer replaces what its old monitor is showing.
- A window that first looked like a popup goes to the workspace it appeared on, even if you have switched away by the time it is recognized.
- `close` on a window that asks about unsaved changes no longer turns it into a new window on the focused workspace with its rules run again.

### Responsiveness

- Lower CPU use. A refresh no longer asks the system about every running process, which took most of the time in each one.
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
- A window rule with no command says so in the pane, since rule changes aren't saved until every rule has one.

### Security and updates

- Updates are verified before they are unpacked, not after. This starts with the update after the one that brings it.
- The CLI reads stdin only for `workspace next`/`prev` and `move-node-to-workspace next`/`prev`. Every other command used to read it too, which swallowed the input of a `while read` loop.
- CLI clients that connect and stall can no longer hold up the rest of the app. Each request and each reply has 30 seconds to finish.
- If another account already holds the CLI socket's path, AeroSpork logs it and runs without the CLI, instead of refusing to start.
- The CLI and the app each hang up if the other end of the socket is running as a different user.
- Error dialogs no longer fail to appear when the message contains a backslash, and a message can no longer run as a script.
- A scheduled update alert comes to the front instead of opening unseen behind your windows.
- Commands run by AeroSpork no longer get a trailing `:` on `PATH`, which means the current directory, when it starts with no `PATH` set.
- Remembering windows across a restart no longer mistakes another process named WindowServer for the real one, or gives up if the process list grows while it reads it.

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
