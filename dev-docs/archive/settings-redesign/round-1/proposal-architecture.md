# Settings window — cross-tab structural consistency proposal

Author: ArchitectUX (structure pass). One of four parallel proposals (visual language,
accessibility, copy/micro-interaction are separate) to be synthesized by a human. Scope is bounded
to the existing seven tabs and `SettingsChrome.swift`; no tab merging/reordering, no new navigation
paradigm — see the brief for why that's off the table.

Ground truth read: `Sources/AppBundle/ui/SettingsChrome.swift`, `Sources/AppBundleTests/UIChromeConsistencyTest.swift`,
`Sources/AppBundle/ui/ConfigurationWindow.swift`, all seven files in `Sources/AppBundle/ui/ConfigurationTabs/`,
and `.claude/skills/aerospork-design/readme.md`.

---

## Headline findings

1. **Four tabs implement "a growable list of removable rows" three different ways**, despite
   `SettingsChrome.swift` existing specifically to stop tabs from independently inventing list
   chrome. Keys uses a `List` with a composer bar and inline per-row remove buttons; Monitors and
   Window Rules use `Table` + `ListActionBar` with a selection model; Callbacks uses rows embedded
   directly in `Form` sections with its own hand-rolled add/remove buttons that appear nowhere in
   `SettingsChrome.swift`. Two of these tabs (Keys, Callbacks) independently invented a
   near-identical inline "minus.circle" remove button — which is exactly the failure mode
   `UIChromeConsistencyTest.swift` was written to catch, and it slipped through because the two
   implementations aren't textually identical enough for the existing greps to catch (one is
   `Capsule()`-shaped detection, this is a `Button` shape).

2. **`WorkspacesMonitorsTab` disagrees with itself** on empty-state treatment. Its "Workspace
   assignments" list, when empty, gets the full `ContentUnavailableViewCompat` (icon, title,
   message, CTA button) — the design system's "empty states teach the feature" pattern. Its
   "Connected monitors" list, when empty, eight lines above it in the same file, gets a bare
   `SettingsHint` sentence with no icon and no title. Both lists live in the same tab, both can be
   empty, and a user scrolling between them sees two different visual languages for the identical
   concept "nothing here yet."

3. **Pinned bar-strip chrome has no single padding value**, despite the design system explicitly
   naming one (`.padding(.vertical, 9) on a bar strip`). Vertical padding on pinned top/bottom bars
   is 9 in one tab, 8 in another, 10 in a third; horizontal padding is 14 in four places and 12 in
   `ListActionBar` itself — the one component every list-based tab is supposed to be standardizing
   on. None of the deviations are explained by a comment, which is the tell that they drifted rather
   than were chosen.

---

## Finding 1 — three incompatible list-editing idioms (bigger swing, with one safe sub-fix)

**What's inconsistent.** All four of these tabs manage a config array where a user adds/removes
whole rows:

| Tab | Structure | Add | Remove |
|---|---|---|---|
| `KeyBindingsTab.swift:151-155` | `List` of hand-built `HStack` rows | Composer bar with text fields + explicit "Add"/"Replace" button (`KeyBindingsTab.swift:240-260`) | Inline `Button { Image("minus.circle") }` per row (`KeyBindingsTab.swift:169-172`) |
| `WorkspacesMonitorsTab.swift:97-133` | `Table` with `TableColumn`s, selection-bound | `ListActionBar`'s icon-only `+` (`WorkspacesMonitorsTab.swift:14-24`) | `ListActionBar`'s icon-only `-`, acts on `selection` |
| `WindowRulesTab.swift:56-63` | `Table` with `TableColumn`s, selection-bound | `ListActionBar`'s icon-only `+` (`WindowRulesTab.swift:31-36`) | `ListActionBar`'s icon-only `-`, acts on `selection` |
| `CallbacksTab.swift` (5 lists: 4 command sections + env vars) | Rows embedded directly inside `Form` `Section`s | `addButton(_:_:)` helper, text-labeled, accent-colored, scrolls with content (`CallbacksTab.swift:96-100`) | `removeButton(_:)` helper, inline `Image("minus.circle")` (`CallbacksTab.swift:102-108`) |

Two of these (Monitors, Window Rules) already agree with each other — `Table` + `ListActionBar` +
selection is the established pattern for a homogeneous list of structured rows with 2+ typed
columns. Keys and Callbacks both diverge from it, and from each other, for the same underlying
reason: neither has (or wants) a single-selection model. Keys mixes two structurally different row
shapes (editable vs. read-only-with-badge-and-Override), which doesn't fit `Table`'s
one-shape-per-column model. Callbacks manages five independent small lists (typically 0-3 rows
each) inside one `Form`, where a `Table` per list would be mostly empty chrome. **Both of those are
legitimate reasons to not use `Table` + `ListActionBar`** — I'm not proposing to force them into it.

What isn't legitimate is that Keys and Callbacks then each rolled their own version of the same
"remove this one row inline" button:

- `KeyBindingsTab.swift:169-172`: `Button { remove(rowId) } label: { Image(systemName: "minus.circle") } .buttonStyle(.borderless) .help("Remove this binding") .accessibilityLabel("Remove \(b.key)")`
- `CallbacksTab.swift:102-108`: `Button(role: .destructive, action: action) { Image(systemName: "minus.circle") } .buttonStyle(.borderless) .foregroundStyle(.secondary) .help("Remove") .accessibilityLabel("Remove")`

Same icon, same button style, same intent, independently written twice, with small unforced
differences (Callbacks sets `role: .destructive` and a generic "Remove" help string; Keys omits the
role and writes a specific, more accessible help string naming which binding). This is textually
the same shape of problem `UIChromeConsistencyTest.swift:111-121` already pins for badges
("`testNoTabMarksOriginWithBareText` ... same file, two implementations, one with no accessibility
label") — it just wasn't caught because the existing chrome tests grep for `Capsule()` and specific
SF Symbol string literals, not for `Image(systemName: "minus.circle")`.

**Why it matters.** A user who has learned "click the minus to remove a row" in Keys re-learns
nothing in Callbacks — the controls happen to look almost identical — but the generic "Remove" help
text in Callbacks is a regression versus Keys' per-row-named text, and it's pure accident that they
match as well as they do. The next tab that needs an inline remove button has equal odds of copying
either one, keeping the drift alive.

**Proposed fix.**
- *Safe — ship this pass*: add `RowRemoveButton` to `SettingsChrome.swift` (spec below), and point
  `KeyBindingsTab.swift:169-172` and `CallbacksTab.swift:102-108` (and its five call sites at
  `CallbacksTab.swift:45-49, 78-82`) at it. This is a mechanical consolidation of two already-near-
  identical call sites — exactly the kind of change `CopyButton` (`SettingsChrome.swift:439-461`,
  itself introduced because "two tabs need it and they had two different ones") already sets
  precedent for.
- *Bigger swing*: leave `CallbacksTab`'s `addButton` (`CallbacksTab.swift:96-100`) as a tab-local
  private helper for now — it's used five times within one file, not independently invented in a
  second tab, so it doesn't clear the bar this file was built on. If a future tab needs the same
  "inline add, text-labeled, scrolls with content" affordance, promote it then, matching Keys'
  composer-style Add button only if the shape actually converges (Keys' Add is tied to a whole
  composer with input fields; Callbacks' Add just appends an empty row) — don't force a shared
  component prematurely.
- *Bigger swing, optional*: if the team wants full convergence, Callbacks' four near-identical
  command sections could become one `List`-backed pattern instead of four `Form` `Section`s, but I'd
  weigh this against the fact that each section's help footer text is genuinely distinct per event
  (`CallbacksTab.swift:12-36`) — a `Form` section with a footer is doing real communicative work a
  bare list wouldn't do for free. I'd leave this one alone.

## Finding 2 — `WorkspacesMonitorsTab`'s two empty states contradict each other (safe)

**What's inconsistent.**
- `WorkspacesMonitorsTab.swift:39-43` (Connected monitors, empty): a bare `SettingsHint` sentence —
  no icon, no title, just one line of secondary-colored prose.
- `WorkspacesMonitorsTab.swift:88-95` (Workspace assignments, empty): full
  `ContentUnavailableViewCompat` — icon, headline title, message, and an "Add assignment" CTA button
  that fires the same action as the toolbar's `+`.

The comment at `WorkspacesMonitorsTab.swift:38` claims consistency it doesn't deliver: "Same
empty-state treatment as every other list in this window, rather than a section header floating
above nothing" — the actual code avoids a floating header by falling back to a hint, not by using
the shared `ContentUnavailableViewCompat` every other emptyable list/table pane in the window uses
(compare `KeyBindingsTab.swift:131-138`, `WindowRulesTab.swift:48-54`, `WindowRulesTab.swift:124-129`,
all of which use `ContentUnavailableViewCompat`).

**Why it matters.** This directly contradicts the design system's stated empty-state voice rule
("empty states teach the feature, they don't announce emptiness" —
`.claude/skills/aerospork-design/readme.md:70-71`): the monitors hint announces absence ("No
monitors reported yet") without teaching anything about what a monitor row would look like or why
UUIDs matter, while the assignments empty state does both (explains where workspaces land by
default, and offers the fix). It's also the one place in the window where the same visual concept
("this list is empty") reads as two different levels of finish within a single scroll.

**Proposed fix.** Replace the `SettingsHint` at `WorkspacesMonitorsTab.swift:39-43` with
`ContentUnavailableViewCompat(icon: "display", title: "No monitors detected", message: "Monitors
appear here as soon as macOS reports one. Their UUIDs are what pins a workspace to a specific
physical panel.", messageIsMarkdown: true)`. No action button — there's nothing to "add," monitors
appear on their own — which is itself consistent with `WindowRulesTab.swift:124-129`'s
no-action empty state ("No rule selected"). Constrain the monitors pane's existing
`.frame(maxHeight: 200)` (`WorkspacesMonitorsTab.swift:77`) to also apply a sensible `minHeight`
(e.g. 120) so the empty-state icon/title/message combination isn't cramped inside a short strip —
today's hint fits in one line at any height, but `ContentUnavailableViewCompat` wants room to
center vertically.

Tag: **safe — ship this pass**. Single call site, drop-in replacement, matches an existing pattern
verbatim.

## Finding 3 — pinned bar-strip padding is not one number (safe)

**What's inconsistent.** The design system names a specific value: "`.padding(.vertical, 9)` on a
bar strip, `7px` above a +/- row" (`.claude/skills/aerospork-design/readme.md:111-113`). In the
actual tabs:

| Location | Horizontal | Vertical |
|---|---|---|
| `KeyBindingsTab.swift:123-125` (mode bar, top) | 14 | 9 |
| `KeyBindingsTab.swift:253-254` (composer, top of HStack) | 14 | 10 (top only) |
| `KeyBindingsTab.swift:270-272` (composer, hint at bottom) | 14 | top 7, bottom 10 |
| `RawTomlTab.swift:60-62` (path bar, top) | 14 | **8** |
| `RawTomlTab.swift:98-99` (action bar, bottom) | 14 | **10** |
| `SettingsChrome.swift:154-156` (`ListActionBar`, bottom, used by 2 tabs) | **12** | top 7 (documented), bottom 7 or 3 |

The `ListActionBar` vertical values (7 top, 7-or-3 bottom) match the doc's separately-documented
"7px above a +/- row," so that part is intentional and I'm not flagging it. What's undocumented and
inconsistent is: `ListActionBar`'s **horizontal** 12 versus every other pinned bar's 14, and
`RawTomlTab`'s vertical 8 and 10 versus the doc's plain "9" for a generic bar strip (it isn't a
+/- row, so the 7px exception doesn't apply to it).

A second, smaller instance of the same drift shows up in non-Form section headers (headers that sit
directly in a `VStack`, not inside a `Form`'s `header:` closure, so they don't inherit `.formStyle`'s
automatic 16px):

| Location | Horizontal | Top |
|---|---|---|
| `WorkspacesMonitorsTab.swift:32-35` (Connected monitors `SectionLabel`) | 16 | 14 |
| `WorkspacesMonitorsTab.swift:83-86` (Workspace assignments `SectionLabel`, same file) | 16 | **12** |
| `WindowRulesTab.swift:26-28` (Rules `SectionLabel`) | **14** | 10 |

**Why it matters.** None of these numbers carry a comment explaining why they differ (contrast with
`ListActionBar`'s own comment justifying its 7/3 split, or the design doc's explicit callout of "9"
and "odd numbers included: 5, 6, 7, 9, 11, 14... Do not round these to a 4/8 grid; the source says 9,
so it is 9"). A mockup builder cross-referencing the design doc against `RawTomlTab` today would
correctly conclude the tab is out of spec. It's the kind of drift that's invisible tab-by-tab and
only shows up when you place two chrome strips side by side — exactly the review this pass is for.

**Proposed fix.**
- Standardize every pinned top/bottom bar strip's outer padding to horizontal 14 / vertical 9,
  matching the documented value and the majority of existing call sites: change
  `RawTomlTab.swift:61` (`8` → `9`), `RawTomlTab.swift:99` (`10` → `9`), and
  `SettingsChrome.swift:154` (`.padding(.horizontal, 12)` → `.padding(.horizontal, 14)`). Leave
  `ListActionBar`'s vertical 7/7-or-3 alone — it's the documented, intentional exception for a +/-
  row.
- Standardize non-Form `SectionLabel` headers to horizontal 14 / top 10, matching
  `WindowRulesTab.swift:26-28` (the odd one out is actually the two Monitors headers, which agree
  with *each other* on horizontal but not on top padding): change
  `WorkspacesMonitorsTab.swift:33-34` (top 14 → 10) and `WorkspacesMonitorsTab.swift:84-85` (top 12
  → 10, horizontal 16 → 14).
- If the horizontal-16 convention is actually meant to distinguish "this section sits above a
  scrolling list pane" from "this section sits above a table," that's a legitimate reason to keep
  Monitors at 16 — but then `WindowRulesTab.swift:26-28` should move to 16 to match, since its list
  pane is structurally the same shape (`SectionLabel` header above a `Table` above a
  `ListActionBar`). Either direction resolves the inconsistency; I'd pick 14 since it's the value
  used everywhere else in the window's non-Form chrome.

Tag: **safe — ship this pass**. Pure numeric alignment, zero behavioral risk, testable by eye.

## Finding 4 — `KeyBindingsTab`'s list has no column-header row (safe, tab-local)

**What's inconsistent.** `WorkspacesMonitorsTab.swift:97-124` and `WindowRulesTab.swift:56-60` both
use `Table` with named `TableColumn`s ("Workspace"/"Monitor", "Matches"/"Run"), which macOS renders
as a real header row above the data. `KeyBindingsTab.swift:151-155` renders functionally the same
two-column shape (a fixed-width key column at `KeyBindingsTab.swift:166,179` beside a command
column) inside a bare `List`, with no header row at all — a user scanning the Keys tab gets no
label telling them what the two columns mean, while the Monitors and Window Rules tabs both do.

**Why it matters.** This is a real information-scent gap, not just a visual mismatch: on first
encounter, Keys' rows read as two unlabeled strings side by side, and the "which one is the
shortcut, which one is the command" answer has to be inferred from font (monospace key vs.
monospace command — both monospace, so font doesn't even disambiguate) or from position, which only
works because the key happens to come first.

**Why it's tab-local, not a `SettingsChrome` addition.** Keys is the only tab with this problem —
the other two column-shaped lists already get a header for free from `Table`. Converting Keys to
`Table` isn't the fix (Finding 1 explains why it doesn't fit: heterogeneous row shapes, no
selection model). A new shared "fake table header" component would be built for exactly one caller,
which fails this project's own bar for adding to `SettingsChrome.swift`.

**Proposed fix.** Add a plain two-`Text` header row directly above the `List` in
`KeyBindingsTab.swift`'s `content` (around line 150), styled to match `Table`'s own header
typography per the design doc ("11px tab titles and table headers" —
`.claude/skills/aerospork-design/readme.md:105-106`): `Text("Key").font(.caption).foregroundStyle(.secondary)`
at the same `frame(width: 170, alignment: .leading)` used by the row cells
(`KeyBindingsTab.swift:166,179`), and `Text("Command")` filling the rest. No new component — three
lines of tab-local view code, matching column widths already established by the rows themselves.

Tag: **safe — ship this pass**.

## Finding 5 — `GapsSettingsTab`'s preview section is the only headerless `Section` in the window (safe)

**What's inconsistent.** Every `Form` `Section` in every other tab — `GeneralSettingsTab.swift`
(6 sections, all with a `SectionLabel` header), `CallbacksTab.swift` (5 sections, all headed),
`WindowRulesTab.swift:85-102,104-120` (both detail sections headed) — carries a `SectionLabel`
header, per the convention `SettingsChrome.swift:203-218` establishes. `GapsSettingsTab.swift:13-24`
is the one exception: the `GapsPreview` lives in a bare `Section { ... }` with no `header:` and no
`footer:` at all, immediately above two headed sections ("Between windows," "Around the screen")
in the same `Form`.

**Why it matters.** In a grouped `Form`, a `Section` still renders as its own boxed group regardless
of whether it has a header — so the preview appears as an unlabeled card sitting directly above two
labeled cards, which reads as an inconsistency in the same glance a user takes to understand the
tab's structure, even though the preview's *purpose* (an at-a-glance illustration of the six values
below it) is self-evident once you look at it.

**Proposed fix.** Give the preview section a header using the same `SectionLabel` convention as its
neighbors, e.g. `SectionLabel("Preview", "eye")` — or, if a visible title feels redundant with an
already-obvious illustration, at minimum confirm the omission is deliberate with a short comment
(matching this file's existing habit of explaining every non-obvious choice, e.g. the comment already
at `GapsSettingsTab.swift:10-12`). Either resolves the inconsistency; leaving it unlabeled and
unexplained is the only wrong answer.

Tag: **safe — ship this pass**.

---

## Proposed addition to `SettingsChrome.swift`

### `RowRemoveButton`

**The ≥2-tab justification** (per this project's own bar, see `SettingsChrome.swift:5-8` and
`UIChromeConsistencyTest.swift:4-12`, which exists precisely to stop this pattern): both
`KeyBindingsTab.swift:169-172` and `CallbacksTab.swift:102-108` independently built an inline
"remove this row" button — same SF Symbol (`minus.circle`), same `.buttonStyle(.borderless)`, same
intent — with no shared definition, and they've already drifted (one sets `role: .destructive` and
a generic help string, the other doesn't and names the row). This is the same shape of finding that
motivated `Badge` and `CopyButton` in the same file.

**Proposed shape:**

```swift
/// Inline "remove this row" button for a row embedded directly in a Form or List, where there's no
/// selection model for ListActionBar's Remove to act on. `help` is mandatory, like Badge's -- a
/// bare "Remove" tells VoiceOver nothing about which row, so callers must name it (e.g. "Remove
/// this binding" or "Remove PATH").
struct RowRemoveButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "minus.circle")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
```

**Call sites to migrate:** `KeyBindingsTab.swift:169-172` (help becomes `"Remove \(b.key)"`, already
the better of the two existing strings — keep it), `CallbacksTab.swift:102-108`'s `removeButton`
helper and its five call sites (`CallbacksTab.swift:45-49` for env vars — help should become
something like `"Remove \(row.name.isEmpty ? "this variable" : row.name)"` rather than the current
generic `"Remove"` — and `CallbacksTab.swift:78-82` for each command section, similarly naming the
row). Migrating Callbacks' help strings to be row-specific is a free accessibility improvement that
falls out of adopting the shared component with its mandatory-`help` constraint.

Not proposed: a shared "inline add" component (see Finding 1 — doesn't clear the 2-tab bar yet) and
not a shared "fake table header" (see Finding 4 — only one caller).
