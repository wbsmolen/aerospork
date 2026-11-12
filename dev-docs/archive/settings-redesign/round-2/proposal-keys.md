# Keys tab — redesign proposal

Scope: `Sources/AppBundle/ui/ConfigurationTabs/KeyBindingsTab.swift`, mirrored in
`.claude/skills/aerospork-design/ui_kits/settings_app/KeysTab.jsx`. Builds forward from the
already-fixed state (modifier glyphs, mode-picker degrade at 5, capitalized `generated` badge,
uniform 170px recorder/composer width, Key/Command header row). Nothing below re-litigates those.

## 1. Direction

The config surface here is already complete — every bindable key and every mode is reachable.
The problem is entirely editing experience: **a real keymap is 40-80 rows in one flat,
alphabetically-sorted list**, and once `[keys]`'s generated bindings are counted, `main` alone
regularly holds 30+ rows before the user has written a line. Scanning that list to answer three
routine questions is slower than it should be:

1. "What's already bound to *move stuff around*, roughly?" (browsing without knowing the exact key)
2. "Is this key meaningful somewhere else already?" (a config has 2-5 modes, and modes deliberately
   reuse keys for different purposes — `esc` means something different in `service` than in `main`)
3. "I want a second key bound to a command I already have." (arrow keys alongside hjkl is the
   single most common reason to add a binding, per the app's own generated-bindings comment in
   `docs/config-examples/default-config.toml`)

The redesign is three additive, independently-shippable changes that answer exactly those three
questions, all built from primitives that already exist (`Badge`, `Button`, `IconButton`,
`ContentUnavailableViewCompat`'s existing `actionTitle`/`action`, native SwiftUI `List`/`Section`).
**No new shared component is required.** Nothing here touches the mode bar, the filter box, the
composer's fixed widths, or the empty/no-bindings states beyond what's specified.

## 2. Change A — group the browse view by command category

**When:** `query` is empty and the current mode's rows span 2+ categories (see below). Below that
threshold (a small mode like `service` that's 100% "Mode & system") render exactly today's flat
list — grouping four rows into one labeled bucket is chrome that doesn't earn its keep.

**Categories**, derived client-side from the first word of `command` (chained commands — `"focus
left ; layout floating"` — use the verb before the first `;`), fixed order, empty categories
omitted:

| Category | Verbs |
|---|---|
| Focus | `focus`, `focus-monitor`, `focus-back-and-forth` |
| Move & workspace | `move`, `move-node-to-workspace`, `move-node-to-monitor`, `move-workspace-to-monitor`, `workspace`, `workspace-back-and-forth`, `summon-workspace` |
| Layout & resize | `layout`, `split`, `join-with`, `fullscreen`, `resize`, `balance-sizes`, `flatten-workspace-tree`, `macos-native-fullscreen`, `macos-native-minimize` |
| Mode & system | `mode`, `reload-config`, `enable`, `close`, `close-all-windows-but-current`, `volume`, `exec-and-forget`, `trigger-binding`, `config`, `open-settings` |
| Other | anything not in the table above |

This table is exhaustive against `Sources/AppBundle/command/cmdManifest.swift`'s `CmdArgs.Kind`
switch, but "Other" is not a bug bucket to eliminate — the command field is free text with no
validation, so a typo or a future command must still render, just uncategorized. Verify the table
against `cmdManifest.swift` again at implementation time in case commands were added since this
was written.

Rows within a category keep `displayBindings`'s existing key-alphabetical order — no new sort.
Generated and explicit rows interleave within a category exactly as they do today (distinguished
only by the existing `Badge`/Override affordance); category is about *what the binding does*, not
where it lives in the file.

**Header styling** (tab-local — not a new component, following the same reasoning the existing
Key/Command header row used: one caller doesn't clear the bar for a repeating group label used
nowhere else in the window):

- Text: `"\(category) — \(count)"`, e.g. `"Focus — 12"`. Em dash, matching the codebase's existing
  `"Delete "\(mode)" — N bindings"` count convention rather than inventing a new separator.
- Typography: same as the existing Key/Command header — `.caption`/secondary, matching `Table`'s
  own header style (in the JSX: `font: var(--weight-regular) var(--text-subheadline)/1.2
  var(--font-system); color: var(--label-secondary)`).
- No icon. The Key/Command header above has none; matching it keeps the row compact and avoids two
  different header conventions stacked on top of each other.
- No background fill, no bottom border — lighter-weight than the Key/Command header (which keeps
  its existing `--control-bg` + bottom divider) so it reads as "group label inside the list," not
  "second fixed column caption."
- Padding: `9px 14px 4px` (`--space-9 --space-14` top/sides, `--space-4` bottom) — tighter bottom
  than top so the label sits closer to its own rows than to the previous group's last row.
- No disclosure triangle, not collapsible. A collapse feature was considered and cut: with the list
  already scrolling, collapsing buys back vertical space nobody's short on, and the state (expanded
  per category, per mode, persisted or not) is a UI-state design question with no clear answer that
  doesn't fully justify its own weight for v1. Revisit if real usage shows otherwise.

## 3. Change B — surface cross-mode matches while searching

Bindings are **not** conflicts across modes by design — `esc` legitimately means different things
in `main` and `service`. This change is about visibility, not warning, and must not be styled as
one (no orange, no warning icon).

**B1 — current mode has matches.** Below the existing filtered row list, append a second `List`
section (native `Section`, not a new component) titled `"In other modes — \(count)"` (same tab-local
header style as Change A, count = total matching rows summed across every other mode) whenever
`viewModel.allModeNames` other than `selectedMode` contain rows matching the same substring
predicate the tab already applies to `allRows` (key or command contains `query`, case-insensitive —
identical matching, just run against `viewModel.displayBindings(mode:)` for each other mode instead
of the selected one). Iterate other modes in `allModeNames` order (already `main`-first,
alphabetical) so the section order is stable.

Each row in this section is read-only (this section never edits — it's a map, not an editor):

- A `Badge` showing the mode name (reuses `Badge` as-is — it already accepts arbitrary text
  children, no extension needed — e.g. `<Badge tone="muted">service</Badge>`).
- Key, mono, via `KeyNotation.pretty` (or `PrettyKey` in the mockup) — same treatment as an
  existing generated row's key cell.
- Command, mono, secondary — same treatment as an existing generated row's command cell.
- If the row's origin is `.generated`, the existing `Badge("generated", …)` alongside the mode
  badge — identical to how the current conflict banner already shows it.
- A trailing `Button("Go", …)` (borderless, same as the existing `Show` button in the conflict
  banner) that sets `selectedMode` to that row's mode. Leave `query` unchanged — it's already the
  right filter text and now scopes the new mode's row list the moment the mode switches.

**B2 — current mode has zero matches.** Keep using `ContentUnavailableViewCompat` exactly as it
exists today (icon `magnifyingglass`, title `"No matches"`), but compute the same cross-mode match
set as B1 and adjust copy/action only:

- **Zero other-mode matches** (today's behavior, unchanged): message `"Nothing in
  "\(selectedMode)" matches "\(query)"."`, `actionTitle: "Clear filter"`.
- **Exactly one other mode matches:** message `"Nothing in "\(selectedMode)" matches "\(query)".
  It's bound in "\(otherMode)" instead."`, `actionTitle: "Go to "\(otherMode)""`, action switches
  `selectedMode` (query unchanged, same reasoning as B1's Go button).
- **Two or more other modes match:** message `"Nothing in "\(selectedMode)" matches "\(query)". It's
  bound in other modes."`, `actionTitle` stays `"Clear filter"` — jumping to one of several would be
  an arbitrary guess, so don't offer a single-target action.

`messageIsMarkdown: false` in every branch here (mode names and `query` are both arbitrary text that
can contain markdown-special characters — same reasoning the current code already applies to the
plain "No matches" message).

## 4. Change C — cross-mode awareness in the composer

While the composer's key recorder holds a value (`newKey` non-empty), in addition to the existing
same-mode conflict banner (unchanged — exact key match in `selectedMode`, `StatusLabel.Kind.warning`,
"Replace" wording, all as today), check `viewModel.existingBinding(mode:key:)` for every mode in
`allModeNames` other than `selectedMode`. If any match, render one additional line below the
existing conflict banner (or standalone if there's no same-mode conflict):

- `StatusLabel(kind: .neutral)` — not warning. This is not a problem, it's context.
- One other mode: `"Also bound in "\(mode)" mode."`
- Two or more: `"Also bound in "\(a)", "\(b)"\(count > 2 ? ", and \(count - 2) more" : "")
  mode\(count > 1 ? "s" : "")."` — cap the named list at two so a key that's rebound in every mode
  (plausible for something like `esc`) doesn't produce a run-on sentence.
- No action button on this line — it's informational, not a prompt to do anything. (Contrast with
  the warning banner's `Show` button, which exists because that one *is* actionable: it names a
  binding you're about to overwrite.)

This reuses `StatusLabel` with its existing `neutral` kind (already defined in
`components/feedback/StatusLabel.jsx` — no extension needed) and needs one new piece of data-layer
work in Swift: nothing, actually — `existingBinding(mode:key:)` already exists and takes `mode` as a
parameter, so this is a pure View-layer loop over `allModeNames`, identical in shape to the loop B1
already needs.

## 5. Change D — duplicate a binding to a second key

A single `IconButton` (existing component, `components/controls/IconButton.jsx` — no extension)
added to every row, editable and generated alike:

- **Editable row:** order becomes `[KeyRecorderField][SettingsField][IconButton "duplicate"][IconButton
  "remove"]` — duplicate (non-destructive) before remove (destructive), left-to-right escalation.
- **Generated row:** order becomes `[key][command][Spacer][Badge "generated"][IconButton
  "duplicate"][Button "Override"]` — duplicate before Override, since Override is the row's primary
  action and stays rightmost, matching the composer's own primary-action-rightmost convention
  (`Add`/`Replace`).
- Icon: `doc.on.doc` (already mapped in the JSX kit's `SF_TO_LUCIDE`, no new icon needed — it's the
  same symbol Finder and other AppKit apps use for "duplicate").
- Label/tooltip/accessible name: `"Duplicate "\(command)""` — curly-quoting the command, consistent
  with this tab's existing precedent of curly-quoting non-"name" data in a control label (the
  Remove button already quotes the raw key notation the same way).
- Behavior: `newCommand = row.command; newKey = ""` — seeds the composer's command field with the
  row's command and leaves the key recorder empty, ready to record. Does **not** touch `selectedMode`
  or `query`, and does not auto-focus/auto-arm the recorder (that would steal a click the user
  hasn't made yet — they click the recorder same as any other new binding). No new
  `ConfigurationViewModel` method: the composer's existing `add()` handles the rest exactly as it
  does for anything else typed into those two fields.
- Role: not destructive (`role: nil`), same visual weight as the row's other secondary controls.

## 6. Shared component usage — for the reconciliation pass

Everything below is an *existing* component used as-is. Flagging each explicitly per the
instructions, so a collision with another tab's proposal is easy to spot:

- **`Badge`** — reused for mode-name tags in the B1 cross-mode section (`<Badge
  tone="muted">service</Badge>`), in addition to its existing "generated" use in this tab. No prop
  changes; it already accepts arbitrary children.
- **`Button`** (borderless) — reused for the B1 "Go" action, same visual role as the existing "Show"
  button in the conflict banner.
- **`IconButton`** — reused for Change D's duplicate action (`systemImage="doc.on.doc"`, `role`
  omitted/non-destructive). Already used in this tab for Remove; this is a second call site with a
  different `systemImage` and no `role`, not a new variant.
- **`StatusLabel`** — reused for Change C, this time with `kind="neutral"` (map already defines it:
  `equal.circle`, `--label-secondary`) rather than `warning`. First use of `neutral` in this tab;
  worth checking no other tab's proposal is independently inventing a different "informational,
  non-warning inline status" pattern that should collapse into this one.
- **`ContentUnavailableViewCompat`** — reused for B2, only changing its existing `title`/`message`/
  `actionTitle`/`action` argument values per query state. No prop additions.
- Native SwiftUI `List` + `Section` — used for Change A's category grouping and Change B1's
  supplementary section. Not a `SettingsChrome` component (same category as `BarStrip`/`TabBar` per
  the design system's "these are SwiftUI/AppKit constructs" note) — nothing to build, but flagging
  since this is the first *repeating, collapsible-candidate* grouped-list pattern in the window. If
  another tab (Window Rules, Callbacks) independently proposes grouped/sectioned lists for their own
  long lists, that's a real candidate for a future shared convention — not proposed here since one
  call site doesn't justify promoting a pattern.
- **No new component.** Nothing in this proposal needs an addition to `SettingsChrome.swift`
  (Swift) or a new file under `components/` (JSX).

## 7. Fit at 780×520

- **Change A** (category headers) and **Change B1** (cross-mode section) both render *inside* the
  existing scrollable `List` — they add rows to content that already scrolls, not new fixed-height
  chrome. The mode bar, Key/Command header, and composer keep their exact current heights.
- **Change B2** reuses `ContentUnavailableViewCompat` at its existing size; only text and the action
  button's label/target change, never its layout.
- **Change C** adds at most one more capped-length, single-line `StatusLabel` below the existing
  conflict banner — same category of conditional content the fixed floor already accounts for
  (today's conflict banner is itself conditional and already budgeted). Total composer-area growth
  in the worst case (both banner and neutral line showing) is one line, ~15-18pt — well inside the
  slack `SettingsHint`'s existing 2-line cap and `.help()` fallback already protect.
- **Change D** adds one 22px `IconButton` (plus its 8px row gap) per row, horizontally. Both row
  layouts already have a flexible middle element — `SettingsField`/the command text — that
  compresses under width pressure exactly as the filter box already does at 780pt per the existing
  code comments; a fixed ~30pt addition here is small next to that slack and doesn't change the
  170px recorder/key column or add a new fixed-width element.
- Verified against the two stress cases named in the brief:
  - **40-80 bindings, one mode:** Change A's category buckets turn one 40-80-row wall into 3-5
    labeled runs of ~10-25 rows each — same total scroll length, better scan structure. No height
    added.
  - **Multiple modes:** Change B1/B2/C are the parts that specifically target this case; all three
    are additive/conditional as described above, none widen the mode bar or filter box (both
    already fixed by the prior round's `.fixedSize()`/`maxWidth` work, untouched here).

No change in this proposal adds width or height to any always-visible element, so the 780×520 floor
holds under the same reasoning the prior consistency pass already verified for this tab.
