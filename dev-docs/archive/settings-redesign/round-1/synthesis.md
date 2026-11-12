# Settings GUI redesign — synthesis

Reconciles `proposal-architecture.md`, `proposal-visual.md`, `proposal-a11y.md`,
`proposal-whimsy.md`, and the adversarial cross-critique in `review.md` into one direction. This
is the spec Stage 2.5 (the mockup builder) implements into
`.claude/skills/aerospork-design/ui_kits/settings_app/*.jsx`. Tie-break rationale is included
inline wherever two proposals disagreed, since that's the part a future reader can't reconstruct
from the mockup alone.

## Pulled out of this pass entirely

**`WorkspacesMonitorsTab` row-selection fix.** The a11y proposal's Finding 1, independently
re-verified by the cross-critique reviewer, found that the assignments `Table`'s two columns are
both fully occupied by a focusable control (`SettingsField`, `Picker`), leaving no cell space for
a click to reach the `Table`'s own row-selection handler — a functional bug, not a cosmetic one,
since it would make `ListActionBar`'s Remove permanently unreachable by any input method. This
doesn't belong in a visual-consistency mockup review; it's already been diagnosed, fixed, and
adversarially reviewed directly in Swift (`WorkspacesMonitorsTab.swift`), following the same
process as Part A. See that diff and its review for detail — not reflected in the mockup below
beyond the new inert leading column, which the mockup builder should mirror for visual parity
since it's now real production layout.

**Non-visual accessibility and copy fixes.** `.help()` tooltips, `.accessibilityLabel()`
corrections, VoiceOver announcements, and hit-target sizing don't render as anything different in
a static JSX mockup — there's nothing for you to look at that would change. These are listed below
under "Swift-only — not in the mockup" so the eventual Swift-implementation pass picks them up,
but Stage 2.5 should not spend effort trying to represent them visually.

**Explicitly dropped, not deferred:**
- Architecture's self-flagged "convert `CallbacksTab` to a `List`-backed pattern" idea — the
  proposal recommends against it itself, and it's the one idea across all four documents that
  reads as tab restructuring rather than consistency.
- a11y's `RecorderView` font-scaling work and the `settingsAnnounce`/`AccessibilityNotification`
  pattern — both introduce infrastructure (system text-size tracking, a status-announcement
  convention) that doesn't exist anywhere else in this window yet. That's new capability, not
  bringing an outlier in line with an established pattern, so it's out of scope for a consistency
  pass. Worth a dedicated future pass, not folded in here.
- Visual's Finding 4 (monitor-row icon size vs. its section header) — a documented, in-range,
  deliberate choice per the design tokens. Leaving as-is; not worth the churn.

## Resolved conflicts

**`RowRemoveButton` vs. `IconButton` — collapsed into one primitive.** Architecture and visual
both independently proposed a `RowRemoveButton`, with incompatible signatures; a11y separately
proposed a more general `IconButton` that strictly subsumes it. Adopting `IconButton` only —
building two overlapping "icon button with mandatory label" primitives into `SettingsChrome.swift`
in the same pass would be the exact failure mode that file exists to prevent.

```swift
struct IconButton: View {
    let systemImage: String
    let label: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) { Image(systemName: systemImage) }
            .buttonStyle(.borderless)
            .help(label)
            .accessibilityLabel(label)
    }
}
```

Remove-button call sites use `IconButton(systemImage: "minus.circle", label: "Remove …", role:
.destructive, action:)`. This is a deliberate, called-out behavior change for
`KeyBindingsTab.swift:169-172`, whose current button has no `role` set — adding `.destructive` is
correct (it does destroy a row) but should land as a named decision, not ride along silently in a
mechanical refactor.

**Remove-button label wording — whimsy's curly-quote convention wins.** Three proposals rewrote
`CallbacksTab`'s generic `"Remove"` label three different ways. Adopting whimsy's, since the
cross-critique confirmed it's the only one of the three that follows the design system's own
documented rule ("Curly quotes around user-supplied names: `Leave "service" mode`"):

- Env var row: `row.name.isEmpty ? "Remove variable" : "Remove "\(row.name)""`
- Command row: `row.command.isEmpty ? "Remove command" : "Remove "\(row.command)""`
- `KeyBindingsTab`'s existing `"Remove \(b.key)"` gains the same quoting for consistency now that
  it's going through the shared component: `"Remove "\(b.key)""`.

**Non-Form `SectionLabel`-as-panel-header padding — visual's numbers win.** Architecture and
visual both targeted the same three call sites with opposite end states, both tagged "safe."
Adopting visual's `horizontal 16 / top 14 / bottom 8`: the cross-critique found it's the only one
of the two that resolves all three padding axes into full consistency (architecture's fix leaves
`bottom` unaddressed), and its anchor is the more direct one — 16pt matches what a `Form` section
header gets for free from `.formStyle(.grouped)`, so a non-Form tab's header lines up with a
Form-tab's header if a user flips between tabs. This becomes the new `PanelHeader` component's
fixed padding.

**Pinned bar-strip padding — architecture's finding stands, unaffected by the above.** This is a
different chrome category (pinned top/bottom toolbar/action strips, not section headers), so no
conflict with the panel-header decision. Standardize to horizontal 14 / vertical 9, matching the
documented value and the majority of existing call sites: `RawTomlTab.swift`'s path bar (8→9) and
action bar (10→9), `ListActionBar`'s horizontal padding (12→14). Leave `ListActionBar`'s vertical
7/7-or-3 values alone — that's the documented, intentional +/-row exception.

**`CodeEditor`'s font size — resolved, not left open.** Visual flagged `SettingsChrome.swift`'s
`CodeEditor` using a bare `12` with no semantic anchor, unlike every other monospaced text in the
window (13pt via the semantic body style). Since consistency is the point of this pass, resolving
in favor of matching: change to `NSFont.systemFontSize` (13), the same AppKit-equivalent pattern
already used in `KeyBindingsTab`'s key-recorder drawing code.

## What ships in the mockup (visual + structural + representable copy)

**New `SettingsChrome` components** (to prototype in the JSX kit's shared-component layer):
- `IconButton` (above).
- `PanelHeader` — `SectionLabel` pre-wrapped with `horizontal: 16, top: 14, bottom: 8`, for a tab
  whose layout isn't a `Form`. Justified by 3 independently-invented call sites across 2 files.

**Structural fixes:**
- `WorkspacesMonitorsTab`'s two empty states unified — the "Connected monitors" bare `SettingsHint`
  becomes a full `ContentUnavailableViewCompat` (icon `"display"`, title "No monitors detected",
  explanatory message, no action button since monitors appear on their own), matching every other
  emptyable list in the window. Give the monitors pane a `minHeight` (~120) alongside its existing
  `maxHeight: 200` so the empty state has room to center.
- `KeyBindingsTab`'s two-column `List` gains a plain column-header row ("Key" / "Command") above
  the rows, at `.caption`/`.secondary` styling matching `Table`'s own header typography, using the
  same 170pt-leading-column width the rows already establish. Tab-local, not a new component — one
  caller doesn't clear the bar for a shared "fake table header."
- `GapsSettingsTab`'s preview `Section` gets a `SectionLabel("Preview", "eye")` header, matching
  every other `Section` in the window instead of being the one unlabeled exception.
- Bar-strip and panel-header padding fixes (above).
- Remove-button consolidation onto `IconButton` (above), applied to `KeyBindingsTab` and all five
  `CallbacksTab` call sites.

**Visual fixes:**
- `GapsSettingsTab`'s preview fill: `Color.primary.opacity(0.05)` → `0.045` (the documented
  `--fill-subtle` token, matching the monitor row's card-radius surface). Its stroke:
  `Color.secondary.opacity(0.35)` → `Color.primary.opacity(0.16)` (the documented
  `--border-control` token).
- `CallbacksTab`'s add-button: drop `.foregroundStyle(Color.accentColor)` — accent tint is
  reserved for status/emphasis elsewhere in the window (the armed key recorder, the gaps-preview
  accent tile), not an ordinary add affordance. Inherit the default borderless-button tint like
  `ListActionBar`'s plain `+`.
- `CodeEditor` font size (above).

**Representable copy fixes** (visible in the mockup because they change on-screen text, not just
tooltips):
- `KeyBindingsTab`'s "No matches" filter empty state gains a "Clear filter" action button, reusing
  `ContentUnavailableViewCompat`'s existing `actionTitle`/`action` params — currently the only
  empty state in the window that names a problem with no offered recovery.
- `WorkspacesMonitorsTab`'s monitor picker: the plain-name option gains a contrasting label
  ("`LG UltraFine` — matches by name") only when a UUID sibling exists to disambiguate against —
  today only the UUID option explains itself.
- `KeyBindingsTab`'s "Delete mode" menu item states the cost before the irreversible click: appends
  `" — N bindings"` (counting only written/explicit bindings, matching the vocabulary the tab's own
  summary line already uses) when N > 0.

## Swift-only — not in the mockup, for the eventual implementation pass

These don't change any pixel a mockup can show, so Stage 2.5 skips them, but they're real, agreed
fixes and should land when Swift implementation happens:

- Two missing accessible names: the Keys filter-clear button and the mode-options `Menu` (direct
  `.help()`/`.accessibilityLabel()`, no component needed — `IconButton` can't wrap a `Menu`).
- `.help()` additions grounded in existing docs: `CallbacksTab`'s "Inherit AeroSpork's environment"
  toggle (the secrets-leak consequence from `docs/guide.adoc`), `GeneralSettingsTab`'s disabled Dock
  icon toggle (surfacing the footer's existing explanation at the point of interaction),
  `WindowRulesTab`'s App name/Window title fields (stating they're regexes), the two normalization
  toggles in `GeneralSettingsTab` (grounded in `docs/guide.adoc`'s own mechanism descriptions).
- `WorkspacesMonitorsTab`'s monitor row: `.accessibilityElement(children: .contain)` on the row
  `HStack`, so VoiceOver reads it as one grouped stop instead of four-plus separate ones, while
  keeping `CopyButton` individually actionable.
- `GapsPreview`: `.accessibilityElement(children: .ignore)` + a label/value summarizing the six
  gap numbers in words — currently a purely visual `Shape`-based view with zero accessible content.
- Badge contrast (a11y Finding 8) — flagged as verify-first, not a known defect. Screenshot `Badge`
  in both tones/appearances/real usage contexts and check against WCAG 1.4.3 before deciding
  whether it needs a fix. Not blocking.
- Extending `UIChromeConsistencyTest` with a rule catching `Button { } label: { Image(systemName:`
  outside `IconButton` — the cross-critique found a11y's originally-proposed regex wouldn't have
  caught the `Menu`-based case (Location B), so the rule should be scoped to what it actually
  catches (bare `Button`s) rather than oversold as covering both gaps.

## Verified clean against hard invariants (no synthesis decision needed)

- **`UIChromeConsistencyTest`**: no proposal reintroduces a hand-rolled `Capsule()`, raw status SF
  Symbol string, glyph-as-status-icon, or `TextField` title-as-placeholder. All new components live
  in `SettingsChrome.swift`, which the test's own `tabSources()` excludes from its scan.
- **`DesignKitParityTest`'s five pinned phrases** ("Add rule", "Add assignment", "Startup &
  behaviour", "Pause tiling", "Non-main") — untouched by anything in this synthesis. Confirmed
  directly against the diff scope; no test or kit-string update required.
- **Window-size floor** (`780×520` min / `880×620` ideal, confirmed in `ConfigurationWindow.swift`):
  nothing in this synthesis adds width or height to any tab. (The one width-adding change — the
  20pt selection-handle column — belongs to the pulled-out selection-bug fix, already reviewed
  separately, and is small relative to this tab's existing slack.)
- **Voice/casing/motion rules**: every string above is sentence case, no exclamation
  marks/emoji/jokes, no new motion, no new color outside `StatusLabel.Kind`/`Banner.Kind`.
