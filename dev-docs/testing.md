# Testing

This document describes the tests that exist, the seams they use, and what they cannot see. The work
that is still open is in [issue #61](https://github.com/wbsmolen/aerospork/issues/61).

## Run the tests

```bash
AEROSPORK_SWIFT=xcrun ./run-tests.sh                                          # the full check
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test     # Swift tests only
```

`run-tests.sh` builds, runs both test targets, checks the CLI, lints, and checks that the generated
files are current. `dev-docs/development.md` lists its steps and explains the toolchain rule.

CI (`.github/workflows/ci.yml`) runs `run-tests.sh` on a hosted `macos-latest` runner, then an
unsigned Release build and `shellcheck`. The `test` job is a required status check on `main`.

## What the suite covers

There are two test targets, `AppBundleTests` and `CommonTests`. Both run with no windows, no
monitors and no Accessibility permission. This document gives no test count, because a count goes
stale. Run the suite to see it.

| Area | Where |
|---|---|
| Tree operations, normalization, focus order | `AppBundleTests/tree/`, `AppBundleTests/command/` |
| Each command | `AppBundleTests/command/*CommandTest.swift`, `List*Test.swift` |
| Layout geometry | `LayoutRecursiveTest` |
| Config parse, v1 to v2 migration, round trip | `AppBundleTests/config/` |
| The config writer: no-op saves, safety, backups, fuzz | `ConfigTest`, `ConfigurationWriterSafetyTest`, `ConfigSafety*Test`, `ConfigSafetyWriterFuzzTest` |
| Settings logic, pane metadata, render smoke of all seven panes | `UISettingsTest`, `UIKeysBindingsTest`, `UIRenderSmokeTest`, `SettingsApplyTest` |
| Shared Settings chrome | `UIChromeConsistencyTest` |
| Window-kind heuristics on captured AX trees | `AxWindowKindTest` with `axDumps/` |
| AX writes and the frame no-op guard | `AxWriteTest` |
| Monitor fingerprints, including DisplayLink UUID matching | `MonitorFingerprintTest`, `MonitorIdentityTest` |
| Focus taken from macOS (#39) | `InvoluntaryFocusTest`, `FocusCacheTest` |
| Window rules, retries, declared workspaces (#40) | `WindowDetectionRetryTest`, `PersistentWorkspacesTest` |
| Workspace memory, away windows, native tabs | `WorkspaceMemoryTest`, `AwayWindowTest`, `NativeTabsTest` |
| The refresh scheduler and sessions | `RefreshSchedulerTest`, `ConcurrencyTest` |
| IPC: framing, real `AF_UNIX` sockets, exit codes | `CommonTests/SocketCodecTest`, `UnixSocketTest`, `CliConnectionTest`, `ServerProtocolTest` |
| CLI argument parsing and the command surface | `CommonTests/CmdArgsParsingTest`, `CliSurfaceTest`, `ShellCompletionGrammarTest` |
| Source rules: performance, branding, docs, design kit | `PerfInvariantsTest`, `BrandingTest`, `ReadmeExamplesTest`, `SiteInvariantsTest`, `DefaultConfigParityTest`, `DesignKitParityTest`, `ReleaseFeedTest` |

`dev-docs/architecture.md` names the test that pins each project rule.

## The seams

These seams let the suite run with no live window server:

- **The fake tree.** `TestApp` and `TestWindow` (`AppBundleTests/tree/`) stand in for `MacApp` and
  `MacWindow`. A test builds a real `Workspace` and `TilingContainer` tree from
  `TestWindow.new(...)`, runs real `Command` objects, and compares `layoutDescription`, a structural
  snapshot of the tree.
- **Layout geometry.** `LayoutTestWindow` records the frame that layout gives it instead of writing it
  through Accessibility. `LayoutRecursiveTest` runs `layoutWorkspace()` and checks each frame.
- **Monitors.** `testMonitors` (`model/Monitor.swift`) is a settable array. A test sets it to a two-
  or three-monitor arrangement, and `monitors`, `mainMonitor` and `sortedMonitors` read it.
  `fingerprint` is part of the `Monitor` protocol, so fingerprint resolution works on fake monitors.
- **Accessibility reads.** `AxUiElementMock` (`util/AxUiElementMock.swift`) has a real `AXUIElement`
  conformance and a dictionary conformance. `AxWindowKindTest` replays the captured AX trees in
  `axDumps/` through the window-kind heuristics. `AxWriteTest` uses `FakeAxElement` for writes.
- **AX errors.** `axErrorMeansDestroyed` is a pure function, so the meaning of each `AXError` is
  testable with no live element.
- **An app that does not answer.** `TestApp.shared.focusedWindowReadTimesOut` makes the focused-window
  read throw `NativeFocusUnknown`, as an app that misses the AX timeout does.
- **Source checks.** Some paths need a real `MacApp`. Tests such as `WorkspaceMemoryTest` and
  `WindowDetectionRetryTest` read the Swift source and check that a call is present or absent.
- **Shared state.** `setUpWorkspacesForTests` (`AppBundleTests/testUtil.swift`) resets the config,
  the workspaces and `TestApp.shared`. It does not reset `testMonitors`: a test that changes the
  monitors sets `testMonitors = [defaultTestMonitor]` again, as `MonitorIdentityTest` does.

## Add a test

1. Write the test at the lowest layer that shows the bug. Most window bugs reproduce on the fake tree.
2. Put it next to the tests for that area: `command/`, `config/`, `model/`, `tree/`, or the top of
   `AppBundleTests/` for cross-cutting rules. Put a test of code in `Sources/Common/` in
   `CommonTests/`.
3. Call `setUpWorkspacesForTests()` in `setUp` when the test touches the tree.
4. Reset in `tearDown` any global that the test sets and that `setUpWorkspacesForTests` does not
   reset, such as `testMonitors`. `DegradeInsteadOfDieTest`, `OpenSettingsTest` and `OwnWindowsAndSingleInstanceTest` do
   this. A flag such as `focusedWindowReadTimesOut` can also be reset with `defer`.
5. Cite symbols in comments and messages, not line numbers. A line number goes stale with the next
   edit.

## Refresh an AX fixture

Each file in `axDumps/` is the output of `aerospork debug-windows` for one window, plus the answer
that the heuristics must give.

1. Run a debug copy (`dev-docs/development.md`, "Run a debug copy").
2. Find the window ID with `./run-cli.sh list-windows --all`.
3. Run `./run-cli.sh debug-windows --window-id <id> > axDumps/<app>_<what>.json5`.
4. Add a first line comment that says how to make the window appear.
5. Check `Aero.AxUiElementWindowType` and `Aero.AxUiElementWindowType_isDialogHeuristic`. The command
   writes what the current code decides. If the code is wrong, change these two values to the correct
   answer. The test then fails until the code is fixed.
6. Run the Swift tests.

## What the suite cannot see

- **Live Accessibility.** No test drives a real `AXUIElement` or a running app. A test of the socket
  uses `socketpair`, not a running server.
- **Native-control pixels.** `ImageRenderer` forces each pane body to evaluate, but it cannot draw a
  grouped `Form` faithfully without a window. Review the Settings window by eye.
- **Monitor timing.** A virtual display sends one clean notification. A real DisplayLink dock sends a
  burst as it connects and settles, which only the hardware shows.
- **The first-run permission flow.**

## Live checks before a release

These checks use a debug copy and the CLI at `.debug/aerospork`. Two techniques do most of the work:

- `kill -STOP <pid>` and `kill -CONT <pid>` on a real app make each AX call to it miss the 1 s
  timeout (`.cannotComplete` on macOS 26 and 27).
- `list-workspaces --focused` and `list-windows --workspace N --count` give the result with no
  screenshot.

| Scenario | Action | Expected result |
|---|---|---|
| The focused window closes, and macOS focuses a window on another workspace (#39) | Windows of one app on workspaces 1 and 3. Press ⌘W on workspace 1. | `list-workspaces --focused` stays `1`. |
| An app is too busy to answer during a switch (#39) | `kill -STOP` the focused app, run `workspace 2`, wait 3 s, `kill -CONT` | The focused workspace stays `2` for 5 s. |
| Empty declared workspaces (#40) | `workspaces = "1-9"` and no `mod` | `list-workspaces --all` lists 1 to 9 at launch. |
| A rule applies with no click (#40) | `open -a "Visual Studio Code"` with a rule to workspace 3. Again with `kill -STOP` right after launch. | `list-windows --workspace 3 --app-bundle-id com.microsoft.VSCode --count` is 1 within 10 s. |
| Settings comes to the front (#40) | `open-settings` from Terminal, then `workspace 2` | `lsappinfo front` names the app. The window is still on screen. |
| One copy at a time | Run the binary of the bundle while it runs. | stderr says so. `pgrep -x AeroSporkApp` counts 1. |
| Workspace-change variables (#40) | `on-focused-workspace-changed = ['exec-and-forget echo "$AEROSPORK_PREV_WORKSPACE>$AEROSPORK_FOCUSED_WORKSPACE" >> /tmp/ws.log']` | Each switch logs both names. |

Then do these passes by hand:

- **DisplayLink.** With a real dock: pin a workspace by `uuid`, unplug and replug the dock, and check
  that the workspace comes back to the same panel.
- **Settings.** On the current macOS release, open each pane in light and dark appearance, at the
  ideal and the minimum window size, and use each control once.
