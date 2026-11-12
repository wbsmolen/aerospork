# Gaps tab — redesign proposal

Author: UI Designer (Gaps tab)
Scope: `Sources/AppBundle/ui/ConfigurationTabs/GapsSettingsTab.swift` and its mockup counterpart
`.claude/skills/aerospork-design/ui_kits/settings_app/GapsTab.jsx`. Nothing outside this tab's
content pane.

## 1. Summary

The current tab is already close to right: a live preview, two grouped sections, six
`NumberField`s. The redesign keeps that shape and does two things:

1. **Compact-by-default editing.** Four of the six gap numbers (outer) and two of them (inner)
   are, in the overwhelming common case, all the same value — the shipped default config is
   `inner = 8`, `outer = 8`. Today the tab always shows all six fields, so the common case pays
   the same six-field tax as the rare one. Add one "same value" toggle per group; when the
   group's values already match, the tab shows a single compact field instead of two or four.
   Switching the toggle off always still exposes full per-edge control — nothing about
   editability is removed, only the default presentation of the common case gets smaller.
2. **Precise, honest disclosure of the Raw-TOML boundary**, replacing a single static sentence
   that says the same thing whether or not it's currently true. A new read-only signal on the
   view model reports whether *any* of the six gaps currently carries a per-monitor rule; when
   it does, the preview section grows a `StatusLabel` that says so, in addition to (not instead
   of) the permanent footer that teaches the capability exists at all.

Both changes are assembled entirely from existing shared components (`Toggle`, `NumberField`,
`StatusLabel`, `FormSection`/`Section`+`SectionLabel`, `SettingsFooter`) used in combinations
already established elsewhere in the window. No shared component's contract changes. See §3.

Deliberately **not** proposed: per-monitor editing in the structured UI, moving `accordionPadding`
here from `GeneralSettingsTab` (it's a gap-adjacent value but it lives in another designer's tab —
out of my remit for the same reason the tab shell itself is out of scope), or any interactive/
draggable version of the preview graphic (the design system is explicit that AeroSpork has no
custom control skin and nothing in the shipped UI is a drag surface; a click-to-edit preview would
be a new interaction paradigm invented for one tab, not a consistency improvement).

## 2. Specific changes

### 2a. Preview section — structure unchanged, new conditional footer

No visual change to `GapsPreview` itself or its `Section` header (`SectionLabel("Preview", "eye")`
was already fixed in the prior pass — fill `0.045`, stroke `0.16` — leave as-is).

Add a **conditional `footer`** to that `Section`, shown only when the new
`viewModel.gapsHavePerMonitorOverrides` signal (§3) is `true`:

```swift
Section {
    GapsPreview(...).frame(height: 156).padding(.vertical, 4)
} header: {
    SectionLabel("Preview", "eye")
} footer: {
    if viewModel.gapsHavePerMonitorOverrides {
        StatusLabel("Some of these gaps have per-monitor rules set in Raw TOML — editing any value below replaces the whole section with flat numbers.", kind: .neutral)
    }
}
```

This reuses `StatusLabel(kind: .neutral)` exactly as `RawTomlTab.swift` already does for
"Matches the file on disk" — an inline, non-error state readout, not a new alert style. It says
nothing when there's nothing to say: a config with no per-monitor gaps shows no footer here at
all, so the tab doesn't manufacture anxiety about a feature the user isn't using.

Copy note: singular/plural doesn't need handling since the sentence is written to be true for any
count ≥ 1 ("some of these gaps") rather than counting exactly how many — simpler than a "1 of 6" /
"3 of 6" construction and avoids a grammar-agreement edge case for no real loss of usefulness.

### 2b. "Between windows" section (inner gaps)

Add one `Toggle` as the first row, before the number field(s):

```swift
Section {
    Toggle("Same value for both", isOn: $innerGapsLinked)
    if innerGapsLinked {
        NumberField("Horizontal & vertical", value: linkedInnerBinding)
    } else {
        NumberField("Horizontal", value: viewModel.binding(\.innerGapsHorizontal))
        NumberField("Vertical", value: viewModel.binding(\.innerGapsVertical))
    }
} header: {
    SectionLabel("Between windows", "rectangle.split.2x1")
}
```

`innerGapsLinked` is a **local `@State private var` on `GapsSettingsTab`, not a config field** —
it controls presentation only, the same way e.g. an armed key-recorder's highlight is transient
view state elsewhere in this window. It is **seeded once**, when the tab loads (`.task`/`.onAppear`,
alongside the existing `viewModel.loadConfiguration()` call), from whether the loaded values
already match: `innerGapsLinked = (viewModel.innerGapsHorizontal == viewModel.innerGapsVertical)`.
It must **not** be a continuously-recomputed derived value — if it were, typing into "Vertical"
until it happens to equal "Horizontal" would make that row disappear out from under the user
mid-edit. The toggle is a manual mode switch the user controls, not an auto-detector.

`linkedInnerBinding` is a composed `Binding<Int>` local to the tab: `get` reads
`viewModel.innerGapsHorizontal`, `set` writes the new value to *both*
`viewModel.innerGapsHorizontal` and `viewModel.innerGapsVertical` through the existing
`viewModel.binding(\.)` setters (so it still goes through `markAsModified()` +
`scheduleAutoSave()` — same 600ms debounce as every other field, no new timing model).

Turning the toggle **on** while the two values currently differ snaps both to the current
`innerGapsHorizontal` value immediately (visible, not hidden — the user just took the action that
caused it, and can turn the toggle back off to see and re-diverge the values; no confirmation
dialog, consistent with this window having no toasts/modals for reversible actions). Turning it
**off** changes nothing; it only exposes the two rows again.

### 2c. "Around the screen" section (outer gaps)

Same pattern, four-wide instead of two-wide:

```swift
Section {
    Toggle("Same on all sides", isOn: $outerGapsLinked)
    if outerGapsLinked {
        NumberField("All sides", value: linkedOuterBinding)
    } else {
        NumberField("Top", value: viewModel.binding(\.outerGapsTop))
        NumberField("Bottom", value: viewModel.binding(\.outerGapsBottom))
        NumberField("Left", value: viewModel.binding(\.outerGapsLeft))
        NumberField("Right", value: viewModel.binding(\.outerGapsRight))
    }
} header: {
    SectionLabel("Around the screen", "rectangle.inset.filled")
} footer: {
    Text("The top gap is measured below the menu bar, so 0 is flush with the usable area.")
}
```

`outerGapsLinked` seeded once from `outerGapsTop == outerGapsBottom && outerGapsBottom ==
outerGapsLeft && outerGapsLeft == outerGapsRight`. `linkedOuterBinding` writes all four outer
fields on set, same debounce mechanism as above.

Keep the existing footer sentence about the menu bar unconditionally — it stays true and
low-cost to show whether the row it refers to ("Top") is currently visible as its own field or
folded into "All sides"; splitting it into a conditional would be complexity for no real gain.

### 2d. Bottom `SettingsFooter` — tightened, general-education role

Change the permanent footer text. It no longer needs to carry the specific warning (that job now
belongs to the conditional `StatusLabel` in §2a, which only appears when there's something
concrete to warn about); its job becomes teaching the capability to someone who has never used it:

```swift
SettingsFooter(
    "Raw TOML can set a different value per monitor for any of these six gaps. Editing a gap here always writes one flat number for every monitor. Use Raw TOML for per-monitor rules.",
)
```

Three short sentences instead of one long one with an em dash and an inline backtick example —
keeps the existing lesson (SwiftUI's markdown parser breaks on `[` inside backticks) moot by not
using backticks at all here, rather than working around it.

## 3. Shared components used or extended

**Used as-is, no contract change:**
- `SectionLabel`, `FormSection`/`Section` header+footer, `NumberField`, `SettingsFooter` — same
  signatures as today.
- `Toggle` — already takes `(label, isOn/checked, ...)` in both Swift and the JSX kit
  (`components/controls/Toggle.jsx`); this is its first use in the Gaps tab but not a new shape.
  It renders its own label + switch row, so it is used directly as a `Section` row, not wrapped in
  `LabeledContent`.
- `StatusLabel(kind: .neutral)` — already exists and already has exactly this "informational,
  not a validity problem" precedent in `RawTomlTab.swift`. No new `Kind` case, no new icon param
  (Swift's `StatusLabel` fixes the icon to `kind`, with no override — the JSX mock's optional `sf`
  prop is mock-only flexibility that must **not** be used here, to stay accurate to what Swift can
  actually render).

**Not used:** `Badge`. I considered a per-field "this one has a per-monitor override" badge
(mirroring `KeyBindingsTab`'s "generated" provenance badge) before this design, but the actual
write behavior (`ConfigurationWriter.replaceGaps`, gated by `ConfigurationViewModel.gapsEdited`)
rewrites the *entire* `[gaps]` section — all six values — on any single edit, not just the field
touched. Six independent per-field badges would misrepresent that as six independent risks when
it's really one section-wide one; a single signal is both simpler and more accurate to the real
mechanics.

**New, tab-local (not shared-component) state:**
- `GapsSettingsTab`: two `@State private var` bools (`innerGapsLinked`, `outerGapsLinked`) and two
  composed `Binding<Int>` (`linkedInnerBinding`, `linkedOuterBinding`). Tab-local view state, not
  reusable chrome — no reason to promote to `SettingsChrome.swift`, and nothing about it is generic
  across tabs the way `IconButton`/`PanelHeader` were.
- `ConfigurationViewModel`: one new read-only field, `@Published private(set) var
  gapsHavePerMonitorOverrides = false`, computed inside `reloadFromConfig()` alongside the existing
  six `gapValue(...)` calls:
  ```swift
  gapsHavePerMonitorOverrides = [
      config.gaps.inner.horizontal, config.gaps.inner.vertical,
      config.gaps.outer.top, config.gaps.outer.bottom, config.gaps.outer.left, config.gaps.outer.right,
  ].contains { if case .perMonitor = $0 { true } else { false } }
  ```
  Deliberately **outside** `LoadedSnapshot`/`currentGaps`/`gapsEdited` — it is a display-only
  projection recomputed on every load/reload, never diffed against and never itself editable, so it
  cannot interact with the writer's edit-detection or the byte-identical-no-op-save invariant.

Because both new pieces are additive and tab/view-model-local, there's nothing here for the
cross-tab reconciliation pass to collide with — no shared `.jsx` component's props change shape.

## 4. Fits at 780×520

Nothing here changes horizontal geometry: `NumberField`'s fixed 58px input and `Toggle`'s fixed
38px switch are unchanged and used at their existing sizes; the preview keeps its existing
`frame(height: 156)` and scales its internal geometry off the container width exactly as today
(`GeometryReader` + `nominalWidth = 1600` ratio), so it degrades the same way it already does
toward the 780px floor.

Vertically, the worst case (both groups unlinked — i.e., a user with genuinely asymmetric gaps,
who was already seeing all six rows today) adds exactly two rows total versus the current tab: one
`Toggle` row in "Between windows," one in "Around the screen." The best case (a default or
uniform-gap config, which is what ships) is *more* compact than today: two sections collapse from
2+4=6 number-field rows down to 1+1=2 plus the two toggle rows, net smaller. Either way this is a
`Form`/`ScrollView`-backed list, not a fixed-height layout — it already scrolls past two sections
today when needed, so a worst-case +2 rows has no overflow risk at the 520px floor; it's a taller
scroll, not a broken one. The conditional `StatusLabel` in §2a is one line, shown only when
relevant, and replaces zero existing content.

## 5. Per-monitor editing boundary — explicit confirmation

I did **not** propose full per-monitor gap editing in the structured Gaps tab. The tab still edits
exactly six flat `Int`s, exactly as it does today; `DynamicConfigValue<Int>`'s `.perMonitor` case
remains reachable only through Raw TOML, per the writer invariant in `CLAUDE.md`.

How the boundary is communicated changed from one static sentence to two complementary,
context-appropriate signals:
- A **permanent, low-key footer** (§2d) that teaches the capability exists at all, for a user who
  has never touched Raw TOML and has no per-monitor rules to lose — always present, never alarming.
- A **conditional, specific notice** (§2a) that appears only when the config *currently has*
  per-monitor rules that a structured edit would flatten — precise instead of hypothetical, and
  gone entirely for the common case where it would just be noise. This is the more honest version
  of "maximum customizability": it doesn't add editing power the config format can't safely
  round-trip through this UI, but it makes sure nobody discovers the flattening behavior by losing
  a Raw TOML rule they forgot they'd written.
