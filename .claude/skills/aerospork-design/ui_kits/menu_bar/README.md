# UI kit — menu bar & tiled desktop

Recreates `Sources/AppBundle/ui/MenuBar.swift` and `MenuBarLabel.swift`, plus a schematic tiled
desktop so the chips have something to describe.

- **Chips** are the menu bar label: one per workspace that holds windows or owns a monitor, filled
  when focused, a capsule for an active binding mode. Drawn, never SF Symbols.
- **The menu is a remote control**: jump to a workspace, leave a mode, pause tiling, Settings, Quit.
  Everything that is configuration lives in Settings — that is why there is no "Reload config" or
  "Open config" row here.
- **Pause tiling** swaps the label for `pause.circle.fill` and lets the windows float, which is
  what the real command does.
- The "service" mode link shows the capsule chip, which comes before the workspace chips, and the
  *Leave mode* row that only appears while a non-main mode is active.
- The "Break the config" link shows the two rows a config that failed to parse puts at the top:
  *Config not loaded — running defaults* and *Show config error…*.
- *Check for updates…* is in release builds only. A debug build has no update feed, so the row is
  not there.

Window contents are schematic stand-ins; the app never draws other apps' windows.
