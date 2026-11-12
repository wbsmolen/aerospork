# Window Rules tab — redesign proposal

Scope: `Sources/AppBundle/ui/ConfigurationTabs/WindowRulesTab.swift` content pane only (list +
detail split). Tab chrome and the seven-tab shell are out of scope.

## 1. Direction

The tab's bones are sound — list/detail split, `Table` + `ListActionBar` on the left, grouped
`Form` on the right — and the prior pass already fixed its header padding via `PanelHeader`. I'm
not restructuring it. The one real content gap is `duringAeroSporkStartup`: a schema field the
row model and the writer already round-trip byte-for-byte, but that has no control anywhere in
the UI. Closing it is the redesign's spine; everything else is a small, targeted clarity pass
around it, using only components already in the shared toolkit.

I deliberately did **not** turn "Then run" into a structured action builder (dropdowns per
supported command, chip list, etc.), even though only two commands (`move-node-to-workspace`,
`layout`) are legal there. That's a bigger interaction paradigm than any other tab in the kit
uses for command entry (`CodeEditor`/Raw TOML and `KeyBindingsTab`'s recorder both keep commands
as typed text), it isn't a confirmed gap the way `duringAeroSporkStartup` is, and it would be the
one part of this pass that reads as "a different tab" rather than "the same tab, finished." The
mono `TextField` stays; I add one grounded sentence of footer copy instead (§2.3), which gets
most of the same benefit — knowing what's legal before you type it — for near-zero risk.

## 2. Specific changes

### 2.1 New matcher: "Startup timing"

Add a fifth row to the **Match when…** `FormSection`, after Workspace (this exact order —
App ID, App name, Window title, Workspace, Startup timing — matches the field order in
`docs/guide.adoc`'s own `[[on-window-detected]]` example).

```
LabeledContent("Startup timing")
  → SegmentedPicker, 3 options: "Any" | "Startup" | "Runtime"
```

Existing `SegmentedPicker` component, no changes to it — same pattern already used for 2–3
mutually-exclusive short choices (the component's own doc comment names "the Keys mode
switcher" as precedent). This is the only shared component this proposal touches, and it's a new
*use*, not a new *shape* of it.

**Value mapping** (the field is `Bool?` — three real states, not a checkbox):

- `nil` → segment **"Any"** (leftmost = the default/most common state)
- `true` → segment **"Startup"**
- `false` → segment **"Runtime"**

```js
value={rule.duringStartup === true ? 'true' : rule.duringStartup === false ? 'false' : 'any'}
onChange={(v) => update({ duringStartup: v === 'any' ? undefined : v === 'true' })}
```

For the eventual Swift pass (not the mockup): `WindowRuleRow.duringStartup: Bool?` and
`ConfigurationWriter.swift:472` already read/write this field correctly for all three states —
confirmed by reading both. Only the control is missing. Add a 3-case `enum StartupTiming: any,
startup, runtime` and a computed `Binding<StartupTiming>` (same shape as the existing `field(_:_:)`
helper at the bottom of `WindowRulesTab.swift`, but mapping `Bool?` instead of `String`), bound to
`.pickerStyle(.segmented)`. No writer or view-model changes needed — this is strictly additive.

### 2.2 Footer copy — "Match when…" section

Current footer: *"Empty matchers are left out. A rule with no matchers at all applies to every
window. `aerospork list-apps` prints app IDs."*

New footer, one clause inserted, grounded in `docs/guide.adoc`'s own line ("If not specified then
the condition isn't checked"):

> Empty matchers are left out. A rule with no matchers at all applies to every window. Startup
> timing is not checked until you set it — Runtime matches every detection after AeroSpork has
> finished starting up, including every later relaunch. `aerospork list-apps` prints app IDs.

The "Runtime…" clause is the one place this tab explains what "Runtime" means, since the segment
label itself has room for one word, not a sentence — same pattern the tab already uses for
`workspace = '3'` needing `aerospork list-apps` explained in prose rather than inline.

### 2.3 Footer copy — "Then run" section

Current: *"Chain commands with `;`. By default a matching rule stops the search."*

New, one clause appended, grounded in `docs/guide.adoc`'s "Only move-node-to-workspace and layout
are supported in run so far":

> Chain commands with `;`. By default a matching rule stops the search. Only
> `move-node-to-workspace` and `layout` are supported here; anything else fails to load.

### 2.4 List: make the badge tell the whole story

`matchCell`'s existing inline `Badge("startup", tone: .muted, …)` only fires for `true`, per its
own comment ("The UI has no control for `during-aerospork-startup`, but it round-trips it. Say
so…"). That comment is now stale — replace the whole block with a two-way version. Same cell,
same `Badge` component, same `.muted` tone (this is a provenance/state marker, not a status —
`.muted` gray is correct for both, per the existing precedent of the `"generated"` badge):

```
if rule.duringStartup == true  → Badge("startup", tone: .muted,
    help: "Only applies while AeroSpork is starting up")          // unchanged copy
if rule.duringStartup == false → Badge("runtime", tone: .muted,
    help: "Only applies after AeroSpork has finished starting up") // new
if rule.duringStartup == nil   → no badge                          // unchanged
```

No badge for `nil` is deliberate, not an oversight: it keeps the common case (timing not
constrained) visually quiet, and a reader learns the convention from the two badges that *do*
appear — "no badge" reads as "no constraint" once you've seen one of the other two.

No new `DataTable`/`Table` column. I considered giving Timing its own column (cleaner separation
from the mono match text) and rejected it: the list pane's floor is 280px, the match cell is
already the thing absorbing overflow via truncation, and a third column buys clearer visual
separation at the cost of squeezing that column further for no functional gain over the existing
inline-badge pattern, which already handles the `true` case today. Smallest correct diff: extend
the existing `if` to an `if/else if`, don't restructure the table.

## 3. Shared components used

- **`SegmentedPicker`** — existing component, new call site (Window Rules hasn't used it before).
  Three options, `"Any" | "Startup" | "Runtime"`. Flag for the reconciliation pass: if another tab
  independently reaches for a tri-state segmented control with different option-count conventions,
  check they agree that 3 short single-word segments is the ceiling before it should become a
  `Select` instead.
- **`Badge`** (`tone="muted"`) — existing component, existing call site, just a second text value
  (`"runtime"`) and a second `help` string alongside the pre-existing `"startup"` one. No API
  change.
- **`LabeledContent`**, **`FormSection`**, **`SectionLabel`**, **`DataTable`**/`Table`,
  **`ListActionBar`**, **`ContentUnavailable`**, **`PanelHeader`**, **`TextField`**, **`Toggle`** —
  all unchanged, all already in use by this tab.

Nothing new added to `SettingsChrome.swift` / the JSX component layer.

## 4. Fits at 780×520

- **Width.** List pane stays `minWidth: 280 / idealWidth: 340`; detail pane stays `minWidth: 330`.
  Unchanged, since the new control is one more row inside the existing `LabeledContent` grid, not
  a wider one — a 3-segment picker reading "Any / Startup / Runtime" is roughly 150–170px, well
  inside a 330px-min detail pane that already fits a full-width mono `TextField` in the section
  below it. `280 + 330 = 610`, `340 + 330 = 670` — both comfortably under 780 even before
  `HSplitView`'s divider, same margin the shipped tab already has today.
- **Height.** The new row adds one `LabeledContent` (~the same height as the existing Workspace
  row it sits directly below) to a `Form` that already renders 4 matcher rows + a footer + 2
  "Then run" rows + a footer inside 520pt minimum height today. One additional row of the same
  height as its four siblings is a small, proportional increase, not a new order of magnitude —
  and a SwiftUI `Form` in `.formStyle(.grouped)` already degrades to native scrolling if content
  ever exceeds the pane, the same guarantee the tab relies on today. Nothing here is a new failure
  mode.
- **List with several rules, each showing all fields.** The two states that matter are the list
  (many rows, one line each) and the detail (one rule, all fields) — never both "many rows" and
  "all fields" at once, because only the selected rule's fields render. List rows stay one line
  regardless of how many matchers a rule has (`summary()` already joins them into one truncating
  string); the only per-row addition is a single compact badge, which is exactly the same
  footprint the shipped tab already budgets for today's `true`-only badge.

## 5. `duringAeroSporkStartup` — summary of the design

Three real states, three explicit representations, no field left silently unreachable:

| Row model (`Bool?`) | Segmented control (Match when…) | List badge | Meaning |
|---|---|---|---|
| `nil` | "Any" (default) | none | Condition not checked — matches regardless of startup timing |
| `true` | "Startup" | `startup` (muted) | Matches only while AeroSpork is finishing launching |
| `false` | "Runtime" | `runtime` (muted) | Matches only after startup, including every later relaunch |

This closes the gap the code itself flagged (`WindowRulesTab.swift:73`'s comment, now stale and
removable) without touching the row model or the writer, both of which already handle all three
states correctly — confirmed against `ConfigurationViewModel.swift` (`duringStartup: Bool?` on
`WindowRuleRow`) and `ConfigurationWriter.swift:472` (`if let during = rule.duringStartup {
block.append("if.during-aerospork-startup = \(bool(during))") }`, and `nil` correctly omits the
key). The unset state is not defaulted to `false` anywhere in this design — collapsing "not
checked" into "checked and false" would silently narrow every existing rule with the condition
genuinely unset, which is the same class of bug the writer-invariant note in `CLAUDE.md` warns
against for a different field.
