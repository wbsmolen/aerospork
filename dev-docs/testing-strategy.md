# aerospork Testing Strategy

A long-term plan for testing a macOS tiling window manager: what to test, how to
test the hard parts (real windows, multi-monitor, DisplayLink) without flaking,
and the tooling/skills to build and maintain to keep it honest over time.

> **Toolchain gotcha, read first.** This app is bound to the macOS SDK, not just a
> Swift version. The current macOS 27 development environment uses Xcode 27.0
> (Swift 6.4, `/Applications/Xcode.app`); a mismatched SDK can make `swift build` **hang silently**. Use the
> repository wrappers. If Swiftly is installed but the `.swift-version` toolchain is not, or the
> selected Xcode SDK is the intended toolchain, use the documented `xcrun` escape hatch:
> ```
> ./run-swift-test.sh                         # normal pinned-toolchain path
> AEROSPORK_SWIFT=xcrun ./run-swift-test.sh   # selected-Xcode path
> ```

---

## 1. Where we are today

The upstream AeroSpace test design is
headless and reusable:

- **Two headless test targets**, `AppBundleTests` and `CommonTests`. No count is quoted here on
  purpose: it rots, and six documents once disagreed about it. Run the suite to find out.
- **A fake-tree seam**: `AbstractApp`/`TestApp`, `Window`(class)/`TestWindow`,
  `Monitor`(protocol)/`MonitorImpl`. Tests build a *real* `Workspace`/`TilingContainer`
  tree out of `TestWindow.new(...)`, run *real* `Command` objects, and assert on
  `layoutDescription` (a structural snapshot). Tree mutation, focus order,
  normalization, split/join/move/resize are all exercised with no real windows.
- **An AX read seam**: `protocol AxUiElementMock` (`get`, `set`, `containingWindowId`,
  `isDestroyed`) with a real `AXUIElement` conformance and a `[String: Json]` fake. `AxWindowKindTest`
  replays the captured real-window AX dumps in `axDumps/` through the window-kind
  heuristics — genuinely headless classification regression tests. The `AXError` meanings that only a
  live element can produce are pinned through the pure `axErrorMeansDestroyed`, and an app that misses
  the AX timeout is simulated with `TestApp.focusedWindowReadTimesOut`.
- **A machine-readable control/observability surface**: a socket-speaking CLI
  (`.debug/aerospork`), `--json` on `list-windows`/`list-workspaces`/`list-monitors`,
  rich `--format` vars, and `trigger-binding`/`enable` for driving the live app.
- **`run-tests.sh`** already does build → `swift test` → CLI smoke → format/lint →
  generate → uncommitted-file check. `.github/workflows/ci.yml` runs exactly that on every push and pull
    request, and it is a required status check on `main`.

**The real gaps:**

1. **CI runs the suite but not the seams below.** `.github/workflows/ci.yml` runs `run-tests.sh` on
   `macos-latest`; what it cannot cover is anything needing a real window server (see §"CI
   strategy").
2. ~~**The fork's marquee new code is untested.**~~ The config writer now has no-op,
   round-trip, safety, backup, and fuzz coverage. Settings has source invariants, pane/view-model
   logic tests, complete empty/loaded render smoke, direct monitor-arrangement rendering, Raw TOML
   section/highlighting/diagnostic tests, and shared-chrome consistency checks. These are headless
   and deterministic; they do not replace a visual review of native AppKit/SwiftUI pixels. The
   remaining pure-code gaps include `Key` Carbon mapping, `SystemVolume`, and `ConfigFileWatcher`.
   Unix-socket framing and MonitorFingerprint UUID matching are covered by `SocketCodecTest`,
   `UnixSocketTest`, and `MonitorFingerprintTest`.
3. ~~**Layout geometry is unreachable in tests.**~~ Fixed. `LayoutTestWindow` overrides
   `setAxFrame`/`setAxTopLeftCorner` to record the rect instead of hitting `Window`'s base
   `die("Not implemented")`, and `LayoutRecursiveTest` runs `layoutWorkspace()` headlessly
   against `testMonitor`. Kept here because §4 describes the seam.
4. **No live-app integration test exists.** Every test is in-process. `ClientServerTest`
   only checks the JSON codec. It never binds a socket.
5. **No window-geometry in the queryable surface** (see §7): a product gap that limits
   what e2e can assert without the unstable `debug-windows` output.

---

## 2. Test pyramid & cadence

Push every bug **down** the pyramid when you fix it — most "window" bugs reproduce
headless via the mock tree. A bug that only shows with a live socket is integration;
only with real AX/monitors, e2e/manual.

| Layer | What | Runs where | Cadence | Catches |
|---|---|---|---|---|
| **Static** | swiftformat, swiftlint, `generate.sh --all` + uncommitted check, **toolchain preflight** | Any Mac / CI | every commit | style drift, stale generated files, wrong-SDK builds |
| **Unit (headless)** | tree/command/config/socket XCTest; config round-trip/fuzz; fingerprint/UUID; layout geometry; Settings logic/source/render smoke | Any Mac / CI | every commit / PR | layout math, command logic, config parse+write data loss, settings body traps and invariants, window-kind heuristics, IPC framing |
| **Integration (live socket/CLI)** | `run-e2e.sh`: launch debug app → `enable on` → issue commands → assert on `list-* --json` | self-hosted Mac (AX granted) | on merge + nightly | server/CLI wiring, framing over a real socket, refresh-session sync |
| **E2E (real windows + virtual displays)** | spawn stock-app windows, tile, assert live rects; multi-monitor via BetterDisplay | self-hosted / dev Mac | nightly / on-demand | real AX quirks, tiling real windows, monitor arrangement, workspace assignment |
| **Manual** | DisplayLink hardware (`uuid` fingerprint, flap timing), Settings visual/interaction review, first-run permission UX | one dev Mac w/ dongle | per release | hardware-only fingerprinting, native-control pixel/interaction regressions, permission flow |

**CI feasibility:** most meaningful tests are headless and belong in CI.
The AX/multi-monitor slice needs a real Mac; DisplayLink needs the physical dongle.
CI runs `run-tests.sh` on a hosted `macos-latest` runner; it does not need macOS 27 to verify the
macOS 13 deployment floor. OS-27-specific visual behavior stays in the manual release pass until a
matching hosted image exists.

---

## 3. Layer 1 — Unit test gaps (headless, do these first)

None of these need a running app. Priority = value × cheapness.

Coverage notes here rot: several rows first written as "zero coverage" have since been covered --
socket framing by `CommonTests/SocketCodecTest.swift` and `AppBundleTests/model/UnixSocketTest.swift`,
default-config parsing by `ConfigurationWriterSafetyTest.testShippedDefaultConfigIsEditable`. Check
before believing a row.

### P0 — cheap, high-value, no new seam

| Test | Target | Why |
|---|---|---|
| ✅ **default-config parses** | `ConfigV2Test.testShippedDefaultIsV2AndParses` plus `ConfigurationWriterSafetyTest.testShippedDefaultConfigIsEditable` | The shipped default and its structured-edit path are explicit guarantees. |
| ✅ **UnixSocket framing** | `SocketCodecTest` and `UnixSocketTest`: codec, loopback, EOF, and framing boundaries | Replaced BlueSocket; a framing bug would be silent IPC corruption. |
| ✅ **ConfigurationWriter round-trip + fuzz** | `ConfigTest`, `ConfigurationWriterSafetyTest`, and `ConfigSafetyWriterFuzzTest` | Managed changes parse, comments/order/unknown sections survive, no-op is byte-identical, and save paths are exercised over generated valid states. |
| ✅ **Settings structure and editor behavior** | `UIRenderSmokeTest`, `UISettingsTest`, `UIChromeConsistencyTest`, `UIKeysBindingsTest`, and `ConfigTest` | All panes evaluate in loaded/empty states; pane metadata, shared chrome, editor sections/highlighting, and exact source diagnostics are regression-tested without a live window server. |
| ✅ **Focus, detection and migration decisions** | `InvoluntaryFocusTest`, `WindowDetectionRetryTest`, `PersistentWorkspacesTest`, `MigrationTrapsTest`, `ExecEnvTest`, `OwnWindowsAndSingleInstanceTest`, `SettingsApplyTest` | The decisions behind #39 and #40 are pure functions pinned headlessly (`axErrorMeansDestroyed`, `shouldRestoreFocusAfterDeath`, `runningCopyToYieldTo`, `execAndForgetProcess`, `shieldedFromCancellation`); a throwing `TestApp.getFocusedWindow` simulates an app that misses the AX timeout. Paths that need a real `MacApp` are pinned by source checks. |

### P1 — cheap, protects the DisplayLink/hotkey revamp

| Test | Target | Why |
|---|---|---|
| ✅ **MonitorFingerprint.matches(patternData:).** *done, `MonitorFingerprintTest`* | UUID match/mismatch (case-insensitive), two identical DisplayLink panels disambiguated by UUID, name exact/substring, vendor/model/serial, width/height | UUID-first matching is why the DisplayLink work exists; pure `struct→Bool`. `model/MonitorFingerprint.swift:107-141` |
| ✅ **Fingerprint config parse.** *done, `ConfigTest.testParseWorkspaceToMonitorFingerprintUuid`* | `parseConfig` of `[workspace-to-monitor-force-assignment]` with `fingerprint = { uuid = ... }`, hex `vendor='0x1234'`, and unknown-key rejection | The new fingerprint path was unasserted (`testParseWorkspaceToMonitorAssignment` covered only errors). `parseWorkspaceToMonitorAssignment.swift:49-118` |
| **Key carbon/round-trip** | over `Key.allCases`: `toString()` reparses; spot-check `carbonKeyCode` for letters/digits/arrows | The soffes/HotKey → Carbon replacement is untested; a wrong keycode = a silently dead hotkey. `config/Key.swift` |

### P2/P3 — needs a seam or is low-ROI

- **Layout geometry** has headless coverage through `LayoutTestWindow` and
  `LayoutRecursiveTest`; expand canonical cases as layout behavior changes.
- **ConfigurationViewModel** has focused coverage in the UI and config test files. SwiftUI scene
  lifecycle and native-control pixels remain outside the headless seam.
- **SystemVolume** (CoreAudio HW) and **ConfigFileWatcher** (DispatchSource timing) — Hard,
  integration-style, low ROI; leave to the integration tier or skip.

---

## 4. Two small seams that make the hard layers testable

These are the two source changes with the widest effect. A few lines each, and they open up
whole categories of headless tests.

### Seam A — layout geometry (≈1–3 lines)

**Built.** `layoutRecursive` records each node's computed rect on the node *before* calling
`window.setAxFrame`. On a bare `TestWindow` that write hit `Window`'s base
`die("Not implemented")` and aborted the run.

**Change:** override `setAxFrame` (and `setAxTopLeftCorner`/`getAxTopLeftCorner`/`getAxSize`
for the floating path) in `TestWindow` to *record* the rect instead of dying (base
`Window.setAxFrame` at `tree/Window.swift:53`).

**Unlocks:** call `workspace.layoutWorkspace()` on a mock tree and assert every node's
computed rect against expected pixels — tiles/gaps, accordion padding, fullscreen,
multi-container nesting — all headless. Feeds the **layout golden-rect** tests (§10.4).
The production no-op AX guard (`MacApp.setFrame`, reads a live element) stays Hard;
that's fine, it's a thin wrapper the mock doesn't need.

### Seam B — injectable monitors (small)

**Built.** `monitors`/`mainMonitor`/`sortedMonitors` used to branch on `isUnitTest` and
return a single hardcoded `testMonitor`, so a 2- or 3-monitor arrangement could not be
constructed. `Monitor.testMonitors` is now a settable array and `MonitorIdentityTest` and
`LayoutRecursiveTest` both inject arrangements through it.

**Change:** replace the `isUnitTest` branch with a settable `@MainActor var
testMonitorsOverride: [Monitor]?` (nil ⇒ real NSScreen path). Add a `fingerprint`
member to the `Monitor` protocol (default nil) so `resolveMonitor`'s `.fingerprint` path
(`MonitorDescriptionEx.swift:12-18`) resolves against fakes.

**Unlocks:** headless tests of workspace-to-monitor assignment, `move-node-to-monitor`,
`move-workspace-to-monitor`, rearrange-on-config-change, and **the DisplayLink UUID
matching path** — construct two identical fake monitors distinguished only by UUID and
assert each `uuid=` assignment resolves to the right one.

### Hygiene — reset leaking globals

`setUpWorkspacesForTests` (`testUtil.swift:16-40`) never clears
`currentlyManipulatedWithMouseWindowId` (read by layout) or `appForTests`. There's no
`tearDown` anywhere. Add two resets so layout/mouse/monitor tests don't bleed across cases.

---

## 5. Layer 3 — Integration harness (`run-e2e.sh`)

Drives the *live* app over the socket. Lives outside `run-tests.sh` (self-hosted/nightly
tier). Bash is right — it's process orchestration, not logic.

**Protocol facts** (for anyone hand-rolling; easiest is to just shell out to `.debug/aerospork`):
- Socket: **`/tmp/com.wbs.aerospork.debug-<user>.sock`** for debug builds (`aeroSporkAppId`
  is `com.wbs.aerospork.debug` under `#if DEBUG`). Not `/tmp/aerospork-…`.
- Framing: 4-byte big-endian length + JSON. `ClientRequest {args, stdin, command?}` →
  `ServerAnswer {exitCode, stdout, stderr, serverVersionAndHash}` (`Common/model/clientServer.swift`).
- **Server gate:** a disabled server rejects everything except `enable` — harness must
  `aerospork enable on` first (`server.swift:58-65`).
- **`exec-and-forget` is rejected over the socket.**
- Useful drivers: `trigger-binding --mode <m> <binding>` (simulate a keybinding without
  synthesizing key events), `reload-config`, `config`.

**Harness flow:**
```
build-debug-app.sh                       # cert-signed when available; ad-hoc only as a fallback
require-ax.sh                            # fail loud if Accessibility not granted (§10.6)
open .debug/AeroSpork-Debug.app            # launch the menu-bar agent
wait for /tmp/com.wbs.aerospork.debug-$USER.sock
aerospork enable on
open -na TextEdit ; open -na TextEdit    # spawn known windows
ids=$(aerospork list-windows --all --app-bundle-id com.apple.TextEdit --json)
aerospork focus / move / layout / split ...
assert aerospork list-windows --workspace focused --json  == expected   # via jq
teardown: aerospork enable off ; close spawned apps
```
Use a locked fixture `~/.aerospork-debug.toml` for determinism. Discover window ids from
`list-windows --json`; drive/assert by `window-id`. Deterministic placement of a spawned
window is best done with an `on-window-detected` config rule.

**Until this harness exists: the live checklist.** Each check for the #39/#40 fixes is a one-liner
against a debug build (`AEROSPORK_SWIFT=xcrun ./build-debug-app.sh`, CLI `.debug/aerospork`). Two
techniques do most of the work with no new files: `kill -STOP <pid>` / `kill -CONT <pid>` on a real app
makes every AX call to it miss the 1s messaging timeout (`.cannotComplete` on macOS 26 and 27),
and polling `list-workspaces --focused` or `list-windows --workspace N --count` asserts the outcome
without screenshots.

| Scenario | Drive | Assert |
|---|---|---|
| Focused window closes; macOS keys one on another workspace (#39) | windows of one app on ws1 and ws3, ⌘W on ws1 | `list-workspaces --focused` stays `1` |
| App too busy to answer during a switch (#39) | `kill -STOP` the focused app, `workspace 2`, wait 3s, `kill -CONT` | stays `2` for 5s |
| Empty declared workspaces (#40) | `workspaces = "1-9"` and no `mod` | `list-workspaces --all` lists 1-9 at launch |
| A rule applies without a click (#40) | `open -a "Visual Studio Code"` with a rule to ws3; again with `kill -STOP` right after launch | `list-windows --workspace 3 --app-bundle-id com.microsoft.VSCode --count` is 1 within 10s |
| Settings comes to the front (#40) | `open-settings` from Terminal, then `workspace 2` | `lsappinfo front` names the app; the window is still on screen |
| One copy at a time | exec the bundle's binary while it runs | stderr says so; `pgrep -x AeroSporkApp` counts 1 |
| Workspace-change env (#40) | `on-focused-workspace-changed = ['exec-and-forget echo "$AEROSPORK_PREV_WORKSPACE>$AEROSPORK_FOCUSED_WORKSPACE" >> /tmp/ws.log']` | both names logged per switch |

---

## 6. Layer 4/5 — Multi-monitor, DisplayLink, GUI

**Multi-monitor (scriptable):** BetterDisplay 2 ships `betterdisplaycli` to create/remove
virtual displays and toggle connect state — fully scriptable. Wrap it in
`script/e2e/with-virtual-display.sh`. After create/destroy, sleep >250ms (the debounce)
then assert via `list-monitors --json` and `list-workspaces --monitor N --json`. This
exercises monitor count/arrangement changes, `autoMoveWorkspacesToAssignedMonitors`, and
the signature-change gating in `GlobalObserver.onMonitorConfigurationChanged`.

**DisplayLink (honest limits):**
- The **debounce/rebalance plumbing** is testable with virtual displays (it only depends
  on `didChangeScreenParameters`).
- The **flap/settle burst timing** the 250ms debounce exists to absorb needs a **real
  DisplayLink USB dock** — virtual displays fire one clean notification, not a burst.
- The **`displayUUID` match on a real panel** (stable nil vendor/model/serial + persistent
  UUID across reconnect) is hardware-only. Virtual displays *approximate* it (they have a
  UUID) so the branch can be smoke-tested, but the UUID is runtime-assigned: a test must
  read it back from `monitor-fingerprint` first, then verify a `uuid=` assignment.
- Gate hardware tests behind `AEROSPORK_DISPLAYLINK=1` + a preflight that detects the panel;
  otherwise skip with a logged reason. Keep a short manual DisplayLink checklist per release.

**GUI:** settings persistence is covered by ConfigurationWriter tests; pane metadata and pure editor
logic by `UISettingsTest`; shared-component rules by `UIChromeConsistencyTest`; and every pane body,
including empty states and asymmetric monitor geometry, by `UIRenderSmokeTest`. Those tests catch
body traps and structural regressions but cannot prove the pixels of a grouped Form in a real host
window. Review the checked v3 light/dark ideal/compact mock matrix and run a visual/interaction pass
on the current macOS release before shipping. SwiftUI UI automation remains low-value and flaky here.

---

## 7. Product changes that make e2e assertions cleaner

Small, also useful to end users, and they remove the biggest e2e friction:

1. **Add `window-x` / `window-y` / `window-width` / `window-height` format vars** to
   `FormatVar.WindowFormatVar` (`format.swift:77-81`). Today `list-windows` exposes only
   id/fullscreen/title, so per-window tile geometry is **not** queryable — e2e must fall
   back to `debug-windows --window-id` (explicitly "not stable API", not JSON, line-prefixed).
   This one addition makes live rect assertions clean.
2. **Add a `monitor-uuid` format var.** The DisplayLink UUID is currently only reachable
   embedded in the `monitor-fingerprint` string; a test that builds a `uuid=` assignment
   has to parse it out.

Both are optional but recommended. They convert "parse an unstable debug dump" into
"assert a JSON field."

---

## 8. Toolchain selection & preflight (the most-reused skill)

The trap: `script/setup.sh`'s `swift()` wrapper runs `swiftly run swift` and
`.swift-version` pins `6.4`; on macOS 27 that toolchain is broken and a mismatched SDK
makes `swift build` **hang with no error**.

**Recommendations:**
1. **Pin the (OS, Xcode) pair, not just the Swift version.** a WM is bound to the SDK.
   Resolve `DEVELOPER_DIR` from: env override → known install path → `xcode-select -p`.
2. **Invert `setup.sh`:** prefer the pinned Xcode; use swiftly only as a fallback (today
   swiftly-first is exactly what breaks).
3. **Add a preflight (`script/preflight-toolchain.sh`)** that checks the SDK/Swift version
   *before* building and hard-fails in ~1s with a readable message
   (`"wrong SDK — expected Xcode 27 b2; run export DEVELOPER_DIR=…"`) instead of hanging.
   **Wire it into every build/test/e2e script.** This is the highest-reuse maintenance skill.
4. **CI:** set `DEVELOPER_DIR` in the workflow `env:` (cleaner than `sudo xcode-select`).

---

## 9. CI

- **Done.** `.github/workflows/ci.yml` runs `run-tests.sh` on `macos-latest`, a
  GitHub-hosted runner, with `AEROSPORK_SWIFT: xcrun`. The self-hosted beta runner this
  section originally called for turned out to be unnecessary.
- Keep the toolchain pin in one place, so moving between images stays a one-value change.
- Still outstanding: the integration tier (`run-e2e.sh`) has nowhere to run. It needs
  Accessibility permission, which a hosted runner cannot grant, so it would want a
  self-hosted box where the grant persists.

---

## 10. Tooling / skills to build (catalog)

Ordered by effect per unit of work. Preference throughout: reuse `AxUiElementMock`, `run-tests.sh`, the XCTest
harness, and the existing scripts (`build-debug-app.sh`,
`reset-accessibility-permission-for-debug.sh`); add the minimum.

1. **Toolchain preflight.** bash, `script/preflight-toolchain.sh`. §8. *Build first.*
2. ~~**CI workflow.**~~ Done: `.github/workflows/ci.yml` runs `run-tests.sh` on a hosted runner. §9.
3. **ConfigurationWriter round-trip + fuzz.** XCTest,
   Config-writer coverage landed instead across `ConfigTest.swift`,
   `ConfigurationWriterSafetyTest.swift` and `ConfigSafetyWriterFuzzTest.swift`. *Done.*
4. **Layout golden-rects.** The seam and direct geometry assertions exist in
   `LayoutRecursiveTest`; extend them with canonical nested and two-monitor cases as needed. A
   checked JSON fixture is optional—the important property is zero AX and exact computed rects.
5. **`run-e2e.sh` + `script/e2e/` helpers.** bash. §5. Integration tier.
6. **`require-ax.sh`.** bash, `script/e2e/`. Check `AXIsProcessTrusted` for the debug
   bundle; if not granted, print exact steps / open the pane and exit non-zero so e2e fails
   loud instead of hanging on a permission dialog. Complements the existing reset script.
   (You cannot auto-grant without MDM or SIP-off; on a dedicated self-hosted mini, grant
   once. It persists. Document that one-time box setup.)
7. **`with-virtual-display.sh`.** bash wrapper over `betterdisplaycli`. §6. Multi-monitor.
8. **`capture-axdump.sh`.** bash, `script/`. Dump a focused window's AX tree to the
   `Aero.*` JSON5 schema `AxWindowKindTest` expects, so refreshing a fixture is
   `capture-axdump.sh chrome > axDumps/chrome.json5`. The `axDumps/` corpus rots as apps
   update; add a short "how to add/refresh a fixture" doc.
9. **Window-fixture spawner.** *defer.* Start with scripted stock apps (TextEdit/Terminal)
   matched by title in `list-windows --json`. Only if that flakes, build a ~50-line
   `TestWindowSpawner` helper that opens N titled `NSWindow`s from argv. YAGNI until stock
   apps prove flaky.

---

## 11. Build-first roadmap

**Phase 1 — headless value, no new seams (a day or two):**
1. Toolchain preflight (`script/preflight-toolchain.sh`), wired into build/test scripts.
2. ~~`.github/workflows/ci.yml`~~ done, on a hosted runner.
3. ✅ P0 unit tests: default-config parsing, UnixSocket framing, and ConfigurationWriter
   round-trip/fuzz (done; `test-settings-ui.sh` retired into XCTest).
4. P1 unit tests: ✅ MonitorFingerprint UUID matching + fingerprint config parse (done);
   remaining — Key carbon mapping.

**Phase 2, geometry and monitors (small seams):**
5. ✅ Seam A (`TestWindow.setAxFrame` records rect) + layout geometry tests.
6. ✅ Seam B (injectable monitors + `Monitor.fingerprint`) + multi-monitor / UUID-resolution
   unit tests and global test-state reset.

**Phase 3 — live integration:**
7. `require-ax.sh` + `run-e2e.sh` (launch → enable → spawn → command → assert `--json`).
8. (Optional product) add `window-x/y/width/height` + `monitor-uuid` format vars for clean
   live rect assertions.
9. `with-virtual-display.sh` for scripted multi-monitor e2e.

**Phase 4 — maintenance skills & the tail:**
10. `capture-axdump.sh` + fixture-refresh doc.
11. Manual DisplayLink checklist (per release); Settings mock-matrix and live-interaction review.
12. Window-fixture spawner app — only if stock apps flake.

**Highest-value remaining work:** toolchain preflight, Key/Carbon round-trip coverage, then a live
socket/Accessibility integration harness. The writer and Settings regressions no longer depend on a
human-only checklist.

---

## 12. Key references

- Fake-tree seam: `Sources/AppBundleTests/tree/{TestApp,TestWindow,TilingContainer}.swift`,
  `testUtil.swift`, `assert.swift`.
- AX read seam: `Sources/AppBundle/util/AxUiElementMock.swift`, `accessibility.swift`,
  `AxUiElementMockEx.swift`; fixtures in `axDumps/` driven by `AxWindowKindTest.swift`.
- Layout seam point: `layout/layoutRecursive.swift:37-39`, `tree/Window.swift:53`.
- Monitor seam point: `model/Monitor.swift:101-115`, `MonitorDescriptionEx.swift:12-18`.
- Control channel: `server.swift`, `Cli/_main.swift`, `Common/util/UnixSocket.swift`,
  `Common/model/clientServer.swift`; commands in `cmdArgsManifest.swift`; output vars in
  `format.swift` / `formatToJson.swift`.
- Scripts: `run-tests.sh`, `script/setup.sh`, `build-debug-app.sh`,
  `script/reset-accessibility-permission-for-debug.sh`.
- The `isUnitTest` master switch: `Common/util/commonUtil.swift:134`.
