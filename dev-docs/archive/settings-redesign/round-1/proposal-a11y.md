# Settings window — accessibility proposal

Scope: the seven-tab `Settings` scene under `Sources/AppBundle/ui/`. Audited against WCAG 2.2
success criteria as the closest documented standard, even though this is a native AppKit/SwiftUI
surface rather than a web page — the same underlying questions (does this have a name, can a
keyboard/AT user reach it, does it announce when it changes) apply one-for-one to the macOS
Accessibility API. `UIChromeConsistencyTest.swift` is the floor: it already mechanically enforces
Badge's mandatory `help:`, forbids hand-rolled badges/status glyphs, and forbids
title-as-placeholder text fields. Everything below is what still gets through that floor.

No production Swift was changed. No hardcoded `Color(red:...)`/`NSColor(red:...)` literals or
`.animation`/`withAnimation` calls exist anywhere under `Sources/AppBundle/ui/` (confirmed by grep)
— the window is disciplined about semantic colors and currently has zero motion, which is worth
stating plainly rather than manufacturing a Motion section with nothing in it.

## Headline findings

1. **`WorkspacesMonitorsTab`'s assignment rows may be unselectable by both mouse and keyboard**,
   which would make the Remove button in `ListActionBar` permanently unreachable for that tab. The
   code's own comment already admits the mouse half of this; the keyboard half is unverified and is
   the single highest-priority thing to test by hand before anything else in this document.
2. **Three icon-only controls ship with no accessible name at all** — not a case of a *misleading*
   label, but VoiceOver reading literally "button" with zero context. This is exactly the failure
   mode `Badge`'s mandatory `help:` param was built to prevent for badges, but nothing enforces the
   equivalent for a bare `Button { } label: { Image(systemName:) }`.
3. **One shared control (`CallbacksTab`'s `removeButton`) gives every remove affordance in four
   command sections plus the env-var list the identical accessible name "Remove"** — the exact
   generic-label problem the codebase already knows how to avoid, since the row right next to it in
   `KeyBindingsTab` does `.accessibilityLabel("Remove \(b.key)")` instead.

## Finding 1 — `WorkspacesMonitorsTab` row selection may be unreachable (Critical, bigger swing)

**Location**: `Sources/AppBundle/ui/ConfigurationTabs/WorkspacesMonitorsTab.swift:97–133`

**What's there.** The assignments `Table` has two columns, and both are filled edge-to-edge by
focusable controls — `SettingsField` (a bordered `TextField`) in the Workspace column, a
`labelsHidden()` `Picker` in the Monitor column. The code's own comment at lines 126–129 says so
directly:

```
// Both columns are filled edge to edge by focusable controls, which swallow the
// click that would select the row -- so `selection` stayed nil and ListActionBar's
// Remove was permanently disabled. Window Rules has had this since it has Text-only
// cells; this table needs it to have any delete affordance at all.
```

The fix that shipped was `.onDeleteCommand { if let id = selection { … } }` (lines 130–133) — a
keyboard Delete path, contingent on `selection` already being non-nil. But nothing in the file sets
`selection` any other way: mouse click is admitted-broken, and Tab traversal through the row lands
inside the `SettingsField`/`Picker` controls themselves, not in a table-level "this row is now the
selected row" state. Contrast `WindowRulesTab`, whose two columns are plain, non-focusable `Text`
(`WindowRulesTab.swift:56–62`) — a click anywhere on a `WindowRulesTab` row hits the row, not a
control, so `Table` selection works normally there. `WorkspacesMonitorsTab` has no equivalent empty
space left to click.

**Why it matters.** If this is as broken as the comment states, no user — sighted, blind, mouse,
keyboard, or Switch Control — can select a row to remove it; `ListActionBar`'s Remove button (which
this tab wires to `onRemove: selection == nil ? nil : { … }`, `WorkspacesMonitorsTab.swift:18–22`)
is permanently disabled for anyone who hasn't found some other way to set `selection`. This is a
WCAG 2.1.1 (Keyboard) and 2.4.3 (Focus Order) failure if confirmed: functionality that exists
(remove an assignment) has no operable path to it at all, for any input method, not just assistive
ones.

**This needs a hands-on check before anything else in this document**: open the tab with an
existing assignment, Tab into the table, and press Down/Up. If `selection` never changes, this is
the most severe finding here by a wide margin, because it isn't an AT-only gap — it blocks
everyone.

**Proposed fix.** Give each row a small, non-field selection target that survives being tabbed to
and clicked — e.g. a leading `Image(systemName: "line.3.horizontal")`-style drag/selection handle
column (no `.width` needed beyond ~20pt) that is not itself a text-entry or picker control, wired
to set `selection` on both click and `.accessibilityAction`. This restores a real click-to-select
surface without touching the two data columns, and gives keyboard/VoiceOver users a discrete,
focusable "select this row" stop that isn't overloaded onto the workspace name field. Tag this
fix itself "bigger swing" — it's a new column, not a one-line change — but the diagnosis and
verification above are cheap and should happen this pass regardless of when the fix lands.

## Finding 2 — three icon-only controls with no accessible name (Serious, safe — ship this pass)

**Location A**: `Sources/AppBundle/ui/ConfigurationTabs/KeyBindingsTab.swift:113–117`, the filter
clear button:

```swift
if !query.isEmpty {
    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
        .buttonStyle(.borderless)
        .foregroundStyle(.tertiary)
}
```

No `.help()`, no `.accessibilityLabel()`. Compare the *other* clear button in the same file, three
hundred lines later (`KeyBindingsTab.swift:363–370`), which does exactly this right:

```swift
Button { notation = "" } label: { Image(systemName: "xmark.circle.fill") }
    .buttonStyle(.borderless)
    .foregroundStyle(.tertiary)
    .padding(.trailing, 4)
    .help("Clear")
    .accessibilityLabel("Clear this shortcut")
```

The fix at the filter box is the same shape: `.help("Clear filter")` +
`.accessibilityLabel("Clear filter")`.

**Location B**: `Sources/AppBundle/ui/ConfigurationTabs/KeyBindingsTab.swift:73–82`, the mode
options menu:

```swift
Menu {
    Button("New mode…") { addingMode = true }
    Button("Delete “\(selectedMode)”", role: .destructive) { removeMode() }
        .disabled(!viewModel.canRemoveMode(selectedMode))
} label: {
    Image(systemName: "ellipsis.circle")
}
.menuStyle(.borderlessButton)
.menuIndicator(.hidden)
.fixedSize()
```

No `.help()`/`.accessibilityLabel()` on the `Menu` itself. Its label is a bare SF Symbol with no
visible text anywhere nearby to fall back on (unlike `ListActionBar`'s plus/minus, which are
adjacent to obviously-labeled rows). A VoiceOver user tabbing across the mode bar hits: mode
picker, then an unnamed "button" or "pop-up button" with no indication it's where mode
management lives. Fix: `.help("Mode options")` + `.accessibilityLabel("Mode options")` on the
`Menu`.

**Why it matters.** These are two of the exact three failure categories the mandate calls out —
icon-only interactive elements with literally no name, not even a wrong one. A screen reader user
cannot use either control without first discovering by trial that it does something.

**Why `UIChromeConsistencyTest` didn't already catch this**: its badge/glyph/placeholder rules are
source-text checks targeted at specific known-bad patterns (`Capsule()`, hardcoded status glyphs, a
title used as a placeholder). None of them inspect `Button { } label: { Image(systemName:` for a
missing `.help(`. See the cross-cutting proposal below for a rule that would.

## Finding 3 — `CallbacksTab`'s shared remove button gives every row the same name (Serious, safe)

**Location**: `Sources/AppBundle/ui/ConfigurationTabs/CallbacksTab.swift:102–108`

```swift
private func removeButton(_ action: @escaping () -> Void) -> some View {
    Button(role: .destructive, action: action) { Image(systemName: "minus.circle") }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Remove")
        .accessibilityLabel("Remove")
}
```

This one helper backs every remove control in the tab: the four `commandSection` calls ("After
startup", "Focused workspace changed", "Focused monitor changed", "Focus changed" —
`CallbacksTab.swift:11–36`, wired at line 78) and the environment-variable rows
(`CallbacksTab.swift:45`). Every single one is announced as exactly "Remove" — no command text, no
variable name, no section. A user with, say, three commands under "After startup" and two under
"Focus changed" hears five identical "Remove, button" stops in a row with nothing to distinguish
which does what.

**The codebase already has the right pattern** for this, in the very same window: `KeyBindingsTab`
does `.accessibilityLabel("Remove \(b.key)")` (line 172) so the name of the thing being removed is
part of the label. The mandate's own example ("Remove" but doesn't say what) is not hypothetical —
this is that exact bug, live, backing eight-plus rows across the window.

**Proposed fix.** Give `removeButton` a `named:` parameter and thread the row's own text through it:

- Command rows (`commandSection`, line 78): `removeButton(named: row.command.isEmpty ? "empty command" : row.command) { … }` → `.accessibilityLabel("Remove \(name)")`.
- Env var rows (line 45): `removeButton(named: row.name.isEmpty ? "unnamed variable" : row.name) { … }`.

Handle the empty-string case explicitly (a freshly-added, not-yet-typed-into row) so the label
never degrades to "Remove " with nothing after it.

## Finding 4 — dynamic status text has no announcement when it appears or changes (Moderate, bigger swing)

**Locations**:
- `Sources/AppBundle/ui/ConfigurationWindow.swift:16–25` — the top-of-window config-failure/warning `Banner`, which the code comments describe as deliberately "not a notification... persistent and not dismissible" because it's the only thing standing between "config failed to load" and an app silently running built-in defaults.
- `Sources/AppBundle/ui/ConfigurationWindow.swift:67–82` — the bottom `safeAreaInset` error `StatusLabel`, shown whenever `viewModel.errorMessage` is set on a non-raw tab.
- `Sources/AppBundle/ui/ConfigurationTabs/RawTomlTab.swift:104–118` — the three-way status readout (`error` / `edited` / `matches disk`) below the code editor.
- `Sources/AppBundle/ui/ConfigurationTabs/KeyBindingsTab.swift:256–260, 279–299` — the "already bound" conflict banner that appears under the composer as soon as a typed shortcut collides with an existing one.

**Why it matters.** All four are exactly the content VoiceOver's "status message" support exists
for (WCAG 4.1.3, Status Messages) — text that appears or changes as a *consequence* of something
the user just did (typed a shortcut, edited raw TOML, saved a bad config) without moving focus.
Right now a VoiceOver user only discovers any of this if they happen to navigate back to where the
text lives after the fact. For the top banner specifically: it's literally the app telling the user
their config didn't load and it's running a keymap they never wrote — a sighted user sees it the
instant the window opens; a VoiceOver user whose focus lands somewhere in the tab content (which is
plausible if the window remembers the last-viewed tab) may never hear it unless they explore
upward.

**Proposed fix.** Post an accessibility announcement whenever the driving text changes, using
SwiftUI's `AccessibilityNotification.Announcement` (macOS 12+):

```swift
.onChange(of: bannerText) { _, new in
    AccessibilityNotification.Announcement(new).post()
}
```

Apply this at the four sites above. This is "bigger swing" only because it's a pattern not used
anywhere in the codebase yet, not because any individual call site is hard — see the
`SettingsChrome.swift` proposal below for making it one call instead of four ad hoc ones.

## Finding 5 — `GapsPreview` has no accessible description at all (Moderate, bigger swing)

**Location**: `Sources/AppBundle/ui/ConfigurationTabs/GapsSettingsTab.swift:61–107`

The tab's own comment explains the point of this view: "Six numbers with no picture is the worst
kind of settings page... The preview is driven by the same values that are about to be written, so
the loop closes here." That loop only closes for sighted users. `GapsPreview` is built entirely
from `GeometryReader`/`ZStack`/`RoundedRectangle` with no `Text` anywhere in it — SwiftUI `Shape`
views produce no default accessibility element, so a VoiceOver user gets nothing here: not wrong
information, just silently zero information, in the one spot in this tab designed specifically to
make the six numbers around it easier to understand.

**Why it matters.** This is WCAG 1.1.1 (Non-text Content): a graphic that conveys information needs
a text alternative that conveys the same information. Here that's tractable — the six numbers
driving the preview are already sitting in `ConfigurationViewModel` as plain `Int`s.

**Proposed fix.** Add a computed accessibility label/value pair to the `GapsPreview` container
summarizing the same six numbers in words, e.g.:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel("Gap preview")
.accessibilityValue("\(innerHorizontal)pt between windows horizontally, \(innerVertical)pt vertically. \(outerTop)pt top, \(outerBottom)pt bottom, \(outerLeft)pt left, \(outerRight)pt right around the screen.")
```

`.accessibilityElement(children: .ignore)` collapses the three nested `RoundedRectangle`/`ZStack`
layers into the one described element instead of VoiceOver silently skipping past several
un-labeled shape layers.

## Finding 6 — `RecorderView`'s custom-drawn text ignores text-size scaling (Minor, bigger swing)

**Location**: `Sources/AppBundle/ui/ConfigurationTabs/KeyBindingsTab.swift:432–467`, specifically
lines 447–449:

```swift
.font: displayed.isEmpty
    ? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    : NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
```

`RecorderView` is the one place in the entire settings window where text is drawn by hand
(`NSString.draw(with:options:attributes:context:)`) rather than through a SwiftUI `Text`/`Label`.
Every other string in the window goes through SwiftUI's semantic font API (`.font(.body)`,
`.callout`, etc.), which is what gives the rest of the window a chance to track the system's text
size preference. `NSFont.systemFontSize` is a fixed 13pt constant — it does not track anything.
This view is also, by the tab's own design, the one place holding the least compressible content
in the window: a real key combo like `ctrl-alt-shift-cmd-rightSquareBracket` inside a fixed
170×22pt frame (`KeyBindingsTab.swift:166, 245`).

**Why it matters.** The row already has a truncation strategy (`.truncatesLastVisibleLine`, per the
comment at lines 458–461) for the *width* problem, so it's not silently broken — but a fixed font
size is one axis of scaling this control can never respond to, unlike its sibling `SettingsField`
in the same row, which is a real SwiftUI `Text`/`TextField`.

**Proposed fix.** Swap the two hardcoded sizes for `NSFont.preferredFont(forTextStyle:)`-equivalent
values (`.systemFont(ofSize: NSFont.systemFontSize(for: .regular))` is not the fix — use
`NSFont.systemFont(ofSize: 0)`/text-style-based APIs, or simplest: read the size SwiftUI would use
for `.body`/`.system(.body, design: .monospaced)` via `NSFont.preferredFont(forTextStyle: .body)`)
so this control at least moves in step with whatever text-size mechanism ends up covering the rest
of the window (see Finding 4's `SettingsChrome` proposal for a shared place to answer "does this
window support text scaling at all" once, rather than per-control).

## Finding 7 — monitor rows are not grouped for VoiceOver (Minor, safe)

**Location**: `Sources/AppBundle/ui/ConfigurationTabs/WorkspacesMonitorsTab.swift:47–71`

```swift
ForEach(viewModel.liveMonitors) { monitor in
    HStack(spacing: 10) {
        Image(systemName: "display")...
        VStack(alignment: .leading, spacing: 1) {
            Text(monitor.name).fontWeight(.medium)
            Text(monitor.resolution)...
        }
        Spacer(minLength: 12)
        if let uuid = monitor.uuid {
            Text(uuid.prefix(8) + "…")...
            CopyButton(value: uuid, help: "Copy monitor UUID\n\(uuid)")
        }
    }
    ...
}
```

Nothing here groups the row into one accessibility element, so VoiceOver reads a "display" image,
the monitor name, the resolution, and the truncated UUID as four-plus separate stops per monitor
instead of one. Compare `KeyBindingsTab`'s `conflictBanner`
(`KeyBindingsTab.swift:279–299`), which explicitly does this right with
`.accessibilityElement(children: .combine)` on the whole `HStack` — the exact same "compound row,
several Text/Image children" shape as this one.

**Proposed fix.** Add `.accessibilityElement(children: .combine)` to the monitor row's outer
`HStack`, and keep the `CopyButton` as its own reachable child by using `.contain` instead of
`.combine` if the copy action needs to stay individually actionable — `.combine` merges into a
single non-interactive label, which would swallow the Copy button's own action. `.accessibilityElement(children: .contain)` groups for rotor/heading navigation while preserving each child's own actions; that's almost certainly the right choice here over `.combine`, given `CopyButton` needs to remain individually pressable.

## Finding 8 — Badge legibility should be measured, not assumed (Minor, bigger swing — verify)

**Location**: `Sources/AppBundle/ui/SettingsChrome.swift:225–259`

`Badge` renders at `.caption2` — 10px, the smallest text size documented anywhere in the design
system (`.claude/skills/aerospork-design/readme.md:105–108`) — at `.foregroundStyle(.secondary)`,
on top of a translucent `Capsule` fill (`Color.primary.opacity(0.08)` for `.standard`,
`Color.secondary.opacity(0.2)` for `.muted`). No literal color is used, which is exactly what the
design system's opacity-hierarchy rule is meant to guarantee correctness across appearances — so
this is not the "bypasses the hierarchy with a literal color" case the mandate asks to hunt for.
But the badge's background is a *translucent overlay*, not an opaque fill: its actual rendered
contrast depends on whatever is compositing underneath it (a `Form`'s grouped background material
in `WorkspacesMonitorsTab`, a `List` row in `KeyBindingsTab`, a `Table` cell in `WindowRulesTab`),
which varies by tab and cannot be determined by reading the source. This is precisely the kind of
thing an automated contrast checker run against a static screenshot would either miss or get wrong
depending on what happened to be behind the badge in that one screenshot.

**Proposed fix.** Not a code change — a verification task: screenshot `Badge` in both tones, in
both `.standard`/`.muted`, in both light and dark appearance, in each of its three real usage
contexts (`KeyBindingsTab`'s "generated" badge in a `List` row, `WindowRulesTab`'s "startup" badge
in a `Table` cell), and run each through a contrast checker against WCAG 1.4.3's 4.5:1 (it's small
text, no bold weight, so it doesn't qualify for the 3:1 large-text exception). If any combination
fails, the fix is almost certainly raising `.muted`'s fill opacity slightly rather than touching
the text color, to keep the opacity-hierarchy rule intact.

## What's working well

- `NumberField`, `SettingsField`, `Badge`, `ListActionBar`, and `CopyButton` in `SettingsChrome.swift`
  already do real, non-decorative accessibility work — separate `.accessibilityLabel`s on the
  `TextField`/`Stepper` pair in `NumberField` (lines 34–48) rather than relying on a hidden
  `LabeledContent` title to survive `labelsHidden()`, and `Badge`'s mandatory `help:` parameter.
- `KeyBindingsTab.swift:172` (`.accessibilityLabel("Remove \(b.key)")`) and `:298`
  (`.accessibilityElement(children: .combine)` on `conflictBanner`) are exactly the right patterns —
  Findings 3 and 7 above are asking other parts of the window to catch up to code that already
  exists two hundred lines away in the same file.
- `RecorderView` (`KeyBindingsTab.swift:401–407`) correctly makes a hand-rolled `NSView` an
  accessibility element with a role, label, help text, and a live-updating value — the harder,
  easy-to-skip half of custom-AppKit accessibility is already done; Finding 6 is about the one
  narrower gap (font scaling) left in it.
- Zero hardcoded colors and zero animations anywhere under `Sources/AppBundle/ui/` — there is
  currently nothing in this window that could violate reduced-motion preferences, and the
  opacity-based label hierarchy plus semantic `NSColor`/SwiftUI materials mean nearly everything
  already adapts to Increase Contrast and Dark Mode automatically. Badge (Finding 8) is the one
  place that's worth double-checking rather than assuming.
- `StatusLabel`/`Banner` pair color with a distinct icon per kind (`SettingsChrome.swift:265–300,
  307–352`) rather than relying on color alone to carry meaning — already correct, don't touch it
  when addressing Finding 4.

## Proposed additions to `SettingsChrome.swift`

These close gaps across multiple tabs at once, the same way `Badge`'s mandatory `help:` already
does for one specific pattern.

### 1. An icon-button wrapper that makes an accessible name required, not conventional

Findings 2 and 3 both trace back to the same root cause: `Button { } label: { Image(systemName:) }`
compiles fine with no name at all, and nothing enforces otherwise the way `Badge`'s `help:`
parameter enforces itself for badges. Add:

```swift
/// An icon-only button. `label` is mandatory and doubles as the accessibility name — the same
/// contract `Badge.help` already has, extended to buttons.
struct IconButton: View {
    let systemImage: String
    let label: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) { Image(systemName: systemImage) }
            .help(label)
            .accessibilityLabel(label)
    }
}
```

Then extend `UIChromeConsistencyTest` with a source-text rule in the same spirit as
`testNoTabRollsItsOwnBadge`: flag any `Button { … } label: { Image(systemName:` (or
`Button(role: … , action: …) { Image(systemName:`) in a tab file that isn't going through
`IconButton`. That single rule would have caught Findings 2 and 3 mechanically, the same way the
existing tests already catch a hand-rolled badge.

### 2. A shared announcement helper for Finding 4

```swift
extension View {
    /// Posts a VoiceOver announcement whenever `text` changes to a non-nil, non-empty value.
    /// For content that appears or updates without a focus change -- banners, inline validation,
    /// conflict warnings -- which WCAG 4.1.3 (Status Messages) exists for.
    func settingsAnnounce(_ text: String?) -> some View {
        onChange(of: text) { _, new in
            guard let new, !new.isEmpty else { return }
            AccessibilityNotification.Announcement(new).post()
        }
    }
}
```

Apply at the four sites in Finding 4 as `.settingsAnnounce(bannerText)` rather than four
independent `.onChange` blocks.

### 3. A minimum hit-target modifier

`CopyButton`'s icon is explicitly `frame(width: 14)` (`SettingsChrome.swift:452`) with no minimum
height and no extra hit-area padding beyond whatever `.buttonStyle(.borderless)` supplies by
default — the tightest explicit size constraint on any control in the window. `ListActionBar`'s
plus/minus (`SettingsChrome.swift:144–150`) and the several `minus.circle`/`xmark.circle.fill`
buttons across the tabs have no explicit size at all, relying on the SF Symbol's natural glyph
size. None of this is necessarily broken (macOS doesn't have a published numeric minimum the way
iOS does), but WCAG 2.2's 2.5.8 (Target Size Minimum) uses 24×24 as its baseline, and that's a
reasonable one to hold a native macOS app to given it also has to serve Switch Control and pointer
users with motor impairments, not just VoiceOver. Add:

```swift
extension View {
    /// Guarantees a minimum interactive footprint regardless of the glyph inside, for icon-only
    /// borderless controls. WCAG 2.5.8's 24x24 baseline, applied to a pointer-first platform that
    /// still has Switch Control and pointer-accessibility users to serve.
    func settingsHitTarget() -> some View {
        frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
    }
}
```

Apply to `CopyButton`'s `Image` and to `ListActionBar`'s plus/minus at minimum; the per-tab
`minus.circle` remove buttons can pick it up for free if they're migrated to `IconButton` above.

## Remediation priority

**Immediate (verify/fix before anything else ships this pass)**
1. Finding 1 — confirm by hand whether `WorkspacesMonitorsTab` row selection is reachable at all by keyboard; if not, this blocks Remove for every input method, not just AT.
2. Finding 2 — two missing `.help()`/`.accessibilityLabel()` calls, near-zero-risk one-line fixes.
3. Finding 3 — thread row identity through `CallbacksTab.removeButton`.

**Short-term**
4. Finding 4 — `settingsAnnounce` helper plus four call sites.
5. Finding 7 — one `.accessibilityElement(children: .contain)` in `WorkspacesMonitorsTab`.
6. Finding 5 — `GapsPreview` accessibility label/value.

**Ongoing / verify-first**
7. Finding 8 — screenshot-and-measure Badge contrast before deciding whether it needs a fix.
8. Finding 6 — `RecorderView` font scaling, bundled with whatever text-scaling story the rest of the window ends up with.
9. `IconButton` + the `UIChromeConsistencyTest` rule that would have caught Finding 2/3 mechanically, so this category doesn't recur in an eighth tab.
