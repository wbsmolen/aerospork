# App icon

This is the shipping app icon. The files in `AppIcon.appiconset/` are byte-identical to
`resources/Assets.xcassets/AppIcon.appiconset/`, which the release build compiles.

The mark is the **layout**, not a letter: one focused pane left, three stacked panes right. It comes
from the repo's original `generate-app-icon.py` (since removed), with the two constraints that shaped
it:

- It must read at 16 pt in the Finder sidebar. Few, large shapes and generous gaps: the icon before
  it drew a 3×3 line grid, which turned to mush below 32 pt.
- macOS icons are squircles with a corner ratio of about 22%, and the artwork is **inset**, not full
  bleed. Here: 5.5% canvas inset, corner radius 22.5% of the plate.

## Layers (Icon Composer order, bottom to top)

| Layer | What it is |
|---|---|
| 1 — Plate | Vertical gradient `#1C202C → #10121A`, squircle, inset 5.5% |
| 2 — Top light | Radial white 20% from 28% / −10%, gone by 62%: the light source |
| 3 — Panes | Focused pane: `#82B7FF → #3D80EA → #2F6ED6` at 170°, plus a top specular wash and a 1px white inner top edge. Dimmed panes: white 17% → 7.5% glass with a white 16% inner border |
| 4 — Rim / bevel | Inset ring: white 14% all round, white 22% top edge, black 50% bottom edge |

Geometry inside the plate: 20% padding, 6.2% gaps, tile radius 4.5% of the plate. The focused pane
takes 56% of the usable width and full height.

## Variants

| File | Use |
|---|---|
| `aerospork-icon-1024.png` | Default (dark plate): the app icon |
| `aerospork-icon-light-1024.png` | Light plate — for dark documentation backgrounds and light-mode marketing |
| `aerospork-icon-mono-1024.png` | Monochrome / tinted — macOS tinted-icon appearance, print, favicons |
| `AppIcon.appiconset/` | Xcode asset catalog, 16→512 @1x/@2x, generated from the 1024 default |

## Rebuilding

`AppIcon.html` is the specimen of all three variants. `render.html` draws each variant at 1024 px
with no outer shadow, on a transparent canvas. The shipping icon exists in four places, and all of
them come from the default variant:

| File | Used by |
|---|---|
| `resources/Assets.xcassets/AppIcon.appiconset/` | The release build (`project.yml`, `ASSETCATALOG_COMPILER_APPICON_NAME`) |
| `resources/AppIcon.icns` | The debug bundle (`build-debug-app.sh`) |
| `AppIcon.appiconset/` here | This design kit |
| `updates-site/icon.png` (256 px) | The hosted site |

1. Open `render.html` in a browser, over HTTP.
2. Take a screenshot of `#r-default`, `#r-light` and `#r-mono` at a device scale factor of 1, with a
   transparent background. A headless browser such as Playwright does this. Save them as the three
   `aerospork-icon-*-1024.png` files.
3. Make each size of the asset catalog from the default 1024 px file. For example:
   `sips -z 512 512 aerospork-icon-1024.png --out AppIcon.appiconset/icon_256x256@2x.png`. The file
   names use Apple's `@2x` convention, and `Contents.json` matches them.
4. Copy `AppIcon.appiconset/*.png` and `Contents.json` to `resources/Assets.xcassets/AppIcon.appiconset/`.
5. Build `resources/AppIcon.icns`: copy the PNG files into a folder named `AppIcon.iconset`, then run
   `iconutil -c icns AppIcon.iconset -o resources/AppIcon.icns`.
6. Make `updates-site/icon.png` at 256 px with `sips -z 256 256`.

The catalog PNG files come from the 1024 px file by downsampling. Below 32 px the glass detail adds
nothing that you can see. The 16 px and 32 px sizes ship as downsampled. To improve them, draw them
again without the specular and rim layers.

## Other brand artwork here

- `Banner.html` → `readme-banner-1280x640.png` — GitHub README / social header.
- `AppStoreHero.html` → `appstore-hero-1440x900.png` — App Store / landing hero, with a schematic
  tiled desktop rather than a real screenshot (App Store screenshots should be real captures; frame
  them with `WindowChrome`).
