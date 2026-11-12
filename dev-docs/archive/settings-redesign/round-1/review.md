# Referee review of the four redesign proposals

Read in full: `proposal-architecture.md`, `proposal-visual.md`, `proposal-a11y.md`, `proposal-whimsy.md`.
Cross-checked against `Sources/AppBundleTests/UIChromeConsistencyTest.swift`,
`Sources/AppBundleTests/DesignKitParityTest.swift`, `Sources/AppBundle/ui/ConfigurationWindow.swift`,
`.claude/skills/aerospork-design/readme.md`, and the actual tab sources
(`WorkspacesMonitorsTab.swift`, `KeyBindingsTab.swift`, `CallbacksTab.swift`, `WindowRulesTab.swift`,
`GapsSettingsTab.swift`, `GeneralSettingsTab.swift`, `RawTomlTab.swift`, `SettingsChrome.swift`).

This is a mechanical read: verify citations, cross-check the four documents against each other and
against the codebase's pinned invariants, flag conflicts and gaps. No new design opinions below
beyond what's needed to adjudicate the checks the brief asked for.

---

## 1. Triage-now

### `WorkspacesMonitorsTab` row-selection may be functionally broken (a11y Finding 1) — independently confirmed plausible, pull out of this pass

Location: `Sources/AppBundle/ui/ConfigurationTabs/WorkspacesMonitorsTab.swift:97-133`.

The a11y proposal is right, and this checks out from static reading, not just the file's own
comment:

- The Table's own in-code comment (`WorkspacesMonitorsTab.swift:126-129`) states outright that both
  columns are filled edge-to-edge by focusable controls (`SettingsField`, `Picker`), which "swallow
  the click that would select the row," leaving `selection` stuck at `nil`.
- I grepped the file for every assignment to `selection`: the only two are `selection = nil`
  (line 21, after a remove) and `selection = nil` (line 131, inside `.onDeleteCommand`). Nothing in
  the file ever sets `selection` to a row id — the only writer would be SwiftUI's own `Table`
  selection machinery reacting to a click, which the comment says is being intercepted by the child
  controls.
- I compared this to `WindowRulesTab.swift:56-62`, which a11y cites as the working counter-example.
  Confirmed by direct read: `WindowRulesTab`'s two `TableColumn`s both return plain `Text`
  (`matchCell(rule)` and `Text(rule.run)...`), not editable controls — so a click has empty row
  space to land on, and Table selection works normally there. `WorkspacesMonitorsTab` structurally
  has no such empty space; every pixel of both columns is inside a control.
- `ListActionBar`'s `onRemove` is wired as `selection == nil ? nil : { ... }`
  (`WorkspacesMonitorsTab.swift:18-22`), so if `selection` genuinely never becomes non-nil, Remove is
  permanently disabled for this tab, for every input method — mouse, keyboard, and VoiceOver alike —
  not only an assistive-technology gap.
- The keyboard half is the one thing I can't confirm by reading code: whether Tab-ing through the
  row and pressing an arrow key ever lands focus on "the row" as opposed to inside the `SettingsField`
  or `Picker`. The `.onDeleteCommand` fallback (lines 130-133) only fires if `selection` is already
  set some other way, so it doesn't establish a keyboard path on its own — it's a safety net for a
  selection that (per the comment) has no way to get set in the first place. This needs the hands-on
  check the a11y proposal calls for.

Verdict: plausible enough, and consequential enough (it may mean assignments can't be removed from
the GUI at all, for anyone), that it should be verified by hand and — if confirmed — fixed as a
standalone bug ticket, not folded into the cosmetic consistency pass this batch of proposals is
scoped to. The fix itself (a11y proposes a new selection-handle column) is a real UI change and
should go through its own review once the diagnosis is confirmed, separately from a design-system
polish pass. See also §4 for a window-width concern with that specific fix if it proceeds.

---

## 2. Convergent findings

### `RowRemoveButton` (architecture Finding 1 + visual Finding 2/secondary candidate) — real convergence, incompatible specs

Both proposals independently converge on: `KeyBindingsTab.swift:169-172` and
`CallbacksTab.swift:102-108` are the same "inline remove this row" control, built twice, and have
already drifted (`role: .destructive` + generic `"Remove"` help in Callbacks vs. no role + a
specific, named help string in Keys — both confirmed accurate by direct read). Both propose
extracting a shared component into `SettingsChrome.swift`. That's a strong, correctly-diagnosed
signal. But the two specs don't match:

- **Architecture's spec** (full code given): `struct RowRemoveButton { let help: String; let
  action: () -> Void }`, using the single `help` string for both `.help(help)` and
  `.accessibilityLabel(help)`, with `role: .destructive` baked in unconditionally.
- **Visual's spec** (named only, not fully written out): `RowRemoveButton(help:accessibilityLabel:action:)`
  — a *different*, three-parameter signature with `help` and `accessibilityLabel` as separate
  arguments.

If implemented independently from each document as written, these produce two different components
with the same name and incompatible call sites. Needs reconciling before either lands — probably in
architecture's favor, since it's the only one of the two with a full implementation, but that's a
human call.

Also worth a second look: both specs bake in `role: .destructive` unconditionally, but architecture's
own Finding 1 table shows `KeyBindingsTab.swift:169-172`'s *current* button has no role set at all.
Migrating it to `RowRemoveButton` silently adds `role: .destructive` to a control that didn't have
it — plausibly correct (it does remove something), but that's a behavior change riding along with
the consolidation, not a pure refactor, and neither proposal calls it out as one.

**Third overlap, uncited by either:** a11y independently proposes `IconButton` (its "Proposed
additions" §1) — a more general icon-only-button-with-mandatory-label wrapper, covering
`Button(role:action:){ Image(systemName:) }` broadly (its own use cases are the filter-clear button
and the mode-options `Menu`, not the remove buttons). None of the three documents (architecture,
visual, a11y) cross-reference each other's new-component proposals. `RowRemoveButton` is a strict
special case of what `IconButton` already covers (icon + mandatory label + optional role,
`.buttonStyle(.borderless)` aside). If a human implements both independently, `SettingsChrome.swift`
ends up with two overlapping "icon-only button, mandatory label" primitives — the exact "two ways to
do one thing" failure this file's own test suite exists to prevent (`UIChromeConsistencyTest.swift:4-7`).
Recommend the synthesis either have `RowRemoveButton` composed from `IconButton`, or drop one of the
two for the remove-button use case.

### `CallbacksTab`'s generic "Remove" label — three proposals independently rewrite the same 5 call sites, three incompatible ways

a11y (Finding 3), whimsy (Finding 7), and architecture (Finding 1's `RowRemoveButton` migration) all
independently flag the exact same defect — `CallbacksTab.swift:102-108`'s shared `removeButton`
gives every row across 4 command sections + the env-var list the identical accessible name "Remove"
— and all three propose fixing it by threading the row's own text through. Strong 3-way convergence
on the *diagnosis*. The *fixes* are three different signatures producing three different strings for
the same controls:

| Proposal | Signature | Resulting label (example) |
|---|---|---|
| a11y (Finding 3) | `removeButton(named:)`, function prepends `"Remove "` | `Remove exec-and-forget open -a Terminal` (no quotes) |
| whimsy (Finding 7) | `removeButton(_ help: String = "Remove", action:)`, caller passes the whole finished string | `Remove "exec-and-forget open -a Terminal"` (curly quotes) |
| architecture (Finding 1, `RowRemoveButton` migration) | `help: "Remove \(row.name.isEmpty ? "this variable" : row.name)"` inline at the call site | `Remove PATH` (env var), no quotes, no fallback wording for commands shown |

Beyond the signature mismatch, note that **whimsy's version is the only one of the three that follows
the design system's own documented convention** — "Curly quotes around user-supplied names:
`Leave “service” mode`" (`.claude/skills/aerospork-design/readme.md:76`) — a11y's and architecture's
versions both omit the quotes. This is the strongest 3-way spec collision in the batch: it's the same
five call sites in the same file, rewritten three different ways in three different documents, and a
synthesizer needs to pick exactly one (and probably fold the choice into whichever `RowRemoveButton`/
`IconButton` resolution wins in the previous finding, since the same call sites are involved).

### Minor convergence, no conflict: both architecture and visual independently decline to extract `CallbacksTab`'s `addButton`

Architecture (Finding 1): "Callbacks' `addButton`... doesn't clear the bar this file was built on...
don't force a shared component prematurely." Visual ("Not proposing" note under its `SettingsChrome`
section): "`CallbacksTab`'s `addButton()` has no independent second implementation anywhere else in
the seven tabs... fails the ≥2-tab bar on its own." Same reasoning, same conclusion, no reconciliation
needed — flagging only because it's a clean example of independent convergence *not* generating a
spec conflict, worth noting as a signal the two proposals are applying the same bar consistently.

---

## 3. Conflicts

### Non-Form `SectionLabel` header padding — architecture Finding 3 vs. visual Finding 3 — direct, incompatible, both tagged "safe"

Both proposals identify the same three call sites as inconsistent with each other —
`WorkspacesMonitorsTab.swift:32-35` ("Connected monitors"), `WorkspacesMonitorsTab.swift:83-86`
("Workspace assignments"), `WindowRulesTab.swift:26-28` ("Rules") — and both tag their fix
**"safe — ship this pass."** But they standardize on opposite target values:

- **Architecture's Finding 3** (second table): standardize to **horizontal 14 / top 10**, anchored on
  `WindowRulesTab.swift:26-28`'s current values. Proposed change: both `WorkspacesMonitorsTab`
  headers move from horizontal 16 to 14, and their top padding to 10.
- **Visual's Finding 3**: standardize to **horizontal 16 / top 14 / bottom 8**, anchored on
  `WorkspacesMonitorsTab.swift:32-35`'s current values. Proposed change: `WindowRulesTab.swift:26-28`
  moves from horizontal 14 to 16, top from 10 to 14, bottom from 10 to 8.

These are mutually exclusive end states for the same three call sites. A human has to pick one before
either lands — implementing both, in either order, produces thrash.

One additional wrinkle worth flagging while adjudicating: I read `WindowRulesTab.swift:26-28`
directly — its actual code is `.padding(.horizontal, 14)` then a single `.padding(.vertical, 10)`,
i.e. **symmetric** top-and-bottom 10, not a "top 10" value with an unstated bottom. Architecture's
table for this finding has no Bottom column at all and its prose only discusses "top," so even fully
applied, architecture's fix leaves Bottom inconsistent (Monitors stays at 8, Window Rules stays at
10) — it resolves the Horizontal and Top axes but not Bottom. Visual's table tracks all three axes
and its fix (16/14/8 everywhere) is the only one of the two that would actually produce full 3-way
consistency across horizontal, top, *and* bottom if applied as written. That's a data point for the
tie-break, not a reason to default to visual's numbers — the bar-strip precedent architecture also
cites (14/9, matching the majority of existing call sites elsewhere in the window) is a legitimate
counter-argument for the other anchor.

I did not find any other direct, same-line, incompatible-prescription conflicts across the four
documents (the two convergent findings in §2 are spec mismatches on an agreed *fix*, not disagreements
about the underlying diagnosis).

---

## 4. Invariant violations

### `UIChromeConsistencyTest` / hand-rolled chrome — clean

None of the four proposals reintroduce a hand-rolled `Capsule()`, a raw SF Symbol status string
outside `StatusLabel.Kind` (`checkmark.circle`, `equal.circle`, `exclamationmark.octagon.fill`,
`exclamationmark.triangle.fill`), an emoji/glyph status icon, or a `TextField` title-as-placeholder.
All five new components proposed across the batch (`RowRemoveButton`, `PanelHeader`, `IconButton`,
`settingsAnnounce`, `settingsHitTarget`) are proposed to live in `SettingsChrome.swift`, which
`UIChromeConsistencyTest.tabSources()` explicitly excludes from its scan
(`Sources/AppBundleTests/UIChromeConsistencyTest.swift:14,26`) — so even if the exact contract isn't
settled yet (see §2), none of these proposals would trip the existing mechanical tests by virtue of
where they live. No proposal adds a new `TextField("...", text:)` call anywhere in a tab file.

### a11y's own proposed new test rule doesn't cover its own cited example

a11y's "Proposed additions" §1 proposes extending `UIChromeConsistencyTest` with a source-text rule:
"flag any `Button { … } label: { Image(systemName:` (or `Button(role: …, action: …) { Image(systemName:`)
in a tab file that isn't going through `IconButton`," and claims "That single rule would have caught
Findings 2 and 3 mechanically." I checked Finding 2's "Location B" directly
(`KeyBindingsTab.swift:73-82`, confirmed): it's

```swift
Menu {
    Button("New mode…") { addingMode = true }
    Button("Delete “\(selectedMode)”", role: .destructive) { removeMode() }
} label: {
    Image(systemName: "ellipsis.circle")
}
```

— a `Menu`, not a `Button`. The proposed rule's pattern only matches `Button`, so as specified it
would not have caught Location B (it would catch Location A, the filter-clear `Button`, and Finding
3's `CallbacksTab` remove buttons, both real `Button`s). Separately, `IconButton` as specced
(`Button(role: role, action: action) { Image(systemName: systemImage) }`) can't wrap a `Menu` either
— which is consistent with Finding 2's own proposed fix for Location B being a direct `.help()`/
`.accessibilityLabel()` on the `Menu`, not `IconButton` adoption. So the fix for Location B is fine;
the "one rule catches both" framing in the "Proposed additions" section overstates it and should be
corrected (either broaden the grep to also match `Menu { … } label: { Image(systemName:`, or scope
the claim down to what it actually catches).

### Window-size floor — confirmed real numbers; two proposals add width without accounting for it

`Sources/AppBundle/ui/ConfigurationWindow.swift:63`:
```swift
.frame(minWidth: 780, idealWidth: 880, minHeight: 520, idealHeight: 620)
```
This matches what the design doc states (`readme.md:30`, "880×620 ideal, 780×520 minimum") and what
the proposals assumed — no proposal is working from a wrong number, and this window has already hit
the 780pt floor for real once: `KeyBindingsTab.swift:106-116`'s own comment documents that an earlier
version of the mode/filter bar overflowed 780pt with 9 modes, and that "a config with nine modes
still overflows 780pt" even with the current mitigation. This is a live constraint in this codebase,
not a theoretical one.

- **a11y Finding 1's proposed fix** (a new leading "selection handle" column, "no `.width` needed
  beyond ~20pt," added to `WorkspacesMonitorsTab`'s `Table`) adds width to a tab that already runs a
  110-140pt `Workspace` column plus an unconstrained `Monitor` picker column, inside a window whose
  *minimum* is 780pt. The proposal doesn't mention the floor at all. Given this exact window has
  already shipped a width-overflow bug in a sibling tab, this deserves an explicit floor check before
  the fix lands (separately from the triage in §1, which is about confirming the bug — this is about
  the specific remediation once it's greenlit).
- **a11y Finding 3's `settingsHitTarget`** (`.frame(minWidth: 24, minHeight: 24)`) applied to
  `CopyButton`'s icon (currently `.frame(width: 14)`, `SettingsChrome.swift:452`) adds roughly 10pt
  where it's used in `WorkspacesMonitorsTab`'s monitor row — already the most horizontally packed row
  in the window (icon, name/resolution stack, spacer, truncated UUID, then the button). Not
  necessarily broken, but not accounted for in the proposal either.
- By contrast, **architecture's Finding 4** (new column-header row above `KeyBindingsTab`'s `List`)
  explicitly reuses the rows' own existing `frame(width: 170, ...)` values rather than introducing new
  widths — this is the one width-adjacent proposal in the batch that visibly accounts for the floor.
- No other proposal in any of the four documents adds width or height anywhere.

### `DesignKitParityTest`'s five pinned phrases — clean

Confirmed exact list and file pairs from `Sources/AppBundleTests/DesignKitParityTest.swift:33-49`:

| Phrase | Swift | Kit |
|---|---|---|
| "Add rule" | `WindowRulesTab.swift` | `ui_kits/settings_app/RulesTab.jsx` |
| "Add assignment" | `WorkspacesMonitorsTab.swift` | `ui_kits/settings_app/MonitorsTab.jsx` |
| "Startup & behaviour" | `GeneralSettingsTab.swift` | `ui_kits/settings_app/GeneralTab.jsx` |
| "Pause tiling" | `MenuBar.swift` | `ui_kits/menu_bar/MenuBarKit.jsx` |
| "Non-main" | `WorkspacesMonitorsTab.swift` | `ui_kits/settings_app/MonitorsTab.jsx` |

Checked every copy change proposed across all four documents against this list — none touch any of
the five phrases:

- Whimsy's Finding 3 rewrites `WorkspacesMonitorsTab.swift:106-113`'s monitor picker, but only inside
  the `ForEach(viewModel.liveMonitors)` branch; the `Text("Non-main").tag("secondary")` line
  (confirmed at line 108, untouched by the proposed diff) is above that loop and isn't part of the
  edit.
- Nothing in any proposal touches `WindowRulesTab`'s or `WorkspacesMonitorsTab`'s "Add rule" /
  "Add assignment" CTA strings (architecture's Finding 2 touches the *Monitors* empty state, a
  different, unlabeled `SettingsHint`, not the Assignments CTA that owns "Add assignment").
- Nothing touches `GeneralSettingsTab`'s "Startup & behaviour" `SectionLabel` — confirmed by direct
  read (`GeneralSettingsTab.swift:20`). Whimsy's Findings 4 and 6 touch `Toggle` labels and add
  `.help()` text inside that same section, not the header itself.
- Nothing in any of the four documents touches `MenuBar.swift`.

Clean across all four proposals — no updates to `DesignKitParityTest` or the kit would be required by
anything proposed here.

---

## 5. Scope-creep flags

Stated boundary: bounded visual/interaction consistency pass, no new navigation paradigm, no tab
restructuring.

- **Architecture Finding 1's "bigger swing, optional" idea** to convert `CallbacksTab`'s four `Form`
  `Section`s into "one `List`-backed pattern instead" is a structural rewrite of a tab's internal
  layout — the one idea across all four documents that comes closest to "tab restructuring." The
  proposal flags this tension itself and recommends against it ("I'd leave this one alone"), so it's
  self-policing, but a synthesizer should drop it explicitly rather than let it survive as a
  deprioritized-but-still-listed option.
- **a11y Finding 6** (`RecorderView` font scaling via a `preferredFont(forTextStyle:)`-equivalent)
  introduces a capability — tracking the system text-size preference — that doesn't exist anywhere
  else in this window; the proposal's own Finding 4 write-up calls the adjacent announcement pattern
  "not used anywhere in the codebase yet." I found no control in the window that currently tracks
  Dynamic-Type-equivalent text scaling by any mechanism, so this reads as introducing new
  infrastructure rather than bringing one outlier control in line with an established pattern the
  rest of the window already follows. Worth a scope check before folding it into a "consistency" pass.
- **a11y's proposal to add a new source-text rule to `UIChromeConsistencyTest`**, and the
  `settingsAnnounce`/`AccessibilityNotification.Announcement` pattern, are test-infrastructure and
  new-interaction-pattern additions respectively — defensible given a11y's proposal was explicitly
  commissioned to find these gaps, but technically beyond "visual/interaction consistency" in the
  strictest reading. Flagging for the record, not as an objection.
- No proposal suggests new navigation, tab merging/reordering, or new top-level surfaces. All four
  explicitly state and respect that boundary in their own scope sections.

---

## 6. Everything else — checked clean

- **Design-token audit (visual proposal's clean-bill claims).** Spot-checked the specific tokens
  visual's preamble and Finding 1 cite — `--fill-subtle: rgba(0,0,0,0.045)`,
  `--fill: rgba(0,0,0,0.06)`, `--fill-strong: rgba(0,0,0,0.08)`, `--separator`, `--border-control`,
  `--space-9`, `--space-16`, `--pad-section-x` — against `tokens/colors.css` and `tokens/spacing.css`
  directly. All match exactly as quoted.
- **Motion / hardcoded color.** Grepped `Sources/AppBundle/ui/` for `.animation(`, `withAnimation`,
  `Color(red:`, `NSColor(red:` — zero hits, confirming both the a11y proposal's and the design doc's
  "essentially no animation, no literal colors" claims. None of the four proposals add any animation,
  motion, toast, gradient, or hardcoded color; whimsy's "Declined ideas" section explicitly rejects a
  scale/bounce flourish, a shake/red-flash, and a confirmation modal for exactly this reason, and that
  self-check holds up against `readme.md`'s "nothing scales or bounces" / "no toasts" language.
- **Voice/copy compliance.** Every proposed string across all four documents is sentence case, with
  no exclamation marks, emoji, or jokes. Curly quotes are used correctly where a proposal quotes a
  user-supplied name (whimsy Finding 7's better-compliant option, Finding 3's picker relabel). The
  menu-item ellipsis convention is respected — whimsy Finding 8 explicitly declines to add one since
  "Delete" doesn't open anything further, matching `readme.md:76`'s stated rule. Whimsy's own
  "Declined ideas" section (gamification badges, color-as-freshness-indicator, a friendlier empty
  state) independently reaches the same conclusions the design doc would, for the reasons the doc
  gives — cross-checked against `readme.md` and holds up.
- **Two minor, non-blocking observations, noted for completeness rather than as invariant
  violations:**
  - Whimsy's Finding 5 (regex `.help()` text for `WindowRulesTab`'s App name/Window title fields)
    frames itself as "explain the consequence," but the proposed text ("Regular expression matched
    against the app's display name") names the field's *format*, not the specific surprising
    behavior the finding's own rationale describes (a literal string matches by substring, not
    exact). Not a rule violation, just weaker than the bar the finding sets for itself.
  - Whimsy's Finding 4 proposes `.help(dockIconIsForced ? "..." : "")` — an empty-string `.help()`
    for the enabled case. Whether AppKit renders a visible empty tooltip bubble on hover versus no
    tooltip at all isn't something I could confirm by reading source; worth a quick manual check
    during implementation, not a spec problem.
