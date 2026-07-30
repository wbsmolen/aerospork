# aerospork Testing Strategy

A long-term plan for testing a macOS tiling window manager: what to test, how to
test the hard parts (real windows, multi-monitor, DisplayLink) without flaking,
and the tooling/skills to build and maintain to keep it honest over time.

> **Toolchain gotcha, read first.** This app is bound to the macOS SDK, not just a
> Swift version. On macOS 27 the only working toolchain is Xcode 27 beta 2 (Swift
> 6.4); a mismatched SDK makes `swift build` **hang silently**. Every build/test
> script must preflight the toolchain (see §8). Build/test with:
> ```
> DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test
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
- **An AX read seam**: `protocol AxUiElementMock` (`get` + `containingWindowId`) with a
  real `AXUIElement` conformance and a `[String: Json]` fake. `AxWindowKindTest` replays
  the captured real-window AX dumps in `axDumps/` through the window-kind
  heuristics — genuinely headless classification regression tests.
- **A machine-readable control/observability surface**: a socket-speaking CLI
  (`.debug/aerospork`), `--json` on `list-windows`/`list-workspaces`/`list-monitors`,
  rich `--format` vars, and `trigger-binding`/`enable` for driving the live app.
- **`run-tests.sh`** already does build → `swift test` → CLI smoke → format/lint →
  generate → uncommitted-file check. **It is a CI job body with no CI calling it.**

**The real gaps:**

1. **CI runs the suite but not the seams below.** `.github/workflows/ci.yml` runs `run-tests.sh` on
   `macos-latest`; what it cannot cover is anything needing a real window server (see §"CI
   strategy").
2. **The fork's marquee new code is untested.** `ConfigurationWriter` (line-surgery TOML
   editing) and the settings GUI are guarded by automated writer tests in `ConfigTest.swift` (they replaced `test-settings-ui.sh`, which was a *manual,
   interactive* checklist whose Test 1 is "did keybindings survive a Save?" i.e. a real
   data-loss bug now guarded by a human pressing Enter. Same for the other revamp code:
   `Key` Carbon mapping, `SystemVolume` and `ConfigFileWatcher` still have no tests.
   `UnixSocket` framing and `MonitorFingerprint` UUID matching since gained them
   (`UnixSocketTest`, `MonitorFingerprintTest`).
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
| **Unit (headless)** | existing tree/command/config/socket XCTest; **+ new** config round-trip/fuzz, socket framing, fingerprint/UUID, Key mapping; **+ layout golden-rects** (after §4 seam) | Any Mac / CI | every commit / PR | layout math, command logic, config parse+write data loss, window-kind heuristics, IPC framing |
| **Integration (live socket/CLI)** | `run-e2e.sh`: launch debug app → `enable on` → issue commands → assert on `list-* --json` | self-hosted Mac (AX granted) | on merge + nightly | server/CLI wiring, framing over a real socket, refresh-session sync |
| **E2E (real windows + virtual displays)** | spawn stock-app windows, tile, assert live rects; multi-monitor via BetterDisplay | self-hosted / dev Mac | nightly / on-demand | real AX quirks, tiling real windows, monitor arrangement, workspace assignment |
| **Manual** | DisplayLink hardware (`uuid` fingerprint, flap timing), SwiftUI settings smoke, first-run permission UX | one dev Mac w/ dongle | per release | hardware-only fingerprinting, GUI regressions, permission flow |

**CI feasibility:** most meaningful tests are headless and belong in CI.
The AX/multi-monitor slice needs a real Mac; DisplayLink needs the physical dongle.
GitHub-*hosted* runners can't even build this until a stable macOS-27 + Xcode-27 image
ships. CI now runs `run-tests.sh` on a hosted `macos-latest` runner.

---

## 3. Layer 1 — Unit test gaps (headless, do these first)

All items below have **zero** current coverage (grep-confirmed) unless noted. None need
a running app. Priority = value × cheapness.

### P0 — cheap, high-value, no new seam

| Test | Target | Why |
|---|---|---|
| **default-config parses** | `parseConfig(String(contentsOf: defaultConfigUrl), isUserConfig:false)` → `assertSucc` + spot-check values | Today it's only *implicitly* exercised (setUp `die()`s if it breaks). The shipped default must always parse; make it an explicit named guarantee. `config/Config.swift:23-38` |
| **UnixSocket framing** | `sendMessage`/`recvMessage` loopback: empty / 1-byte / >64KiB payloads; `recvMessage` → nil on peer close; partial-read/EINTR via `socketpair(2)` into `UnixSocketConnection(fd:)` | Replaced BlueSocket; a framing bug = silent IPC corruption. `Common/util/UnixSocket.swift:40,60,85,93` |
| **ConfigurationWriter round-trip + fuzz** | Feed base TOML (incl. `default-config.toml` and the keybinding/gaps cases from `test-settings-ui.sh`) through `write(from:)`, re-`parseConfig`; assert (a) managed keys changed, (b) comments/order/unknown sections survive, (c) `write→parse→write` is a fixed point. Add a small property fuzzer over valid VM states. | The marquee new code, a proven data-loss class, currently guarded by a human. **Done:** `test-settings-ui.sh` is deleted; its Tests 1–2 now live in `ConfigTest.swift` as the byte-identical no-op invariant plus per-bug regressions. `config/ConfigurationWriter.swift:57-194` |

### P1 — cheap, protects the DisplayLink/hotkey revamp

| Test | Target | Why |
|---|---|---|
| ✅ **MonitorFingerprint.matches(patternData:).** *done, `MonitorFingerprintTest`* | UUID match/mismatch (case-insensitive), two identical DisplayLink panels disambiguated by UUID, name exact/substring, vendor/model/serial, width/height | UUID-first matching is why the DisplayLink work exists; pure `struct→Bool`. `model/MonitorFingerprint.swift:107-141` |
| ✅ **Fingerprint config parse.** *done, `ConfigTest.testParseWorkspaceToMonitorFingerprintUuid`* | `parseConfig` of `[workspace-to-monitor-force-assignment]` with `fingerprint = { uuid = ... }`, hex `vendor='0x1234'`, and unknown-key rejection | The new fingerprint path was unasserted (`testParseWorkspaceToMonitorAssignment` covered only errors). `parseWorkspaceToMonitorAssignment.swift:49-118` |
| **Key carbon/round-trip** | over `Key.allCases`: `toString()` reparses; spot-check `carbonKeyCode` for letters/digits/arrows | The soffes/HotKey → Carbon replacement is untested; a wrong keycode = a silently dead hotkey. `config/Key.swift` |

### P2/P3 — needs a seam or is low-ROI

- **Layout geometry** (gap math, accordion padding, fullscreen rect) — blocked on the §4
  seam; then high-value golden-rect tests.
- **ConfigurationViewModel.** separable logic testable; SwiftUI lifecycle is not.
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
build-debug-app.sh                       # ad-hoc-signed .app so AX/didLaunch behave
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

**GUI:** the settings window's *logic* (round-trip) is covered headlessly by the
ConfigurationWriter tests (§3). Visual/interaction smoke stays a per-release manual pass;
don't invest in SwiftUI UI-automation — low ROI, high flake.

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
   `Sources/AppBundleTests/config/ConfigurationWriterTest.swift`. §3 P0. *Build first.*
4. **Layout golden-rects.** extend XCTest under `Sources/AppBundleTests/layout/`, golden
   JSON in `.../golden/`. Needs Seam A (§4). Snapshot computed rects for canonical trees
   (h/v split, accordion, nested, 2-monitor); a diff is a layout regression, zero AX.
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
3. P0 unit tests: default-config parses, UnixSocket framing, **ConfigurationWriter
   round-trip + fuzz** (done: `test-settings-ui.sh` retired into `ConfigTest.swift`).
4. P1 unit tests: ✅ MonitorFingerprint UUID matching + fingerprint config parse (done);
   remaining — Key carbon mapping.

**Phase 2, geometry and monitors (small seams):**
5. Seam A (`TestWindow.setAxFrame` records rect) + layout golden-rect tests.
6. Seam B (injectable monitors + `Monitor.fingerprint`) + multi-monitor / UUID-resolution
   unit tests. Reset the two leaking globals in setUp.

**Phase 3 — live integration:**
7. `require-ax.sh` + `run-e2e.sh` (launch → enable → spawn → command → assert `--json`).
8. (Optional product) add `window-x/y/width/height` + `monitor-uuid` format vars for clean
   live rect assertions.
9. `with-virtual-display.sh` for scripted multi-monitor e2e.

**Phase 4 — maintenance skills & the tail:**
10. `capture-axdump.sh` + fixture-refresh doc.
11. Manual DisplayLink checklist (per release); GUI smoke checklist.
12. Window-fixture spawner app — only if stock apps flake.

**If you do nothing else:** Phase 1 items 1–3. CI running the tests that
already exist, a preflight that kills the silent hang, and automated coverage of the config
writer that a human currently babysits.

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
