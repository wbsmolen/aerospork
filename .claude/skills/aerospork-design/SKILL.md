---
name: aerospork-design
description: Use this skill to generate well-branded interfaces and assets for AeroSpork, either for production or throwaway prototypes/mocks/etc. Contains essential design guidelines, colors, type, fonts, assets, and UI kit components for protoyping.
user-invocable: true
---

Start with **`readme.md`** in this directory. It carries the content fundamentals (voice, casing,
error copy) and the visual foundations, and it is the part worth matching before any pixel. Then
explore the rest. `_ds_manifest.json` indexes every component, card and token.

Note the filename case: `readme.md` here is lowercase, while the per-directory `README.md` files
under `assets/icon/` and `ui_kits/*/` are uppercase.

## Which half of this you need

**Prototypes, mocks, slides, marketing.** Work in the web layer. Copy assets out and write static
HTML. `styles.css` pulls in every token, and `_ds_bundle.js` exposes the components on
`window.AeroSporkDesignSystem_078bd7`. The claude.ai design project builds `_ds_bundle.js` from the
`.jsx` sources. `dev-docs/architecture.md`, "Rebuild the design kit bundle", says how to change it.
Serve over HTTP rather than opening `file://`. The UI kits load their `.jsx` through Babel, and a
`file://` origin blocks that fetch, so the page stays blank.

**Production code.** The web components are a *recreation* of the shipping SwiftUI, not a source of
truth for it. The real product is:

| This skill | Production |
|---|---|
| `components/{controls,layout,feedback}/*` | `Sources/AppBundle/ui/SettingsChrome.swift` |
| `ui_kits/settings_app/*Tab.jsx` | `Sources/AppBundle/ui/ConfigurationTabs/*.swift` |
| `components/brand/WorkspaceChips.jsx` | `Sources/AppBundle/ui/MenuBarLabel.swift` |
| `components/layout/MenuPanel.jsx` | `Sources/AppBundle/ui/MenuBar.swift` |
| `assets/icon/AppIcon.appiconset/` | `resources/Assets.xcassets/AppIcon.appiconset/` |

Two rules hold on the Swift side, both enforced by `UIChromeConsistencyTest`:

- Shared chrome lives in `SettingsChrome.swift`. A pane uses what is there rather than adding a
  local copy of a badge, status readout, hint, +/- strip or empty state.
- Status symbols and tints come from `StatusLabel.Kind` / `Banner.Kind`, never string literals in
  a pane.

`dev-docs/architecture.md` explains why both exist.

Use SF Symbol names in Swift. The `Icon` component's Lucide shapes are a web-only substitution,
since SF Symbols cannot be redistributed, and a few (`display.2`, `rectangle.inset.filled`) are
loose matches.

If the user invokes this skill with no other guidance, ask what they want to build, then act as an
expert designer who outputs either HTML artifacts or production code, depending on the need.
