# General tab — redesign proposal

Scope: `Sources/AppBundle/ui/ConfigurationTabs/GeneralSettingsTab.swift` content pane (a single
`Form`, six `Section`s). Tab chrome and the seven-tab shell are out of scope.

## 1. Direction

I went in expecting to find either a hidden config gap (like Window Rules' `duringStartup`) or a
section structure that needed re-cutting. Neither is true here.

**No config gap.** I re-verified against `Config.swift` myself rather than trusting the brief's
excerpt, and it undercounts: General owns 11 fields, not 8 — the missing three are
`autoMoveWorkspacesOnMonitorConnect`, `accordionPadding`, and `keyMapping.preset` (nested under
`[key-mapping]`, which is presumably why a flat grep of `Config.swift`'s top-level `var`s missed
it). All 11 are wired into this tab today (line refs below). There is no Raw-TOML-only escape
hatch anywhere in General's own domain. So "maximum customizability" here is entirely a clarity
and grouping exercise, per the brief — I'm not opening this file to add a twelfth control.

| Config field | Control | Line |
|---|---|---|
| `startAtLogin` | "Start AeroSpork at login" toggle | 14 |
| `automaticallyUnhideMacosHiddenApps` | "Automatically unhide macOS hidden apps" toggle | 15 |
| `autoMoveWorkspacesOnMonitorConnect` | "Move workspaces to assigned monitors on connect" toggle | 17 |
| `showMenuBarIcon` | "Show icon in the menu bar" toggle | 24 |
| `showDockIcon` | "Show icon in the Dock" toggle | 28–32 |
| `defaultRootContainerLayout` | "New workspaces use" segmented picker | 42 |
| `defaultRootContainerOrientation` | "Split direction" segmented picker | 48 |
| `accordionPadding` | "Accordion peek" `NumberField` | 55 |
| `enableNormalizationFlattenContainers` | "Flatten single-child containers" toggle | 63 |
| `enableNormalizationOppositeOrientationForNestedContainers` | "Alternate orientation for nested containers" toggle | 64 |
| `keyMapping.preset` | "Keyboard layout" picker | 72 |

**No section re-cut.** I tried three different restructurings before rejecting all of them —
detailed in §2.4 so the reasoning survives, not just the verdict. The six sections, in their
current order, are the right shape. What's actually wrong is narrower and more fixable: one
section header oversells its contents as decorative when they're functional, one section's two
most non-obvious toggles explain themselves only in a hover tooltip nobody will find, and one
footer's phrasing implies a scope narrower than the setting actually has. Three small, precise
fixes, each grounded in a specific line of existing copy or code — not a repaint.

## 2. Specific changes

### 2.1 Rename "Appearance" → "Menu bar & Dock"

Section header at line 34: `SectionLabel("Appearance", "menubar.rectangle")` →
`SectionLabel("Menu bar & Dock", "menubar.rectangle")`. Icon unchanged. Rows unchanged. Footer
unchanged — both variants, verbatim:

- Forced: *"Both icons off would leave no way into Settings, so the Dock icon is kept.
  `aerospork open-settings` opens this window from anywhere if you would rather use a shortcut."*
- Not forced: *"AeroSpork has no window of its own, so these two icons are the only ways back
  into Settings without the command line. `aerospork open-settings` opens this window from
  anywhere."*

Why: the footer already says these two toggles are load-bearing — "the only ways back into
Settings" — but the header calls the section "Appearance," which frames them as cosmetic. That's
a real mismatch between what the copy says and what the label implies, not a style preference.
"Menu bar & Dock" names what the section actually controls and stops undercutting its own footer.

### 2.2 Give "Startup & behaviour" a footer

Today this section (lines 13–21) is the only one of six with zero footer, despite two of its
three toggles having non-obvious consequences that currently exist *only* as `.help()` tooltips
(lines 16, 18) — invisible until you hover. Every other section in the tab puts exactly this kind
of "why would I want this" explanation in visible footer text; this is the one place the pattern
was skipped. Add:

```swift
} footer: {
    Text("Automatically unhiding macOS hidden apps undoes ⌘H so a hidden window keeps tiling. Moving workspaces on monitor connect puts each one back on the monitor you pinned it to; off, a workspace stays wherever it landed when that monitor disappeared.")
}
```

"Start AeroSpork at login" needs no explanation (self-evident, no `.help()` today) and isn't
addressed by this footer, matching how other footers in this tab don't restate every row. Keep
the existing `.help()` tooltips as-is — this adds visible copy, it doesn't remove the hover
affordance.

### 2.3 Extend the "Layout" footer — accordion peek's actual scope

Current footer (line 59): *"Auto gives wide monitors a horizontal split and tall monitors a
vertical one. The accordion peek is how much of the window behind stays visible; 0 stacks them
exactly."*

I checked `docs/guide.adoc` (§Accordion, line 303) and `accordionPadding` applies to **any**
`h_accordion`/`v_accordion` container, not just the layout a workspace starts in — a container can
be switched to accordion later with the `layout` command, and the same peek value applies there
too. Sitting in a section titled "Layout" directly under "New workspaces use," the current wording
reads as if accordion peek only matters for that initial choice. New footer:

> Auto gives wide monitors a horizontal split and tall monitors a vertical one. The accordion peek
> is how much of the window behind stays visible; 0 stacks them exactly. It applies to any
> accordion container, not just new workspaces.

Rows, header, and icon unchanged.

### 2.4 Rejected restructurings (for the record)

Documenting these so the reconciliation pass doesn't wonder whether I considered them, or worse,
someone re-proposes one of these blind:

- **Split "Startup & behaviour" into "Startup & access" (login + the two icon toggles) and a
  separate "Automatic behaviour" (unhide + monitor-connect).** Genuinely tempting — it would give
  every row a tighter conceptual home. Rejected because it also relocates the icon toggles I'm
  already renaming in §2.1, compounding two changes into one section move for a win that a single
  added footer (§2.2) mostly captures anyway: once the consequence is visible, which literal box
  it sits in matters less.
- **Merge "Layout" and "Normalization" into one "Tiling defaults" section.** Both are about how
  the tree is shaped, but one is a choice you make (initial layout, split direction, peek) and the
  other is background housekeeping the app does regardless (flatten, alternate orientation) —
  different enough in kind that collapsing them loses a real distinction, and it would produce a
  5-row section, the largest in the tab by a full row over the current maximum of 3. Two footers
  would also have to become one, and I could not write a single-paragraph merge that stayed as
  precise as the two it would replace.
- **Convert "Keyboard layout" from `Picker`/`Select` to `SegmentedPicker`**, for internal
  consistency with the other two 2–3-option pickers in this same tab (`New workspaces use`,
  `Split direction`). I looked for this precedent and found the opposite of one:
  `Select.prompt.md` names "keyboard layouts" explicitly as a `Select` use case ("a list of
  options that can grow at runtime... connected monitors, modes, keyboard layouts"), distinct from
  `SegmentedPicker`'s "few, short, won't grow" criterion. Today's 3 presets happen to satisfy
  `SegmentedPicker`'s bar, but the component choice is about whether the list is expected to grow
  (more layouts could be added later), not the current count. Leaving as `Select`, unchanged.

## 3. Shared components used

No new components, no API changes, no new call-site pattern anyone else needs to watch for. Every
change in §2 is a header string, a footer string, or an icon-name no-op. Full inventory of what
this tab uses, all pre-existing and unchanged in shape: `FormSection`/`Section`, `SectionLabel`,
`Toggle`, `SegmentedPicker`, `NumberField`, `Select`/`Picker`, `LabeledContent`, `CopyButton`,
`SettingsHint` (implicitly, via `Section`'s `footer:`).

Two shared-component ideas I considered and rejected, flagged explicitly since they're exactly
the kind of thing another tab's designer might independently reach for:

- **`Badge` next to the disabled "Show icon in the Dock" toggle**, to explain inline why it's
  forced on (`Badge("kept", tone: .muted, help: "...")`), instead of relying on the section
  footer. Rejected: `Toggle.prompt.md` states directly, "Explanations belong in the section footer
  (`SettingsHint`), not next to the switch." Every existing `Badge` call site (`KeyBindingsTab`'s
  `"generated"`, `WindowRulesTab`'s `"startup"`) sits next to read-only row text, never next to a
  `Toggle`. Using it there would be the first `Toggle`+`Badge` combination in the kit and would
  contradict a documented rule, not extend it.
  - What I'd do instead, Swift-only and not visible in a static mock: add `.help("Both icons off
    would leave no way into Settings, so this one is kept.")` to the Dock toggle when
    `dockIconIsForced` is true, surfacing the same fact at the point of interaction via the
    existing tooltip mechanism (already used two rows up for the unhide toggle) rather than a new
    inline element. This is the same fix the prior consistency pass's synthesis already queued for
    this exact row (`dev-docs/redesign/synthesis.md`, "Swift-only" list) — I'm reaffirming it, not
    inventing it, and noting it so it isn't lost between rounds.
- **A schematic before/after preview for the "Normalization" section**, on the model of
  `GapsPreview` (Gaps tab renders six otherwise-meaningless numbers as tiles specifically because
  "six numbers with no picture is the worst kind of settings page"). Rejected: Normalization is
  two toggles whose labels ("Flatten single-child containers," "Alternate orientation for nested
  containers") already name the mechanism, unlike Gaps' bare integers — the bar `GapsPreview` was
  built to clear doesn't apply here. A diagram would be a second brand-new visualization component
  for a marginal gain the existing footer already covers in one sentence.
- **A live layout-preview diagram** for "New workspaces use" / "Split direction," same model.
  Rejected for the same reason from the other direction: a `SegmentedPicker`'s selected segment
  *is* the preview — "Tiles" or "Accordion" is already legible at a glance. Gaps needed a picture
  because raw numbers carry no visual meaning on their own; a picker's selected state already does.

## 4. Fits at 780×520

- **Width.** Nothing in §2 touches a control's width or adds a row. The only width-relevant
  element I looked at closely was the rejected `SegmentedPicker` conversion for keyboard layout
  (§2.4); since I'm not making that change, there's no new segmented control to check. The two
  existing segmented pickers ("Tiles"/"Accordion", "Auto"/"Horizontal"/"Vertical") are unchanged
  and already ship at this floor today.
- **Height.** Two of three changes only add or extend footer text (a `SettingsHint`, ~12px type,
  1–2 lines) inside sections that already render inside a scrolling `Form`. The tab already
  requires scrolling well before 520pt at six sections deep — that's true today and unaffected by
  this proposal, since I add zero rows and zero sections. `.formStyle(.grouped)` already
  guarantees native scroll rather than clipping, the same floor every other tab in this window
  relies on.
- **No new failure mode.** Every change here is a string edit (header title, footer body) or a
  `.help()` addition that renders nothing in a static mock. There is nothing in this proposal that
  could overflow, clip, or push a control past its existing footprint.
