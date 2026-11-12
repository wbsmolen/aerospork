# UI kit — AeroSpork Settings

A recreation of the app's SwiftUI `Settings` scene (`Sources/AppBundle/ui/` in
[wbsmolen/aerospork](https://github.com/wbsmolen/aerospork)). Every pane, control and caveat string
is taken from the Swift source, not from a screenshot.

| File | Source it recreates |
|---|---|
| `App.jsx` | `ConfigurationWindow.swift` — banner + native pane-toolbar `TabView` |
| `GeneralTab.jsx` | `ConfigurationTabs/GeneralSettingsTab.swift` |
| `GapsTab.jsx` | `ConfigurationTabs/GapsSettingsTab.swift` (incl. `GapsPreview`) |
| `KeysTab.jsx` | `ConfigurationTabs/KeyBindingsTab.swift` (recorder, origin badge, conflict banner) |
| `MonitorsTab.jsx` | `ConfigurationTabs/WorkspacesMonitorsTab.swift` |
| `EventsTab.jsx` | `ConfigurationTabs/CallbacksTab.swift` |
| `RulesTab.jsx` | `ConfigurationTabs/WindowRulesTab.swift` |
| `RawTomlTab.jsx` | `ConfigurationTabs/RawTomlTab.swift` |
| `data.js` | Mock config state; monitor list includes a DisplayLink panel |

## What is interactive

Toolbar panes switch; toggles, pickers and number fields update live (the real app auto-saves on a
600ms debounce — there is no Save button); the Keys pane filters, records a shortcut, shows the
already-bound conflict, and Override copies a generated binding into the writable set; the Monitors
and Window Rules tables select, add and remove rows; the Raw TOML editor enables Revert/Apply only
when the text differs from disk.

The entry point accepts `tab`, `appearance`, `width`, `height`, and `banner` query parameters. The
reviewed contact sheets in `dev-docs/decisions/assets/` render every pane in light and dark at
880×620 and 780×520. Their Monitors sheets predate the arrangement schematic, so `MonitorsTab.jsx`
is the reference for that pane.

## Deliberately not modelled

Per-monitor gap arrays, monitor fingerprints other than UUID, key-code mapping presets — in the real
app these round-trip through the config writer but have no control, which is exactly why the Raw TOML
pane exists. `framed={false}` renders the window content without the macOS chrome.
