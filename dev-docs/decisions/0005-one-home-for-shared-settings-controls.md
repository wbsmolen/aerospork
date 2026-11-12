# 0005. One home for every shared Settings control

- Status: accepted
- Date: 2026-08-02
- Enforced by: `UIChromeConsistencyTest`
- Code: `Sources/AppBundle/ui/SettingsChrome.swift`

## Context

Before this decision, each pane built its own icon buttons, badges, headers and status lines.
The copies drifted: two badges had different padding, only one of them had an accessibility label, and three panel headers had three different sets of padding.
A first proposal added a `RowRemoveButton` next to a general `IconButton`, which made two controls for one job in the same change.

## Decision

`SettingsChrome.swift` holds the only copy of each control that more than one pane uses, and a pane uses that copy and does not build its own.

## Consequences

- `IconButton` is the one symbol-only button. Its `help` text is also its accessibility label, so VoiceOver never reads only "button". `RowRemoveButton` was never built.
- `PanelHeader` has a fixed padding of 16 points at the sides, 14 at the top and 8 at the bottom. The 16 points match the header that `.formStyle(.grouped)` gives a form section, so a header stays in the same place when the user changes from a pane with a form to a pane without one.
- Status symbols and tints come from `StatusLabel.Kind` and `Banner.Kind`, never from a string literal in a pane. A section footer is a `SettingsHint`.
- `settingsHitTarget()` gives a small control a hit area of at least 24×24 points, and `settingsAnnounce(_:)` announces a change of state that does not move the focus. The first round of the redesign put both out of scope. Both shipped later.
- `CodeEditor` is not shared. Only Raw TOML uses it, so it stays in `RawTomlTab.swift` (see [0009](0009-raw-toml-editor.md)).
- A new shared control needs a change to `SettingsChrome.swift`, and often a new rule in `UIChromeConsistencyTest`. That cost is deliberate.

## Alternatives considered

- Controls local to each pane: they drift, as the badges and headers did.
- `RowRemoveButton` next to `IconButton`: `IconButton` already does everything that `RowRemoveButton` would do.
