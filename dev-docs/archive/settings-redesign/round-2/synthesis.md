# Settings GUI redesign v2 — synthesis

Reconciles all seven tab proposals (`proposal-general.md`, `proposal-gaps.md`, `proposal-keys.md`,
`proposal-monitors.md`, `proposal-events.md`, `proposal-rules.md`, `proposal-rawtoml.md`) and the
adversarial cross-critique (`review.md`) into what Stage 2.5 (the mockup build) implements. All
four proposals' load-bearing factual claims were independently verified against the working tree
and confirmed accurate — this synthesis makes design/reconciliation calls, not fact-checks.

## Correction: the baseline every proposal was told about is wrong — read this first

Every tab brief said the prior round's `IconButton`, `PanelHeader`, and various casing/padding/
empty-state fixes were "already shipped in both the real Swift and the mockup." **That's false for
everything except two specific fixes.** Verified in `review.md` §6 with a 12-row table: only the
three Keys-tab bug fixes (modifier-glyph clipping, mode-picker degrade-at-5, the `generated` badge
casing fix, and the uniform 170px recorder width that rode with them) and the
`WorkspacesMonitorsTab` row-selection fix are real in `Sources/AppBundle/`. Everything else from
`dev-docs/redesign/synthesis.md` — `IconButton`, `PanelHeader`, the Key/Command header row, the
unified Monitors empty state, the monitor-picker disambiguation label, the Gaps preview header and
fill/stroke tokens, `CodeEditor`'s 12→13px fix, the bar-strip padding standardization — exists only
in the JSX mockup kit.

This doesn't block Stage 2.5: the mockup kit is the correct, self-consistent thing to build on top
of (that's what "mockup-first" means), and two proposals (Events, Raw TOML) independently caught
and correctly worked around the discrepancy themselves. **But it means the eventual Swift
implementation phase — a separate, later step, still gated behind human review per this project's
established discipline — has to apply the FULL cumulative delta: round 1's consistency-pass
changes and this round's redesign changes together, in one pass, not assume round 1 already
landed.** Two proposals' reasoning depends on a further-along Swift baseline than exists (Keys:
`IconButton` and the header row need to exist first; Gaps: the preview `Section` needs a header
added, not just a footer inserted into one) — noted per-tab below, not a blocker for the mockup.

## Resolved: one real component-contract violation

**Keys' Change B1** puts an arbitrary, user-chosen mode name inside a `Badge`
(`<Badge tone="muted">service</Badge>`). `Badge`'s contract (`Badge.prompt.md`) is fixed,
app-authored vocabulary — "lowercase, one word" — and mode names have no such constraint
(`Config.swift`'s `modes: [String: Mode]` has no name-shape validation; a real config can name a
mode `Resize Mode`). Every other Badge use across all seven proposals (`generated`, `startup`,
`runtime`, `main`, `complex`) is fixed, app-chosen text and stays as designed — this is the one
exception.

**Fix:** in the cross-mode section (B1) and the composer's cross-mode `StatusLabel` (Change C),
render the mode name as curly-quoted inline text instead of a `Badge` — consistent with how the
rest of Keys' own proposal already quotes mode names everywhere else they appear as prose (B2's
empty-state messages, Change C's own line). Concretely: replace `<Badge tone="muted">{mode}</Badge>`
with a plain `Text("“\(mode)”")` at `.callout`/secondary styling, positioned where the badge was.
The generated-origin `Badge("generated", …)` alongside it in B1 is unaffected — that's fixed
vocabulary and stays a real `Badge`.

## Minor: documentation-only additions, no design change

- **Window Rules' `SegmentedPicker` justification**: the outcome (3 fixed segments for a `Bool?`)
  is correct and within the component's documented ceiling, but the proposal argues cardinality
  ("2-3 options") rather than growability, unlike General's rejection of the same conversion for
  its Keyboard picker (which correctly argues *"can this list grow"*). Both land in the same
  place here since `Bool?` truly cannot grow a fourth state — noting the fuller reasoning here so
  it's on record, no change to the design.
- **Keys' width justification** is the thinnest of the seven proposals relative to its own stated
  stress cases (`review.md` §4) — Window Rules and Raw TOML both sum real pixel widths against the
  780px floor; Keys' fit argument for Change D (a per-row `IconButton` stacked on the existing
  170px key column and an already-compressible `SettingsField`) is qualitative only. The
  individual anchors are real and the change is almost certainly fine, but **the mockup build for
  Keys should render a worst-case row** (long command text, both duplicate and remove buttons
  visible, at the 780px floor) and confirm nothing clips before calling it done — a five-minute
  check, not a redesign.

## Everything else: proceed as proposed

Every other proposal's specific changes, component reuse, and rejected-alternatives reasoning
stands as written — the cross-critique found no other conflicts, no scope creep beyond a tab's own
content pane, no voice/casing violations, and confirmed every remaining load-bearing factual claim
(the three-state `duringAeroSporkStartup` round-trip, `preservedWorkspaceNames`'s derived nature,
TOMLKit's discarded line/column, `replaceGaps`' whole-section rewrite). No new shared component is
needed anywhere in this round — every proposal builds entirely from what already exists in the JSX
kit (`Badge`, `StatusLabel`, `SegmentedPicker`, `IconButton`, `Select`/`Picker`, `Toggle`,
`ContentUnavailable`, native `List`/`Section`/`Menu`), which means **the seven tabs' mockup files
can be built in parallel with no collision risk** — unlike round 1, there's no shared-component
file for multiple builders to contend over.

## What ships in the mockup, per tab

**General** (`GeneralTab.jsx`): three copy-only changes — rename "Appearance" section header to
"Menu bar & Dock"; add a footer to "Startup & behaviour" (currently the only section without one);
extend the "Layout" footer to clarify accordion peek applies to any accordion container, not just
new workspaces. No new controls, no layout change.

**Gaps** (`GapsTab.jsx`): a "same value" `Toggle` at the top of each of the two gap sections,
collapsing to one compact field when values already match (seeded once from loaded values, never
auto-recomputed); a conditional `StatusLabel(kind: .neutral)` in the preview section's footer,
shown only when the config actually has per-monitor gap overrides; a tightened, three-sentence
permanent footer. Requires new mock sample-data support for "linked" state and a per-monitor-
override flag — both view-state/display-only, not persisted config.

**Keys** (`KeysTab.jsx`): category-grouped browse view (5 fixed categories, derived from command
verb, only when a mode spans 2+ categories); a supplementary "In other modes" section when
searching finds cross-mode matches, plus a smarter no-match empty state that names which other
mode has it; a neutral cross-mode awareness line in the composer; a `doc.on.doc` "duplicate"
`IconButton` on every row. Mode names render as curly-quoted `Text`, never inside a `Badge` (see
correction above). Verify the worst-case row width per the note above.

**Monitors** (`MonitorsTab.jsx`): a new "Position N — left to right" option group in the monitor
picker (between the Main/Non-main pair and the name/UUID block); a position digit + `main` `Badge`
on the connected-monitors panel; a `complex` `Badge` in the assignments table's Monitor cell for
rows whose underlying config the structured editor can't fully represent (fallback lists, rich
fingerprints); one added clause to the `ListActionBar` hint about preserved workspace names. Also
fix the mockup's pre-existing `'Primary'`/`'Main'` label drift noted in the proposal while touching
that array.

**Events** (`EventsTab.jsx`): per-section command placeholders grounded in `guide.adoc`'s own
examples (only "Focused monitor changed" and "Focus changed" get non-generic placeholders — After
startup and Focused workspace changed keep the current one, per the proposal's own reasoning); an
order-matters clause on the After-startup footer; a conditional `SettingsHint` under the inherit
toggle stating the real secrets-exposure consequence; swap the raw `<input type="checkbox">` for
the shared `Toggle` component and fix its label to match Swift's actual string; extend the
exec-environment footer to mention `AEROSPORK_WINDOW_ID`/`AEROSPORK_WORKSPACE` and
`list-exec-env-vars`; correct the PATH placeholder to the real documented default.

**Window Rules** (`RulesTab.jsx`): a new "Startup timing" `SegmentedPicker` row (Any/Startup/
Runtime) closing the confirmed `duringAeroSporkStartup` gap; one grounded clause each on the
"Match when…" and "Then run" footers; extend the list's existing `startup` badge to a two-way
`startup`/`runtime` badge (no badge for the default "Any" state).

**Raw TOML** (`RawTomlTab.jsx`, `CodeEditor.jsx`): a line-number gutter; restrained 3-tier TOML
highlighting (structure/keys/values/comments — no per-type rainbow coloring, explicitly rejected
as out of voice); inline error/warning gutter markers (clickable jump-to-line when a real position
exists); a `Sections…` jump menu modeled on the tab's existing `Restore…` menu; a caret `Ln, Col`
readout; find-in-editor noted as free via `NSTextView.usesFindBar` (not built in the mockup — it's
system UI). `CodeEditor.jsx` gains new optional props (`errorLine`, `warningLines`, `onCursorMove`,
`sectionHeaders`) — additive, no other tab touches this component. The mockup's tokenizer is
explicitly a simplified illustration (naive comment regex, no string-boundary awareness) — the
proposal's own feasibility table rates each piece honestly (gutter/highlighting: moderate; syntax-
error positions: easy-moderate, mostly plumbing since TOMLKit already computes them and
`parseConfig.swift` currently discards them; semantic-error positions: permanently best-effort,
degrades to no marker rather than guessing wrong).

## Verified clean against hard invariants

- **Window-size floor** (780×520 min / 880×620 ideal): six of seven proposals include real
  arithmetic or structural reasoning (scrolling `Form`, no new fixed-width elements); Keys is the
  one to double-check during build (see above). No proposal adds width/height to an always-visible
  element outside that one flagged case.
- **Voice/casing**: sentence case, no exclamation marks/emoji/jokes, curly quotes around
  user-supplied names — all confirmed compliant across all seven documents except the one Badge
  exception, now corrected above.
- **`DesignKitParityTest`'s five pinned phrases**: untouched by anything in this round (none of
  the seven proposals modify "Add rule," "Add assignment," "Startup & behaviour" as a literal
  phrase — General renames a *different* section, "Appearance," not this one — "Pause tiling," or
  "Non-main").
- **Scope**: no proposal touches the `TabView` shell or any chrome outside its own tab's content
  pane; every new control traces to a real `Config.swift` field already round-tripped by the
  writer (confirmed per-tab in `review.md` §1 and §3).
