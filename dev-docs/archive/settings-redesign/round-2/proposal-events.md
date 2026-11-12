# Events tab — redesign proposal

Author: UI Designer (Events tab track)
Scope: `Sources/AppBundle/ui/ConfigurationTabs/CallbacksTab.swift`, tab label "Events"
Mockup to update: `.claude/skills/aerospork-design/ui_kits/settings_app/EventsTab.jsx` (not edited by this proposal — for the mockup builder)

## Verification notes (read before implementing)

- **Config surface is already fully exposed.** `Config.afterStartupCommand`,
  `onFocusChanged`, `onFocusedWorkspaceChanged`, `onFocusedMonitorChanged`, and `execConfig`
  (`execInheritEnvVars` + `execEnvVars`) all round-trip through `ConfigurationViewModel`
  (`afterStartupCommands`, `onFocusChanged`, `onFocusedWorkspaceChanged`,
  `onFocusedMonitorChanged`, `execInheritEnvVars`, `execEnvVars`) and are rendered in
  `CallbacksTab.swift` today. There is no missing binding to add.
- **`execOnWorkspaceChange` is confirmed not exposed**, and this proposal does not expose it.
  It exists in `Config.swift:100` (`/// Deprecated, but honoured -- focus.swift spawns it on
  every workspace change.`) and is parsed from the deprecated `exec-on-workspace-change` TOML
  key (`parseConfig.swift:149`), but `CallbacksTab.swift` and `ConfigurationViewModel` never
  reference it. `docs/guide.adoc` (`#exec-on-workspace-change-callback`) itself tells users to
  prefer `on-focused-workspace-changed` + `exec-and-forget` instead. Given that, the config
  surface is complete as-is and "maximum customizability" for this tab means maximizing
  *discoverability* of what's already possible, not adding new bindings.
- **Discrepancy worth flagging, not fixing here:** the brief states the `IconButton` /
  curly-quote remove-button migration "is already shipped in both the real Swift and the
  mockup." I confirmed it's shipped in the JSX (`EventsTab.jsx` already uses
  `IconButton systemImage="minus.circle" role="destructive" label={...curly-quoted...}`), but
  `grep -rn "IconButton" Sources/AppBundle/ui/` returns nothing — the type doesn't exist in
  Swift yet, and `CallbacksTab.swift`'s current `removeButton` is still a private helper with a
  generic, non-curly-quoted `"Remove"` label. This proposal treats the JSX mockup as the
  up-to-date baseline (since that's what the mockup builder extends) and does not re-litigate
  the migration itself — just noting the Swift file hasn't caught up yet, for whoever does the
  eventual Swift pass.
- Order-of-execution claim below (commands run top to bottom) is grounded in
  `initAppBundle.swift:43` (`config.afterStartupCommand.runCmdSeq(...)`) and
  `focus.swift:171-175` (callbacks iterate `commands` in list order inside one `runSession`) —
  not invented.

## Direction

The tab's structure — four command-list sections plus one exec-environment section, all inside
one grouped `Form` — already works and shouldn't change. `dev-docs/redesign/synthesis.md`
already considered and explicitly rejected converting this tab to a `List`-backed pattern
("reads as tab restructuring rather than consistency"); nothing in this brief overrides that,
and reinventing list mechanics here would be the one idea most likely to collide with what the
other six tab-designers are doing in parallel. So: no new components, no new interaction
patterns, no reordering (see "Considered and rejected" below) — same five sections, same row
shape, same shared `FormSection` / `SectionLabel` / `IconButton` / `Toggle` / `TextField` /
`SettingsHint`.

What actually changes is what the tab *tells the user*. Right now every one of the four command
fields shares one generic placeholder (`exec-and-forget open -a Terminal`) regardless of what
the field is for, the environment-inheritance toggle carries a real, documented, security-shaped
consequence that's currently invisible until you go read `docs/guide.adoc`, and two automatic
environment variables plus a diagnostic CLI command exist and are never mentioned anywhere in
the GUI. None of that requires new UI — it requires better-chosen text in components that are
already there. That's the whole proposal: tighten the copy so the tab teaches its own
capabilities, the same way `WindowRulesTab`'s footers and empty states already do
("Chain commands with `&&`. By default a matching rule stops the search.").

## Specific changes

### 1. Per-section command placeholders, grounded in `docs/guide.adoc`

Today `commandSection`'s `SettingsField` prompt is the single hardcoded string
`"exec-and-forget open -a Terminal"`, reused across all four sections regardless of what they
trigger. Two of the four sections have unambiguous, already-documented canonical examples in
`docs/guide.adoc` (`#on-focus-changed-callbacks`) that are more useful than a generic Terminal
launch. Change the placeholder per section:

| Section | Current placeholder | New placeholder | Source |
|---|---|---|---|
| After startup | `exec-and-forget open -a Terminal` | unchanged | — |
| Focused workspace changed | `exec-and-forget open -a Terminal` | unchanged | its own footer already names `move-mouse window-lazy-center`; giving "Focus changed" that exact string as *its* placeholder (next row) would make the two look copy-pasted, so this one keeps the generic example |
| Focused monitor changed | `exec-and-forget open -a Terminal` | `move-mouse monitor-lazy-center` | `guide.adoc` line 643: `on-focused-monitor-changed = ['move-mouse monitor-lazy-center']` |
| Focus changed | `exec-and-forget open -a Terminal` | `move-mouse window-lazy-center` | `guide.adoc` line 645: `on-focus-changed = ['move-mouse window-lazy-center']` |

Implementation: `commandSection(...)` currently takes a fixed prompt inline in its body
(`SettingsField("Command", prompt: "exec-and-forget open -a Terminal", ...)`). Add a `placeholder:
String` parameter to `commandSection` and pass the four values above at each of the four call
sites. In the JSX mockup, `CommandRows` takes a `placeholder` prop threaded into its `TextField`
the same way (currently hardcoded `placeholder="command"` — replace with the per-section value).

### 2. Order note on "After startup"

Add one clause to the existing footer, stated once (not repeated across all four sections — see
rationale below):

> "Runs once, after AeroSpork finishes launching. Multiple commands run in order, top to
> bottom."

This is a real, previously-unstated fact (confirmed via `runCmdSeq` / sequential callback
dispatch, not assumed) and it's the kind of thing a user chaining two or three startup commands
needs to know. Stating it once, on the first section a user reads, is enough — the row shape
(a plain ordered list with an Add button at the bottom) is identical in the other three
sections, so the mental model transfers without needing four near-identical sentences. Don't add
this clause to the other three footers; they're already carrying their own distinct explanation
and a fourth repeated sentence reads as boilerplate stutter.

### 3. Visible consequence for "Inherit AeroSpork's environment"

Currently the toggle has no visible explanation at all — not even a footer mention — despite
`docs/guide.adoc` (`#exec-env-vars`) spelling out a real, security-relevant consequence:
inheriting means every command on the tab runs with AeroSpork's full environment, secrets
included, which is deliberate (a Slack-posting callback needs its token) but means a config
snippet copied from the internet gets the same access. This is exactly the kind of thing
"explain the consequence, not the control" exists for, and right now it's invisible.

Add a conditional `SettingsHint` directly below the toggle, shown only while the toggle is on
(the default, and the state that carries the risk — "name the state, then the recovery"):

> "Every command on this page runs with AeroSpork's full environment, including anything
> sensitive in it. Turn this off and list only what you need below."

Swift:
```swift
Toggle("Inherit AeroSpork's environment", isOn: viewModel.binding(\.execInheritEnvVars))
if viewModel.execInheritEnvVars {
    SettingsHint("Every command on this page runs with AeroSpork's full environment, including anything sensitive in it. Turn this off and list only what you need below.")
}
```
This is the same conditional-row shape `commandSection` already uses for its empty state
(`if viewModel[keyPath: keyPath].isEmpty { SettingsHint(...) }`), so it's not a new pattern in
this file. In the JSX mockup this is `{inherit && <SettingsHint>...</SettingsHint>}` as a second
direct child of the section's `FormSection`, right after the `<label>` checkbox row — `FormSection`
already draws a hairline between any two top-level children, which is the correct visual (it
matches how a native `.formStyle(.grouped)` `Section` would separate the toggle row from the
explanatory row below it; no special wrapping needed).

### 4. Swap the JSX mockup's raw checkbox for the shared `Toggle` component

`EventsTab.jsx` currently renders environment inheritance as a hand-built
`<label><input type="checkbox".../> Inherit this app's environment</label>` instead of importing
`Toggle` from `components/controls/Toggle.jsx`, even though the design system exposes exactly
that component and every other boolean setting in the kit uses it. Replace it with:

```jsx
<Toggle label="Inherit AeroSpork's environment" checked={inherit} onChange={setInherit} />
```

Two things to fix at the same time, both currently wrong relative to the real Swift:
- The visible label text is `"Inherit this app's environment"` in the mockup but
  `"Inherit AeroSpork's environment"` in `CallbacksTab.swift`. The design system's own voice
  rule ("The app never refers to itself in the first person... Product name is always
  `AeroSpork`") sides with the Swift string — use `"Inherit AeroSpork's environment"` and drop
  `"this app's"`.
- `Toggle`'s API is `label`/`checked`/`onChange`, matching the `TextField`/`IconButton` calling
  convention already used elsewhere in this same file.

### 5. Extend the exec-environment footer to surface what's currently invisible

`docs/guide.adoc` documents two environment variables AeroSpork exports automatically to a
command that has a target (`AEROSPORK_WINDOW_ID`, `AEROSPORK_WORKSPACE`), plus a CLI command
that shows the exact resolved environment (`aerospork list-exec-env-vars`). None of this is
mentioned anywhere in the tab today — it's real, already-shipped capability that's purely
undiscoverable. Extend the existing footer (don't add a second hint block — one footer, same
"one hint style in this window" convention) from:

> "`exec-and-forget` and every command above run with this environment. `PATH` is the one
> people usually need."

to:

> "`exec-and-forget` and every command above run with this environment. `PATH` is the one
> people usually need. Commands with a window or workspace target also get
> `AEROSPORK_WINDOW_ID` or `AEROSPORK_WORKSPACE`: check the exact values with `aerospork
> list-exec-env-vars`."

Both `AEROSPORK_WINDOW_ID`/`AEROSPORK_WORKSPACE` and `list-exec-env-vars` render as `code` spans
automatically — `SettingsHint`'s existing backtick-span parsing (both Swift's
`LocalizedStringKey`-driven `Text` and the JSX `SettingsHint`'s regex split) already handles
this; no component change needed, just the string.

### 6. Correct the PATH placeholder to the documented real default

The env-var value field's placeholder is currently `/opt/homebrew/bin:/usr/bin`. `docs/guide.adoc`
documents AeroSpork's actual built-in fallback as:
```toml
[exec.env-vars]
    PATH = '/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}'
```
and explicitly calls out `${ENV_VAR}` substitution as a supported feature. The current
placeholder is close but wrong in two ways: it's missing `/opt/homebrew/sbin`, and — more
importantly — it doesn't demonstrate `${PATH}` substitution at all, which is the one syntax
detail a user is least likely to guess on their own. Change the placeholder to
`/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}` in both `SettingsField("Variable value", prompt:
..., ...)` (Swift) and the matching `TextField placeholder="..."` (JSX). Since placeholders are
real examples per the design system's own rule, this makes the placeholder both correct and a
teaching moment for substitution syntax in one edit.

## Considered and rejected

- **Nesting the three "focus changed" sections under one shared header**, to show that they're
  three flavors of one concept. Rejected: `Form`/`.formStyle(.grouped)` doesn't support a clean
  header-above-header hierarchy without diverging from every other tab's flat list-of-`Section`s
  convention (General, Gaps, Events all currently read as flat). The four sections' distinct SF
  Symbols (`play.circle`, `rectangle.on.rectangle`, `display.2`, `scope`) already give enough
  visual differentiation; the win from nesting is small and the risk of reading as one-off tab
  restructuring — exactly what the prior synthesis pass flagged and dropped — is not worth it.
- **Reordering commands within a list** (drag handle or up/down arrows), even though order does
  matter (see #2 above). Rejected: no tab in the window has any reorder affordance today —
  `WorkspacesMonitorsTab.swift:105` has a comment explicitly avoiding a drag-handle-looking glyph
  because its rows *aren't* reorderable, i.e. the codebase deliberately keeps this concept out
  of the window entirely. Introducing the first reorder interaction anywhere in the Settings
  window, for a tab whose lists are usually one or two entries long, is new interaction
  infrastructure the brief didn't ask for and no other row list here has. If someone needs a
  specific order today, they get it by controlling the order they add rows in — that already
  works, it's just not documented, which #2 fixes with a sentence instead of a feature.
- **A "run now" / test button per command row.** Real pain point (you only find out a command is
  wrong when the event fires), but out of scope: it requires new Swift-side command-execution
  plumbing from the Settings GUI process (not just a UI change), and a stray click running a
  destructive `aerospork` command or shell command outside its intended trigger is a real
  footgun. Bigger than a tab-content redesign; flagging it here so it's not lost, not building
  it.
- **Live validation of typed commands** (e.g. flagging an unparseable command inline). Rejected
  for this pass: `ConfigurationViewModel` stores these rows as plain strings with no parse-time
  validation today, and no other tab in the window does inline command validation either. Adding
  it here first — new infrastructure, not an existing pattern being brought in line — is the
  same category of scope creep the prior synthesis pass explicitly excluded for a different
  reason (a11y's `RecorderView` font-scaling / `settingsAnnounce` proposal).

## Shared-component usage (for the reconciliation pass)

- `FormSection`, `SectionLabel`, `IconButton`, `TextField`, `Toggle`, `SettingsHint`, `Button`
  (borderless, for "Add command"/"Add variable") — all used exactly as already defined, no
  prop additions, no new components. `Toggle` is a genuinely new call site in this file (item 4
  above) — flagging explicitly since if another tab is *also* newly adopting `Toggle` in this
  round, there's nothing to reconcile (same component, same props), but if another tab invents
  its own toggle look in parallel, that's the collision this component exists to prevent.
- No new component proposed. Nothing here needs an extension to `IconButton`, `FormSection`, or
  any other shared primitive's API — every change is either a string (placeholders, footers) or
  a conditional render of an existing component (`SettingsHint` under the toggle).

## Fit at 780×520

No new fixed-width elements are introduced (the widest control remains the existing 150px
env-var name field), so nothing changes about horizontal fit — the tab was already comfortable
at 780px before this proposal and stays that way.

Vertically: this tab's `Form` already scrolls today — the shipped tab with four command
sections plus the env section already exceeds 520px of static content with more than a
handful of rows across all four sections, and that's the existing, accepted interaction model
(same as `KeyBindingsTab`, `WindowRulesTab`). This proposal adds, in the worst case (inherit
toggle on, which is the default):
- one extra sentence to the "After startup" footer (~1 line)
- one conditional `SettingsHint` row under the inherit toggle (~1–2 lines plus row padding)
- one extra sentence appended to the exec-environment footer (~1 line, may wrap)

That's roughly 60–90px added in the worst case, entirely absorbed by scrolling exactly like the
rest of the tab's content already is with multiple commands per section and several env vars.
Nothing is clipped, no control shrinks below its minimum, and no section becomes unusable — the
layout mechanics (`FormSection`'s card + footer stack) are unchanged from what's already
shipped and already handles this. I did not render a live screenshot (out of scope for this
proposal stage / no `.jsx` edits made), but the reasoning above is structural, not a guess: the
only things that grew are wrapped text in components that already handle overflow by wrapping
and scrolling.
