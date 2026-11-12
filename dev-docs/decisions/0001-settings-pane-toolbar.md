# 0001. A native pane toolbar for the Settings window

- Status: accepted
- Date: 2026-08-02
- Enforced by: `UISettingsTest.testSettingsPaneMetadataIsCompleteAndStable` (pane order, titles, symbols), `UISettingsTest.testSettingsUiStaysWithinTheMacOS13Floor`. Review only for the layout.
- Code: `Sources/AppBundle/ui/ConfigurationWindow.swift` (`TabView`, `SettingsPane`, `settings.selectedPane`)

## Context

The Settings window has seven peer panes: General, Gaps, Keys, Monitors, Events, Window Rules and Raw TOML.
None of them contains another, so the window has no hierarchy to show.
A sidebar in the style of System Settings uses about 180 points of width all the time.
That makes the minimum width about 20% larger, and the window then looks like a document browser.

## Decision

The Settings window shows its seven panes as a native `TabView` pane toolbar, with an SF Symbol above a short label.

## Consequences

- The window keeps its 880×620 ideal size and its 780×520 minimum size (see [0003](0003-settings-window-resizable.md)).
- AeroSpork remembers the selected pane in `settings.selectedPane`, and the title of that pane becomes the window title. A stored value that names no pane selects General.
- Each pane uses grouped forms, inset tables, hairline separators, semantic system colors and SF Symbols. A pane has no display title of its own, because the toolbar item and the window title already name it. General stays one scrolling form, not a two-column dashboard.
- A pane symbol must exist in SF Symbols on macOS 13. A newer symbol renders as a blank toolbar icon on macOS 13 without an error. This is why Gaps uses `rectangle.split.3x3` and not `square.resize`.
- An eighth pane, or a pane that contains other panes, is a reason to reconsider this decision.

## Alternatives considered

- A System Settings sidebar: it makes the minimum width about 20% larger and suggests a hierarchy that the panes do not have.

## Reference renders

The design kit in `.claude/skills/aerospork-design/ui_kits/settings_app/` rendered these contact sheets before the panes were built.
They show every pane in both appearances, at the ideal size and the minimum size:

- [Light, 880×620](assets/settings-light-ideal.png)
- [Dark, 880×620](assets/settings-dark-ideal.png)
- [Light, 780×520](assets/settings-light-compact.png)
- [Dark, 780×520](assets/settings-dark-compact.png)

The Monitors sheets are out of date. They show the monitor list that the arrangement schematic later replaced.
For the Monitors pane, `MonitorsTab.jsx` in the kit is the current reference. The Swift is the source of truth for every pane.
