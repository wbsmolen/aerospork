# Settings GUI — visual-language proposal

Scope: the seven tabs under `Sources/AppBundle/ui/ConfigurationTabs/` plus
`Sources/AppBundle/ui/SettingsChrome.swift`, checked against the documented visual language in
`.claude/skills/aerospork-design/` (`readme.md` and `tokens/*.css`, which were themselves derived
from this Swift, so a mismatch is either drift in the Swift or a gap in the docs — both are called
out below). Bounded consistency pass, not a rewrite; ideas are tagged **safe — ship this pass** or
**bigger swing** per the brief so a human can curate.

The audit was more clean than dirty. Before the findings, what passed and doesn't need touching:

- **Spacing.** Every literal `.padding(...)` value across all seven tabs (grepped exhaustively)
  is a member of the documented scale `{1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16, 24}`
  (`tokens/spacing.css`). No tab invents an arbitrary number. `KeyBindingsTab.swift:119-120`'s
  filter-pill padding (`7, 4`) and `WorkspacesMonitorsTab.swift:68-69`'s card padding (`12, 9`)
  match their documented aliases (`--space-7`, `--pad-card-y`) exactly.
- **Corner radii.** Every `RoundedRectangle(cornerRadius:)` in the seven tabs is a member of
  `{4, 5, 6, 8, 10}` (`tokens/radius.css`), and each is used for the surface class the token names:
  4 for the gaps-preview tile, 6 for the filter field, 8 for card/row surfaces (the monitor row, the
  gaps-preview screen). `KeyBindingsTab.swift`'s filter pill (6) and `WorkspacesMonitorsTab.swift`'s
  monitor-row card (8) — the two the brief flagged for comparison — are each correctly using the
  radius for *what kind of surface they are*, not drifting from each other.
- **Hardcoded status color.** Zero instances of `Color.red`/`.green`/`.orange`/etc. outside
  `StatusLabel.Kind`/`Banner.Kind` anywhere in the seven tabs. The shared-chrome invariant is
  holding for color.
- **Typography scale.** Zero hardcoded `.font(.system(size: N))` pixel sizes in any tab file; every
  text style is a semantic SwiftUI style (`.body`, `.callout`, `.headline`, …) that resolves to the
  documented scale. One real deviation exists, but it's in `SettingsChrome.swift`, not a tab —
  see Finding 3.

Three real findings below, in order of how load-bearing they are for a mockup builder to fix.

---

## Finding 1 — an orphan fill opacity in the gaps preview

**What's inconsistent.** `GapsSettingsTab.swift:77-78`:

```swift
RoundedRectangle(cornerRadius: 8, style: .continuous)
    .fill(Color.primary.opacity(0.05))
```

The design system's "schematic/inert shape" fill is a closed set of exactly three opacities, each
tied one-to-one to a surface — `tokens/colors.css:41-43`:

```css
--fill-subtle: rgba(0, 0, 0, 0.045);   /* monitor rows */
--fill: rgba(0, 0, 0, 0.06);           /* filter field */
--fill-strong: rgba(0, 0, 0, 0.08);    /* "generated" badge capsule */
```

`WorkspacesMonitorsTab.swift:70` (monitor row) uses `0.045` and `KeyBindingsTab.swift:121` (filter
pill) uses `0.06` — both correctly drawn from that set. The gaps-preview screen background at `0.05`
is a fourth, unlisted value: close enough to `0.045` to read as a rounding slip, not a deliberate
fourth tier. It's also the *only* card-radius (8pt) surface using an ink wash that doesn't match
`WorkspacesMonitorsTab`'s card-radius surface, even though both are "a faint ink-wash rectangle at
radius 8."

While in that file, the screen's stroke — `GapsSettingsTab.swift:80`,
`.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)` — is also a one-off: it doesn't match
the documented hairline (`--separator: rgba(0,0,0,0.1)`, "10% black / 15% white" per `readme.md:127`)
or the documented control border (`--border-control: rgba(0,0,0,0.16)`), and because `Color.secondary`
already carries its own baked-in opacity (~50% in light appearance), stacking `0.35` on top produces
an effective tone that doesn't correspond to any named token.

**Why it matters.** This is the one place in the settings window where the fill palette the rest of
the UI is disciplined about quietly drifts. It's small (0.05 vs 0.045 is not perceptible on its own),
but it's exactly the kind of value a future tab would copy-paste as precedent, widening the palette
from three opacities to four for no reason.

**Proposed fix.**
- `GapsSettingsTab.swift:78`: change `Color.primary.opacity(0.05)` → `Color.primary.opacity(0.045)`
  (i.e., reuse `--fill-subtle`, matching the monitor row's card-radius surface).
- `GapsSettingsTab.swift:80`: change `Color.secondary.opacity(0.35)` →
  `Color.primary.opacity(0.16)` (i.e., reuse `--border-control`, the documented control-border tone),
  or `.secondary` at the framework default with no extra `.opacity()` modifier if the intent was
  just "a faint hairline" rather than a control-style border.

**Tag: safe — ship this pass.** Two-line diff, no layout or behavior change, brings the file's own
tokens back to the documented three-value set.

---

## Finding 2 — CallbacksTab tints an icon for emphasis, not status

**What's inconsistent.** `CallbacksTab.swift:96-108`, its own private helpers, side by side:

```swift
private func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) { Label(title, systemImage: "plus.circle") }
        .buttonStyle(.borderless)
        .foregroundStyle(Color.accentColor)          // <- accent
}

private func removeButton(_ action: @escaping () -> Void) -> some View {
    Button(role: .destructive, action: action) { Image(systemName: "minus.circle") }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)                  // <- monochrome, correct
        .help("Remove")
        .accessibilityLabel("Remove")
}
```

The icon shapes are fine — `plus.circle` for an inline add, `minus.circle` for an inline remove,
which is the same family `KeyBindingsTab.swift:169` uses for its own per-row remove
(`Image(systemName: "minus.circle")`). The problem is the tint: `addButton` colors both its icon
*and its text label* in `Color.accentColor`. `readme.md:174-176` is explicit: "icons are monochrome
and inherit the text colour; they are tinted only to carry a status (red/orange/green)." Add is not
a status. This is the only accent-tinted icon anywhere in the seven tabs — grepped for
`foregroundStyle` and `foregroundColor` across every tab, this is the sole hit that isn't `.secondary`,
`.tertiary`, or a `StatusLabel.Kind`/`Banner.Kind` tint.

It's also an internal contradiction: the two functions sit nine lines apart, form a symmetric
add/remove pair, and only one of them follows the monochrome rule the other one is written to. And
separately, `KeyBindingsTab.swift:169-172`'s own per-row remove button sets no `foregroundStyle` at
all, so it falls back to the button's default tint — which on macOS is not guaranteed to render as
neutral gray the way `CallbacksTab`'s explicit `.secondary` does. Three call sites, three different
answers to "what color is a per-row minus.circle button," for what should be one answer.

**Why it matters.** Accent color is the one non-monochrome signal AeroSpork's UI reserves for
"this is interactive and important" (the armed key recorder, the accent-colored tile in the gaps
preview). Spending it on an ordinary "add a row" button dilutes that signal and is the kind of thing
that reads as a UI kit inconsistency the moment two tabs are open side by side — Callbacks' add
button will visually pop in a way nothing else in the window does.

**Proposed fix.**
- `CallbacksTab.swift:99`: delete `.foregroundStyle(Color.accentColor)`. Let it inherit the default
  borderless-button tint like every other `+`/`add` affordance in the window (`ListActionBar`'s plain
  `plus`, no color override).
- `KeyBindingsTab.swift:169-172`: add `.foregroundStyle(.secondary)` explicitly, matching
  `CallbacksTab`'s (corrected) `removeButton`.

**Tag: safe — ship this pass.** One line deleted, one line added, no layout change.

See also the SettingsChrome proposal below — this pair of buttons is independently reinvented in two
files and is worth centralizing while it's being fixed anyway.

---

## Finding 3 — a free-floating section header padded three different ways

**What's inconsistent.** Three call sites, one visual pattern — "a `SectionLabel` used as a panel
header outside a `Form`, with its own manual padding" — three different padding tuples
(horizontal / top / bottom):

| Call site | Horizontal | Top | Bottom |
|---|---|---|---|
| `WorkspacesMonitorsTab.swift:32-35` ("Connected monitors") | 16 | 14 | 8 |
| `WorkspacesMonitorsTab.swift:83-86` ("Workspace assignments") | 16 | **12** | 8 |
| `WindowRulesTab.swift:26-28` ("Rules") | **14** | **10** | **10** |

Every one of these values is individually a legal member of the documented spacing scale — that's
why the padding grep at the top of this doc reads as "clean." But the same tab
(`WorkspacesMonitorsTab.swift`) doesn't even agree with *itself* between its two section headers (14pt
top vs. 12pt top), and `WindowRulesTab.swift`'s version disagrees with both on all three axes. This
is exactly the "two badges at two paddings" failure mode `SettingsChrome.swift`'s file comment
describes — it just wasn't caught for `SectionLabel`-as-panel-header because each Form-based tab gets
this spacing for free from `.formStyle(.grouped)`, so it was only ever handwritten in the two tabs
(`WorkspacesMonitorsTab`, `WindowRulesTab`) that *aren't* built on `Form`.

**Why it matters.** Monitors and Window Rules are the two tabs with a custom (non-Form) top-level
layout, and this header is the first thing the eye lands on in both. A 2-4pt difference in top
padding between "Connected monitors" and "Workspace assignments" — stacked in the same window, one
above the other — is small but is the kind of thing that reads as "slightly off" without anyone being
able to say why.

**Proposed fix.** Standardize on `horizontal: 16, top: 14, bottom: 8` (the first `WorkspacesMonitorsTab`
call site) — 16 matches `--space-16` / `--pad-section-x`, the same horizontal inset a `Form` gives its
sections for free, so a non-Form tab's header lines up with a Form tab's section header if the user
flips between tabs. Apply it at all three call sites.

**Tag: safe — ship this pass** for the padding fix itself. Promoting it to a shared primitive (below)
is the accompanying **bigger swing**, since it touches three call sites across two files instead of
editing numbers in place.

---

## Finding 4 (secondary) — the monitor row's icon is the largest inline glyph in the window

**What's inconsistent.** `WorkspacesMonitorsTab.swift:49-52`:

```swift
Image(systemName: "display")
    .font(.title2)              // 17px — the top of the documented inline range
    .foregroundStyle(.secondary)
    .frame(width: 26)
```

This is *technically* within the documented iconography rule ("12-17px inline," `readme.md:160-161`)
— `tokens/typography.css:14` even names it explicitly: `--text-title2: 17px; /* the monitor glyph in
the Monitors tab */`, so this was a deliberate, documented choice, not drift. Flagging it anyway
because of where it sits: the `SectionLabel("Connected monitors", "display.2")` header directly above
it (`WorkspacesMonitorsTab.swift:32`) renders its own icon at `.headline` size (13px, per
`SettingsChrome.swift:214-217`). So the row content's icon (17px) is visually larger than the section
header's icon (13px) that titles it — a minor hierarchy inversion. Every other icon that leads a row
of text in the seven tabs (`RawTomlTab.swift:32`'s `doc.plaintext`, `KeyBindingsTab.swift:98`'s
`magnifyingglass`) inherits the surrounding text's size rather than taking an explicit oversized
`.font()`, so this is also the only "row-leading icon" in the window that opts out of that pattern.

**Why it matters.** Judgment call, not a bug — the icon is legible and on-brand, and it's the one
tab where "which physical monitor is this" benefits from a slightly more prominent glyph. Worth a
second look precisely because it's a deliberate one-off with no comparison point; it's easy for that
kind of one-off to look like an oversight to the next person editing this file.

**Proposed fix (if pursued).** Drop to `.title3` (15px) to sit between the section header (13px) and
its current size, or keep `.title2` but size the `SectionLabel` icons in this tab up to match — do not
do both independently. If keeping the current size, add a one-line comment at the call site
explaining the choice (the token file's comment doesn't travel to the Swift source), so it reads as
intentional in the file that actually ships.

**Tag: bigger swing** (design judgment, not a clear violation — safe to leave as-is if the human
disagrees).

---

## Finding 5 (secondary) — the raw-TOML editor's font size has no token

**What's inconsistent.** `SettingsChrome.swift:376`:

```swift
textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
```

Every other monospaced "code-like" text in the seven tabs renders at the 13px body size via the
semantic style `.font(.system(.body, design: .monospaced))` — `GeneralSettingsTab.swift:89` (version
string), `KeyBindingsTab.swift:175,181` (key/command rows), `WindowRulesTab.swift:58,71` (table
cells). `CodeEditor` is an `NSViewRepresentable`, so it can't reach for the SwiftUI semantic style —
but the file already has the right pattern to reach for instead: `KeyBindingsTab.swift:447-449`'s
key-recorder drawing code uses `NSFont.systemFontSize` (the AppKit equivalent of 13px,
`--text-default` in `typography.css:17`) rather than a literal number. `CodeEditor`'s `12` is a bare
magic number with no semantic anchor — not `NSFont.systemFontSize`, not `NSFont.smallSystemFontSize`
(11), just `12`.

**Why it matters — with a caveat.** This might be entirely correct: monospaced glyphs read visually
heavier than proportional text at the same point size, and a dense code editor at 12px next to 13px
prose elsewhere is a completely normal typographic choice (Xcode's own default editor size is smaller
than its UI chrome). The problem isn't necessarily the number — it's that nothing documents it as a
choice. `tokens/typography.css` has no `--text-code-editor` entry; the 12 in the source reads
identically to whether someone measured "what looks dense enough" once and never named it, or someone
mis-copied `13` and slipped a key. A mockup builder hitting this file today has no way to tell which.

**Proposed fix.** Either:
- (a) Keep `12`, but add a token — `--text-code-editor: 12px;` in `typography.css`, with a comment
  explaining the deliberate one-step-down-from-body sizing for code density — and a matching Swift
  comment at the call site so the rationale survives outside the design-system repo, or
- (b) Change it to `NSFont.systemFontSize` (13) to match every other monospaced text element in the
  window, if the smaller size wasn't a deliberate call.

This proposal doesn't pick between (a) and (b) — that's a real design decision, not a consistency bug
— but *not documenting whichever one is chosen* is the part worth fixing regardless.

**Tag: bigger swing** (needs a decision, not just a value swap).

---

## Proposed addition to `SettingsChrome.swift`

**`PanelHeader`** (or similar name) — a `SectionLabel` pre-wrapped with the padding from Finding 3
(`horizontal: 16, top: 14, bottom: 8`), for a tab whose top-level layout isn't a `Form` and therefore
doesn't get section-header spacing for free.

**Justification (≥2-tab reinvention, per the bar this proposal is held to):** the exact pattern —
`SectionLabel` immediately followed by hand-written `.padding(.horizontal:).padding(.top:).padding(.bottom:)`
— appears independently at three call sites across two files (`WorkspacesMonitorsTab.swift:32-35`
and `:83-86`; `WindowRulesTab.swift:26-28`), each with different numbers (Finding 3's table above).
That's the shared-chrome file's own stated failure mode — "a tab needs a small piece of chrome, does
not find it, and grows its own" — caught in the act a second time, for a primitive one level up from
what `SectionLabel` alone covers.

**Secondary candidate — `RowRemoveButton`:** `CallbacksTab.swift:102-108`'s `removeButton()` (used at
two call sites in that file: command rows and env-var rows) and `KeyBindingsTab.swift:169-172`'s
inline row-remove button are the same primitive — `minus.circle`, `.borderless`, secondary tint,
`help`/`accessibilityLabel` set to a "Remove …" string — independently written twice, with the tint
and `role: .destructive` diverging exactly as described in Finding 2. Worth folding into
`SettingsChrome.swift` as a small `RowRemoveButton(help:accessibilityLabel:action:)` while fixing
Finding 2 by hand anyway, rather than fixing the two call sites in place and leaving the next tab to
reinvent a third copy. Only proposing this as a secondary candidate (not promoting to the same
confidence as `PanelHeader`) because two call sites is the bar, not comfortably past it, and the
existing `ListActionBar` already owns the *other* half of "add/remove a row" for table-selection
contexts — a third small component here is worth a human's judgment on whether it's one component too
many for what it saves.

**Not proposing** a shared "add row" component to pair with it: `CallbacksTab`'s `addButton()` has no
independent second implementation anywhere else in the seven tabs (its two call sites are both inside
the same file, already sharing the one private function), so it fails the ≥2-tab bar on its own. Fix
Finding 2's tint in place; revisit extraction only if a future tab needs the same "add a row inline"
affordance.

---

## Summary for the curator

| # | Finding | File(s) | Tag |
|---|---|---|---|
| 1 | Orphan fill/stroke opacities in the gaps preview | `GapsSettingsTab.swift:78,80` | safe |
| 2 | Accent-tinted add icon breaks the "tint = status only" rule | `CallbacksTab.swift:99`, `KeyBindingsTab.swift:169` | safe |
| 3 | Free-floating section header padded 3 different ways | `WorkspacesMonitorsTab.swift:32-35,83-86`, `WindowRulesTab.swift:26-28` | safe (padding fix) / bigger swing (extraction) |
| 4 | Monitor-row icon outweighs its own section header | `WorkspacesMonitorsTab.swift:49-52` | bigger swing |
| 5 | Undocumented magic-number font size in the code editor | `SettingsChrome.swift:376` | bigger swing |
| — | New primitive: `PanelHeader` | justified by Finding 3 (3 call sites, 2 files) | bigger swing |
| — | New primitive (secondary): `RowRemoveButton` | justified by Finding 2 (2 call sites, 2 files) | bigger swing |

Everything not listed above — spacing scale, corner-radius scale, hardcoded status color, hardcoded
pixel typography — was checked across all seven tabs and found consistent with both the documented
design system and with each other.
