# Performance

## Status

**Only the first group below has a controlled measurement behind it.** The rest are defensible on
first principles. They remove work that provably happens, but their end-to-end effect has *not*
been demonstrated, because the benchmark available was too noisy to resolve it. See
"Why the benchmark is unreliable".

Do not cite these as measured wins without re-measuring under Instruments.

## Measured

Test-suite wall clock, same tests, back-to-back on the same machine:

| build | duration (median of 5) |
|---|---|
| old `debugLog` | 0.255 s |
| new `debugLog`, gate OFF | 0.155 s |
| new `debugLog`, `AEROSPORK_DEBUG_LOG=1` (fully logging) | 0.156 s |

**Read the third row before quoting the first two.** It is what makes the result interpretable: the
win is ~99% from deleting the per-call `DateFormatter.localizedString` and `URL(fileURLWithPath:)`,
and ~0% from the env gate or the `@autoclosure`. Eager evaluation was not the bulk of the cost, which
is the opposite of the obvious guess.

**This is also not a user-facing number.** The suite makes ~10,000 `debugLog` calls/sec. The real
refresh path makes 2 per refresh plus 4–5 per `runSession` — roughly 40/sec at the debounce ceiling,
about **0.28% of one core**. Presenting a harness running 250× the app's real rate as "measured
performance" would be overstatement.

The genuinely user-visible win here is a different one: `printStderr` used to be
unconditional, so **every** `aerospork` CLI invocation printed 6+ `[DEBUG]` lines to stderr. That
broke anyone scripting the CLI.

## Changes

### Removed unconditional work

1. **`tree/Workspace.swift`.** two unconditional `print("[DEBUG]…")` inside `forceAssignedMonitor`,
   which is the first thing `workspaceMonitor` checks. `workspaceMonitor` is called from layout,
   focus, tray updates and `hideInCorner`, so for any user with
   `workspace-to-monitor-force-assignment` configured this was an unbuffered stdout write many
   times per refresh. Deleted.

2. **`Common/util/commonUtil.swift`.** `debugLog` now takes `@autoclosure`, uses `#fileID`
   (no `URL` parsing), drops the per-call `DateFormatter` (os_log timestamps its own records), and
   is gated on `AEROSPORK_DEBUG_LOG`.

   The gate is a **runtime env var, not `#if DEBUG`**, deliberately: the shipped `.app` is itself a
   debug build, so a compile-time gate would have left this on for every user.

3. **`ui/TrayMenuModel.swift`.** `trayText`, `workspaces` and `trayItems` are now assigned only
   when the value actually changed (`setIfChanged`). Each `@Published` write invalidates
   `MenuBarExtra`, and `MenuBarLabel` then runs a full SwiftUI→CGImage `ImageRenderer` pass on the
   main thread. `updateTrayText()` runs every refresh, so this was a rasterization at up to 20 Hz
   producing a byte-identical image nearly every time.

### Not individually measured

4. **`normalizeLayoutReason.swift`.** `isMacosFullscreen` / `isMacosMinimized` are prefetched for
   all windows via `withThrowingTaskGroup` instead of two sequential `await`s inside the mutation
   loop. Was 2 serialized MainActor↔app-thread round trips per window per refresh, across every
   window of every workspace. Same fan-out pattern as `MacApp.refreshAllAndGetAliveWindowIds`.

   **A regression this introduced, now fixed.** The prefetched `states` array was captured *before*
   any mutation, and the mutation loop `await`s inside `relayoutWindow`, releasing the main actor —
   so a window un-minimized mid-loop was still acted on from the stale snapshot (e.g. bound into
   the minimized container). The fix keeps the parallel prefetch but adds a cheap `willMutate`
   precheck and **re-reads** AX state only for the few windows that are actually about to move, so
   the steady state pays no extra round trips. Per-workspace and per-window cancellation checks are
   restored too: the `.standard` branch had become fully synchronous, so a cancelled refresh was
   mutating the whole tree instead of stopping. Index/order pairing was verified correct throughout.

5. **`tree/MacApp.getOrRegister`.** replaced a `while true` / `Task.sleep(100ms)` poll with
   continuation-based waiters. The old loop published into `allAppsMap` from a hopped
   `Task { @MainActor }`, so the first re-poll always lost the race: registering one app cost 100 ms
   minimum, 200 ms typically.

   Note: session-duration histograms showed only 4 of 147 sessions in the 100/200 ms bands, so this
   was **not** the dominant cost, despite an apparent `200.5 ms` cluster.

   **Three caveats, all closed:**
   - **Negative cache added.** `bulkSubscribe` returning `[]` used to leave nothing in `allAppsMap`,
     so an unsubscribable app cost a fresh `Thread` + `AXObserverCreate` on *every* refresh forever.
     `failedPids` now backs off 1 s → ×2 → 30 s (≈1 probe/30 s instead of ≈20/s). Keyed with
     `launchDate` so pid reuse can't hide a brand-new process behind a stale backoff.
   - **Cancellation fixed.** Waiters are keyed by id and wrapped in `withTaskCancellationHandler`,
     so a cancelled refresh unparks immediately instead of holding its whole task-group child set
     until the AX timeout. `AXUIElementSetMessagingTimeout(1.0)` also caps a wedged app at 1 s
     rather than the 6 s default (120 debounce windows).
   - **The fragile invariant is gone, not documented.** Correctness used to depend on there being
     *zero* suspension points between `wipPids.insert(pid)` and the continuation append: a single
     `await Task.yield()` there deadlocked the main actor. It is now non-load-bearing: the
     continuation body re-checks `!wipPids.contains(pid) || Task.isCancelled` and resumes itself.
     `wipPids` is cleared in the same synchronous drain that wakes waiters, so "not in flight"
     means exactly "already published": the state a suspension point would have produced.

6. **`tree/MacApp`.** the frame no-op guard was extracted to `isFrameSatisfied` and hoisted
   *above* `disableAnimations`, which costs a read plus two writes on the app element. Previously a
   fully skipped frame still paid that. The guard was also extended to `setAxTopLeftCorner`, which
   `hideInCorner` calls for every window of every invisible workspace on every refresh.

7. **`layout/refresh.swift`.** `aliveWindowIds` is a `Set`, not an `Array`. Was O(W²).

8. **`util/RefreshDebouncer.swift`.** a 250 ms max-wait ceiling was added and then **REVERTED**.

   The intent was to stop a sustained event stream from starving the refresh. What it actually did,
   measured by porting the logic into a harness and driving it:

   | scenario | refreshes started (3 s) | refreshes **completed** |
   |---|---|---|
   | events @10 ms, refresh 5 ms | 12 | 12 |
   | events @10 ms, refresh 400 ms | 12 | **0** |
   | events @5 ms, refresh 300 ms | 12 | **1** |

   Every ceiling fire hit the unconditional `activeRefreshTask?.cancel()` and killed a refresh that
   was still running, which the next ceiling fire then repeated. The plain debounce does no work
   during the burst and then produces exactly one correct layout; the ceiling produced twelve
   refreshes' worth of AX traffic and no layout, with a risk of partial layout left behind from
   `setFrame` writes already issued. p90 refresh here is ~380 ms, so this was reachable in practice,
   not theoretical.

   Do not re-add without (a) fixing the unconditional cancel so an overdue fire never kills a live
   refresh, and (b) a measurement showing starvation actually occurs.

## Why the benchmark is unreliable

The obvious benchmark — drive N workspace switches through the CLI and time them — does not work
here. Measured medians of session duration for **identical code**, same workload (24 switches):

| run | median | p90 |
|---|---|---|
| pre-change, run 1 | 143.3 ms | 383.6 ms |
| pre-change, run 2 | 11.7 ms | 43.1 ms |
| post-change | 21.5 ms | 46.5 ms |

Run-to-run variance on unchanged code is ~12×, far larger than any effect being measured. Causes:

- **Cold app registration dominates the first run after a restart.** Every app must get a thread and
  AX subscriptions; that cost lands entirely in the first few sessions and then disappears.
- AX round-trip latency depends on whether the target app is busy. One slow app serializes a refresh.
- Ambient system load (browsers, other tooling) moves the numbers more than the code does.
- CLI process spawn is ~27.6 ms of every measurement, independent of server work.

**Consequence:** a single before/after pair is worthless here. Anything claiming a win needs either
many alternating trials from a warm process, or Instruments.

## How to measure properly

`OSSignposter` intervals already exist and are the right tool, no new instrumentation needed:

- `util/appBundleUtil.swift`: the signposter, `category: .pointsOfInterest`
- `layout/refresh.swift` — around `runRefreshSessionBlocking` and `runSession`
- `util/accessibility.swift` — around **every** AX `get`, `set` and `containingWindowId`, tagged
  with `axTaskLocalAppThreadToken`

Attach Instruments to the Points of Interest track for per-AX-attribute timing attributed by app
thread. Always warm the process first (switch workspaces a few times) so app registration is not
counted.

For a coarse view without Instruments, run the binary directly with logging enabled and read the
durations the code already computes:

```bash
AEROSPORK_DEBUG_LOG=1 /Applications/AeroSpork.app/Contents/MacOS/AeroSpork 2>&1 \
  | grep -oE 'SESSION: Completed in [0-9.]+ms'
```

## Known remaining items

- **`model/Monitor.swift`.** `monitors`/`sortedMonitors` rebuild from `NSScreen.screens` on every
  access, from around 30 call sites. `updateTrayText` hoists it into a local and reads that, so the
  hot path costs one rebuild per refresh rather than one per use. **Attempted and deliberately
  reverted.**
  A `@MainActor` cache cascades isolation into `MonitorEx.monitorId`, `MonitorResolution` and their
  callers (all currently non-isolated); a `nonisolated(unsafe)` cache would be an unsound data
  race. No measurement shows this path is hot, so neither price is justified yet. Profile first.
- **`layout/refresh.swift`.** `activeRefreshTask?.cancel()` discards in-flight refresh work when a
  new session starts. This is also the reason the max-wait ceiling above cannot simply be re-added:
  fix the unconditional cancel first.
- **Batching AX attribute reads.** `AXUIElementCopyMultipleAttributeValues` is the right primitive
  and is not used. A previous attempt (`AxBatchFetcher`) was deleted rather than wired in: it was
  broken (`as? CGPoint` on an `AXValue` is always nil) and its `.stopOnError` mode would have been a
  pessimization: one absent attribute such as `AXFullScreen` falls back to eight individual reads,
  slower than not batching at all. `normalizeLayoutReason` now takes one round trip per window
  rather than two, which captured most of the available win without the batching API.
- **Regression coverage is structural, not timing-based.** `PerfInvariantsTest` pins the algorithmic
  properties (workspace GC, the tray publish guard, `aliveWindowIds` being a `Set`, the `debugLog`
  autoclosure) and `AxWriteTest` counts AX operations through the mock. Neither measures wall clock,
  deliberately; see below. What is *not* covered: the real
  monitor and AX paths. `Monitor.testMonitors` lets a test inject an arrangement, so
  multi-monitor logic is reachable, but nothing drives a live `AXUIElement`.
