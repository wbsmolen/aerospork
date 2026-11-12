# Settings GUI — copy & micro-interaction proposal

Scope: copy and micro-interaction only, using the vocabulary already established in
`Sources/AppBundle/ui/SettingsChrome.swift` (colour-change-is-the-confirmation, faint-fill
hover/press, `StatusLabel`/`Banner`, the two content rules — "explain the consequence, not the
control" and "name the state, then the recovery"). No new components, no new animation
primitives, no new navigation. Every proposed string avoids exclamation marks, emoji, jokes,
marketing adjectives, and backticks inside `.help()` tooltips (SwiftUI's plain tooltip does not
render Markdown — only `SettingsHint`/`Banner`/section-footer `Text(LocalizedStringKey(...))` do).

Most of the window already holds the line well — the empty states in `WindowRulesTab`,
`WorkspacesMonitorsTab`, and most of `CallbacksTab`, the Gaps footer, and the `CopyButton`
checkmark are exactly the model to extend, not to change. This document flags the places that
fall short of that same bar, plus a few genuine feedback gaps.

---

## Summary — best three opportunities

1. **`KeyBindingsTab`'s "No matches" empty state states the problem and stops** — it never tells
   the user there's a one-click way out, even though that control (the filter's clear button)
   already exists two lines away. This is the clearest violation of "name the state, then the
   recovery" in the window.
2. **The "Inherit AeroSpork's environment" toggle in `CallbacksTab` has no help text at all**,
   despite the guide explicitly calling out why you'd turn it off: a config snippet copied from
   the internet otherwise runs with your whole shell environment, secrets included. This is the
   single highest-consequence silent control in the window.
3. **The monitor picker in `WorkspacesMonitorsTab` offers two options for the same monitor
   ("LG UltraFine" and "LG UltraFine — this exact monitor") but only labels one of them** — so the
   plain option's actual behaviour (matches by name, could hit either of two identical panels) is
   never stated. This is "explain the consequence, not the control" failing on the one row in the
   window where getting it wrong silently repoints a workspace to the wrong physical screen.

All three are exact-string, no-new-component fixes. Detail below, in file order.

---

## Findings

### 1. `KeyBindingsTab.swift:139-149` — "No matches" empty state has no recovery

**Current:**
```
title: "No matches"
message: "Nothing in “\(selectedMode)” matches “\(query)”."
```
(`ContentUnavailableViewCompat`, `messageIsMarkdown: false` because `query` is user-typed.)

**Why it falls short:** every other empty state in this window either offers an action button
(`WorkspacesMonitorsTab`'s "Add assignment", `WindowRulesTab`'s "Add rule") or points at the
control that fixes it. This one just restates that nothing matched. The recovery — clear the
filter — is a single existing control (the `xmark.circle.fill` button beside the filter field,
`KeyBindingsTab.swift:113-117`) that the empty state doesn't mention or wire to.

**Proposed:** reuse `ContentUnavailableViewCompat`'s existing `actionTitle`/`action` parameters
(already used elsewhere in this same file and in `WorkspacesMonitorsTab`/`WindowRulesTab` — no
new API):

```swift
ContentUnavailableViewCompat(
    icon: query.isEmpty ? "keyboard" : "magnifyingglass",
    title: query.isEmpty ? "“\(selectedMode)” has no bindings" : "No matches",
    message: query.isEmpty
        ? "Record a shortcut below to add the first one."
        : "Nothing in “\(selectedMode)” matches “\(query)”.",
    messageIsMarkdown: query.isEmpty,
    actionTitle: query.isEmpty ? nil : "Clear filter",
    action: query.isEmpty ? nil : { query = "" },
)
```

Message text is unchanged (still correct and still not rendered as Markdown, since `query` is
user input) — only the action button is new, and it calls the same `query = ""` the existing
clear button already calls.

**Tag:** safe — ship this pass.

---

### 2. `CallbacksTab.swift:39` — "Inherit AeroSpork's environment" toggle has no help text

**Current:**
```swift
Toggle("Inherit AeroSpork's environment", isOn: viewModel.binding(\.execInheritEnvVars))
```
No `.help()`. The section footer two elements down only says: *"`exec-and-forget` and every
command above run with this environment. `PATH` is the one people usually need."* — true, but it
describes the section as a whole, not what flipping this specific toggle off costs you.

**Why it falls short:** `docs/guide.adoc:222-226` states the actual stakes plainly: *"AeroSpork
inherits the app's own environment... including any secrets in it. That is deliberate: a callback
that posts to Slack needs its token. But it means a config snippet copied from the internet runs
with everything your shell has."* That is exactly the kind of "why you would care" the design
system asks for, and it is currently nowhere in the GUI — only in the docs site.

**Proposed:** add `.help()` to the toggle itself (plain text, no backticks — `.help()` doesn't
render Markdown):

```swift
Toggle("Inherit AeroSpork's environment", isOn: viewModel.binding(\.execInheritEnvVars))
    .help("Off, exec commands and callbacks only see the variables listed below — not your shell's PATH or any secrets in your environment.")
```

**Tag:** safe — ship this pass.

---

### 3. `WorkspacesMonitorsTab.swift:106-113` — the two monitor-matching options are asymmetric

**Current:**
```swift
ForEach(viewModel.liveMonitors) { m in
    Text(m.name).tag(m.name)
    if let uuid = m.uuid { Text("\(m.name) — this exact monitor").tag(uuid) }
}
```
For a monitor with a UUID, the picker offers two rows: `LG UltraFine` and
`LG UltraFine — this exact monitor`. Only the second says what it does.

**Why it falls short:** this is the one control in the window where silently picking the "wrong"
of two visually near-identical options has a real consequence — two identical external monitors
both named `LG UltraFine` will both match the plain-name option, so a workspace pinned "to this
monitor" can land on its twin. The UUID option already explains its own behaviour
("this exact monitor"); the name option, sitting right above it, explains nothing, which reads as
the default/safe choice rather than the looser one.

**Proposed:** only touch the name-only label, and only when a UUID sibling exists to contrast
against (when there's no UUID there's nothing to disambiguate, so leave it as the bare name):

```swift
ForEach(viewModel.liveMonitors) { m in
    Text(m.uuid == nil ? m.name : "\(m.name) — matches by name").tag(m.name)
    if let uuid = m.uuid { Text("\(m.name) — this exact monitor").tag(uuid) }
}
```

**Tag:** safe — ship this pass.

---

### 4. `GeneralSettingsTab.swift:28-32` — disabled "Show icon in the Dock" toggle explains nothing at the point of interaction

**Current:**
```swift
Toggle("Show icon in the Dock", isOn: Binding(
    get: { viewModel.appVisibility.showsDockIcon },
    set: { viewModel.binding(\.showDockIcon).wrappedValue = $0 },
))
.disabled(viewModel.appVisibility.dockIconIsForced)
```
No `.help()`. The explanation exists, but only as the section footer six lines below: *"Both
icons off would leave no way into Settings, so the Dock icon is kept."*

**Why it falls short:** a disabled control with no tooltip is a dead end at the exact moment a
user is trying to interact with it — the 40% opacity says "you can't," not "here's why." The
"consequence, not control" rule is being followed *near* the control instead of *on* it.

**Proposed:**
```swift
.disabled(viewModel.appVisibility.dockIconIsForced)
.help(viewModel.appVisibility.dockIconIsForced
    ? "Both icons off would leave no way into Settings, so the Dock icon is kept."
    : "")
```
(Same sentence the footer already uses — this isn't new copy, just the existing explanation
surfaced where the click actually happens. Leave `.help("")` — effectively no tooltip — when the
toggle is enabled, since the footer already covers the pair relationship for that case and the
toggle itself needs no extra text when it's simply interactive.)

**Tag:** safe — ship this pass.

---

### 5. `WindowRulesTab.swift:89-93` — "App name" and "Window title" fields never say they're regular expressions

**Current:**
```swift
LabeledContent("App name") {
    SettingsField("App name", prompt: "^Finder$", text: field(i, \.appNameRegex))
}
LabeledContent("Window title") {
    SettingsField("Window title", prompt: "^Preferences$", text: field(i, \.windowTitleRegex))
}
```
The only hint that these are regexes, not substrings, is the `^…$` in the placeholder — which a
user who wants to match "Preferences" literally could easily read as decorative rather than
syntactic. The section footer explains empty matchers and points at `list-apps`, but never says
"regular expression."

**Why it falls short:** this is a format the user needs to know before they type, not after —
closer to "explain the consequence" than a pure label problem: typing `Preferences` instead of
`^Preferences$` will match every window whose title *contains* "Preferences," not just that one,
which is a silent behavioural surprise rather than a validation error.

**Proposed:** add `.help()` to each field (plain text, tooltip doubles as the accessibility label
per the existing rule):

```swift
LabeledContent("App name") {
    SettingsField("App name", prompt: "^Finder$", text: field(i, \.appNameRegex))
        .help("Regular expression matched against the app's display name.")
}
LabeledContent("Window title") {
    SettingsField("Window title", prompt: "^Preferences$", text: field(i, \.windowTitleRegex))
        .help("Regular expression matched against the window's title.")
}
```

**Tag:** safe — ship this pass.

---

### 6. `GeneralSettingsTab.swift:63-69` — normalization toggles explain the group, not themselves

**Current:**
```swift
Toggle("Flatten single-child containers", isOn: viewModel.binding(\.enableNormalizationFlattenContainers))
Toggle("Alternate orientation for nested containers", isOn: viewModel.binding(\.enableNormalizationOppositeOrientation))
```
Footer: *"Housekeeping applied after every layout change. Turn both off if you want the tree to
stay exactly as you built it."* — true of the pair, but neither toggle's own label states what it,
individually, changes about what you see on screen. "Flatten single-child containers" and
"Alternate orientation for nested containers" are tree-jargon labels a user would have to toggle
and watch to understand.

Verified against `docs/guide.adoc:308-355`, which gives the exact mechanism each one performs, so
this proposal is not guessing at behaviour:

**Proposed:**
```swift
Toggle("Flatten single-child containers", isOn: viewModel.binding(\.enableNormalizationFlattenContainers))
    .help("A container left holding a single window collapses into its parent, instead of sitting in the tree as an empty wrapper.")
Toggle("Alternate orientation for nested containers", isOn: viewModel.binding(\.enableNormalizationOppositeOrientation))
    .help("A container nested inside one with the same split direction is flipped to the other direction, so two splits in a row don't produce two equally thin slices.")
```

**Tag:** safe — ship this pass (wording is grounded in `docs/guide.adoc`'s own two normalization
examples, not invented).

---

### 7. `CallbacksTab.swift:102-108` — the shared "Remove" tooltip never names what it removes

**Current:**
```swift
private func removeButton(_ action: @escaping () -> Void) -> some View {
    Button(role: .destructive, action: action) { Image(systemName: "minus.circle") }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Remove")
        .accessibilityLabel("Remove")
}
```
Used identically for every env-var row and every command row across four command sections. With
several rows in a list, every one of these controls says exactly "Remove" — indistinguishable
from its neighbours by tooltip or VoiceOver.

**Why it falls short:** the design system's own rule is explicit — *"Tooltips double as
accessibility labels, so they are written as names."* `KeyBindingsTab` already does this
correctly one file over (`"Remove this binding"` / `"Remove \(b.key)"`,
`KeyBindingsTab.swift:169-172`); `CallbacksTab`'s shared helper is the one place in the window
that regressed to the generic form the design doc calls out as the thing to avoid.

**Proposed:** thread the row's own content through as the label, falling back to a generic term
only for a still-blank row:

```swift
private func removeButton(_ help: String = "Remove", _ action: @escaping () -> Void) -> some View {
    Button(role: .destructive, action: action) { Image(systemName: "minus.circle") }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
}
```
Call sites:
```swift
// env var row
removeButton(row.name.isEmpty ? "Remove variable" : "Remove “\(row.name)”") { … }

// command row (inside commandSection, used by all four sections)
removeButton(row.command.isEmpty ? "Remove command" : "Remove “\(row.command)”") { … }
```

**Tag:** safe — ship this pass.

---

### 8. `KeyBindingsTab.swift:74-76` — "Delete mode" states the control, not the consequence

**Current:**
```swift
Button("New mode…") { addingMode = true }
Button("Delete “\(selectedMode)”", role: .destructive) { removeMode() }
    .disabled(!viewModel.canRemoveMode(selectedMode))
```
This fires immediately — no confirmation dialog anywhere in this window, for any delete, so this
isn't proposing to add one (that would be new interaction machinery, out of scope). But right now
the only information in front of the user at the moment of an irreversible click is the mode's
*name* — not that deleting it also deletes every binding written under it.

**Why it falls short:** every other place in this window that's about to discard something
explains the size of what's being discarded first (the summary line: *"12 generated by mod, 4
written in your config"*). Mode deletion is the one destructive action that doesn't, and it's the
most destructive one in the tab — it can take an arbitrary number of bindings with it in one
click, with nothing to undo.

**Proposed:** count only the *written* bindings (the ones actually lost — generated ones aren't
"yours" to lose, matching the vocabulary the summary line already uses), and put the count in the
menu item itself:

```swift
private var writtenBindingCount: Int {
    viewModel.displayBindings(mode: selectedMode).count { $0.origin == .explicit }
}
...
Button(
    writtenBindingCount == 0
        ? "Delete “\(selectedMode)”"
        : "Delete “\(selectedMode)” — \(writtenBindingCount) binding\(writtenBindingCount == 1 ? "" : "s")",
    role: .destructive,
) { removeMode() }
    .disabled(!viewModel.canRemoveMode(selectedMode))
```

No ellipsis added — this still fires immediately, so the existing "ellipsis only on things that
open something further" convention is unaffected.

**Tag:** bigger swing — same interaction, but it's a menu item whose label now depends on
`viewModel` state computed at menu-build time rather than a static string; worth a second look
from whoever owns `KeyBindingsTab`'s perf assumptions (the tab already recomputes `allRows`
per body evaluation, so this adds one more `count` over the same array, not a new query — but
flagging since it's the one item here that isn't a pure string edit).

---

## Reviewed, holds up — no change proposed

Called out explicitly because the brief asked me to verify flagged candidates, not just repeat
them:

- **`CopyButton`'s checkmark state** (`SettingsChrome.swift:439-461`) — the 1.4s hold, the
  colour-only confirmation, the accessibility label swap to "Copied". This is the reference
  implementation for everything above; it needed nothing.
- **The conflict banner in `KeyBindingsTab.swift:279-299`** — "\(key) is already bound to
  \(command)" plus a "Show" button that filters the list to the conflicting row. The "Add" →
  "Replace" button-label swap (`KeyBindingsTab.swift:250`) already tells the user what the click
  will do, so the banner doesn't need to repeat it. Holds up.
- **The armed key-recorder placeholder copy** ("Click to record" / "Press a shortcut…",
  `KeyBindingsTab.swift:440`) — both are imperative and specific, not filler. Holds up.
- **Every `ContentUnavailableViewCompat` in `WorkspacesMonitorsTab` and `WindowRulesTab`** — all
  already teach the feature and name a recovery action. No changes.
- **The Gaps tab's outer-gap footer and per-monitor-gap footer** — both already the two best
  examples of the two content rules in the window; the per-monitor one was visibly hand-tuned to
  work around a Markdown parsing limitation (see its own comment) and shouldn't be touched again.
- **`RawTomlTab`'s status readout** (`RawTomlTab.swift:104-118`) — already uses `StatusLabel`'s
  established ok/neutral/error vocabulary correctly, with no toast anywhere near it.

---

## Declined ideas (guardrail check)

Things a "whimsy" pass would normally reach for, considered and rejected because they don't fit
this app's stated voice:

- **A scale/bounce or confetti-style flourish on `CopyButton` success.** Declined —
  "nothing scales or bounces" is explicit, and the checkmark colour change is already stated to
  be *the entire confirmation*. Adding motion on top of it would contradict the one sentence in
  the design doc written specifically about this control.
- **A friendlier or jokier empty-state line** (e.g. something like "Nothing here yet — go make
  some shortcuts!"). Declined — no exclamation marks, no jokes, and empty states in this window
  are held to a specific bar (teach the feature in one flat sentence), not a tone bar. Every
  empty-state fix proposed above adds information (a recovery action), never personality.
  Similarly considered and declined for the "No matches" filter state (finding 1): rejected a
  cute miss-search line in favor of a literal, useful "Clear filter" action.
  KeyBindingsTab's "No modes" bare-text state (`KeyBindingsTab.swift:51`) was also considered for
  a fuller empty-state treatment and declined for the opposite reason: it's a word in a compact
  toolbar strip, not a content pane — `ContentUnavailableViewCompat`-style teaching copy would be
  out of place at that size and in that role, and this state is effectively unreachable in
  practice (a mode registry always has at least the main mode).
- **A shake or red-flash on the key recorder when a re-key conflict is entered inline**
  (as opposed to the composer's conflict banner, which already exists). Declined for two reasons:
  motion again ("nothing scales or bounces"), and it would require inventing a new *error* visual
  state on `KeyRecorderField` — today it only has idle/armed, and adding a third state is a
  component change, out of scope for a copy/micro-interaction pass. The existing bottom-banner
  error text already names the conflicting key and the recovery ("Edit or remove that binding
  first"), which is the copy-only fix available here.
- **A confirmation modal or an "Undo" affordance for mode deletion.** Declined — this app has no
  modal surface and no toast/undo surface anywhere ("AeroSpork has no notification surface at
  all"); introducing one for this single action would be the biggest voice break in the whole
  proposal. Addressed instead with finding 8: name the stakes in the menu item *before* the
  click, since the click itself can't be softened without new components.
- **A small progress/achievement badge for filling out a first keymap or first window rule**
  (classic onboarding gamification). Declined outright — this is a config editor for a tiling
  window manager aimed at people who already know what a tree layout is; a badge or celebration
  surface would read as aimed at the wrong audience entirely, and again, there is no notification
  surface to hang it on.
- **Colour-coding rows in the Window Rules table or Key Bindings list by "freshness" or
  "recently edited."** Declined — colour in this system "carries meaning only: red = config not
  loaded, orange = warning, green = valid." Repurposing colour for a non-status signal would
  dilute the one channel the app uses for something safety-critical (is your config actually
  loaded).

---

## Files referenced

- `Sources/AppBundle/ui/SettingsChrome.swift`
- `Sources/AppBundle/ui/ConfigurationTabs/GeneralSettingsTab.swift`
- `Sources/AppBundle/ui/ConfigurationTabs/GapsSettingsTab.swift`
- `Sources/AppBundle/ui/ConfigurationTabs/KeyBindingsTab.swift`
- `Sources/AppBundle/ui/ConfigurationTabs/WorkspacesMonitorsTab.swift`
- `Sources/AppBundle/ui/ConfigurationTabs/CallbacksTab.swift`
- `Sources/AppBundle/ui/ConfigurationTabs/WindowRulesTab.swift`
- `Sources/AppBundle/ui/ConfigurationTabs/RawTomlTab.swift`
- `Sources/AppBundle/ui/ConfigurationWindow.swift`
- `docs/guide.adoc` (grounding for findings 2 and 6)
