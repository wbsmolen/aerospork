repo: wbsmolen/aerospork
branch: main

## Last sync

date: 2026-07-29T16:42:05Z

### Updated in this project

- Built the design system from the Swift UI layer: tokens, 32 components, three UI kits.
- Recreated the seven-pane native-toolbar Settings window from `Sources/AppBundle/ui/` (all panes,
  real caveat copy, light/dark and ideal/compact states).
- Generated a new layered (Icon Composer style) app icon set plus README banner and App Store hero.
- Imported the shipped app icon and `docs/assets/` product screenshots and monitor diagrams.

### Applied back to the repo

The audit found the Swift already matched this system almost everywhere — unsurprising, since the
system was derived from it. What did not match was fixed in the repo, not here:

- `MenuBarLabel.swift` chip font ratio `0.72` → `0.62`, matching
  `components/brand/WorkspaceChips.jsx`. The chip rasterizes at 40pt and scales to the menu bar's
  ~22pt, where 0.72 reads oversized next to the ~14pt clock. Every other chip number (gap, border,
  radius, inactive opacity) already agreed exactly.
- `Badge`, `StatusLabel` and `Banner` promoted into `SettingsChrome.swift`. All three existed, but
  as `private` structs or inline view builders, so the two badges had drifted to different paddings
  (6/2 vs 5/1) and only one carried an accessibility label. Both now share the geometry this system
  specifies, differing only in tone.
- `CopyButton` now tints its checkmark green on copy, per `components/controls/CopyButton.jsx`. The
  colour change is the whole confirmation: the product has no toast anywhere.
- The settings kit and Swift implementation now share the native pane toolbar, monitor-arrangement
  schematic, guided Rules controls, cross-mode Keys search, and AppKit Raw TOML editor behavior.
  `dev-docs/decisions/` records why (ADRs 0001 to 0005 and 0009), and `dev-docs/decisions/assets/`
  holds the reviewed contact sheets.

`UIChromeConsistencyTest` pins all of it, including the chip ratio, so the two sides cannot drift
apart silently.

## Screen map

| Project screen / file | Repo files it was built from |
|---|---|
| `ui_kits/settings_app/App.jsx` | `Sources/AppBundle/ui/ConfigurationWindow.swift` |
| `ui_kits/settings_app/GeneralTab.jsx` | `Sources/AppBundle/ui/ConfigurationTabs/GeneralSettingsTab.swift` |
| `ui_kits/settings_app/GapsTab.jsx` | `Sources/AppBundle/ui/ConfigurationTabs/GapsSettingsTab.swift` |
| `ui_kits/settings_app/KeysTab.jsx` | `Sources/AppBundle/ui/ConfigurationTabs/KeyBindingsTab.swift` |
| `ui_kits/settings_app/MonitorsTab.jsx` | `Sources/AppBundle/ui/ConfigurationTabs/WorkspacesMonitorsTab.swift` |
| `ui_kits/settings_app/EventsTab.jsx` | `Sources/AppBundle/ui/ConfigurationTabs/CallbacksTab.swift` |
| `ui_kits/settings_app/RulesTab.jsx` | `Sources/AppBundle/ui/ConfigurationTabs/WindowRulesTab.swift` |
| `ui_kits/settings_app/RawTomlTab.jsx` | `Sources/AppBundle/ui/ConfigurationTabs/RawTomlTab.swift` |
| `ui_kits/menu_bar/MenuBarKit.jsx` | `Sources/AppBundle/ui/MenuBar.swift`, `MenuBarLabel.swift` |
| `ui_kits/cli/CliKit.jsx` | `docs/aerospork-list-monitors.adoc`, `docs/commands.adoc`, `README.md` |
| `components/controls/*`, `components/layout/*`, `components/feedback/*` | `Sources/AppBundle/ui/SettingsChrome.swift` (+ the tabs above) |
| `components/brand/WorkspaceChips.jsx` | `Sources/AppBundle/ui/MenuBarLabel.swift` |
| `components/brand/GapsPreview.jsx` | `Sources/AppBundle/ui/ConfigurationTabs/GapsSettingsTab.swift` |
| `tokens/*.css` | The SwiftUI source's literal metrics + macOS system semantic colors |
| `assets/icon/*` | `generate-app-icon.py`, `resources/Assets.xcassets/AppIcon.appiconset/` |
| `assets/product/*` | `docs/assets/` |
| `readme.md` (content + visual foundations) | `README.md`, `CLAUDE.md`, `docs/config-examples/default-config.toml` |
