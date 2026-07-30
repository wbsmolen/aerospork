# Architecture

## Definitions

**SPM.** Swift package manager and Swift build tool. In other words, `swift` CLI tool

## High level project infrastructure overview

- `../Sources`.
  The majority of AeroSpork source code. Managed by SPM `../Package.swift`
- `../Sources/AppBundle/`.
  The AeroSpork.app server. An SPM library, exposed to the `aerosporkApp` executable target.
- `../Sources/aerosporkApp/`.
  Thin app entry point (`@main`). SPM can't build a macOS App Bundle, so the release build is produced via the
  generated Xcode project. The Xcode project model lives in `../aerospork.xcodeproj/` and is generated from the
  `../project.yml` "skeleton" by `./generate.sh`. Keep as much code as possible in the `AppBundle` library.
- `../Sources/Cli/`.
  CLI client. Built purely with SPM; Xcode is not involved.
- `../Sources/Common/`.
  Shared code between server and client (command-line args parsing, util functions, and the native Unix-socket IPC).
- `../Sources/AppBundleTests/` and `../Sources/CommonTests/`.
  The two test targets. Both are headless.
- `../docs/`.
  Documentation sources for site and man pages in Asciidoc format https://asciidoc.org/

## client/server interaction

`aerospork` CLI binary is client. `AeroSpork.app` is server. Client and server talk to each other via predefined UNIX file.

Each time you run a CLI command:
1. Args are parsed by the client, args parsing errors are reported if any. Help is shown if `-h`/`--help` is passed.
1. If args are parsed successfully, the args are send to the server
1. Server parses the args once again, and runs the command
1. Server returns stdout, stderr, and exit code to the client
1. Client shows stdout, stderr, and ends the process with the requested exit code

## Commands subsystem

todo

../Sources/AppBundle/command/
../Sources/Common/cmdArgs/

Command checklist:
- [ ] Documentation in `../docs/aerospork-*` and `../docs/commands.adoc`
  - [ ] Check that site looks alright `./.site/commands.html`
  - [ ] Check that man page looks alright `./.man`
- [ ] Do `--window-id` and/or `--workspace` flags make sense for the command?
- [ ] Shell completion `../grammar/commands-bnf-grammar.txt`

## TOML Config parse subsystem

todo

../Sources/AppBundle/config/

## Tree Model subsystem

todo

../Sources/AppBundle/tree/

## Layout subsystem

todo

../Sources/AppBundle/layout/

## UI subsystem

../Sources/AppBundle/ui/

Two surfaces, and neither is a window the app owns:

- **`MenuBarExtra`** (`MenuBar.swift`, `MenuBarLabel.swift`). The menu is a *remote control*, not a
  control panel: jump to a workspace, leave a binding mode, pause tiling, open Settings, quit.
  Anything that is configuration lives in Settings, which is why there is no "Reload config" or
  "Open config" row. The label is drawn chips, rasterized by `ImageRenderer` at 40pt and scaled
  down, never `N.square.fill` SF Symbols, which only exist for 0…50 and single capitals, so a
  workspace named `web` would have looked nothing like one named `3`. It follows the *menu bar's*
  appearance, which is not always the app's.
- **A SwiftUI `Settings` scene** (`ConfigurationWindow.swift` + `ConfigurationTabs/`), seven tabs
  over one `ConfigurationViewModel`. Structured tabs auto-save on a 600ms debounce; Raw TOML
  applies explicitly. The view model is a lossy projection of the config, which is why the writer
  guards each section on an `…Edited` flag; see the writer invariant in `CLAUDE.md`.

**`SettingsChrome.swift` owns every shared control.** `NumberField`, `SettingsHint`,
`SettingsFooter`, `ListActionBar`, `ContentUnavailableViewCompat`, `SectionLabel`, `Badge`,
`StatusLabel`, `Banner`, `CodeEditor`, `CopyButton`. Nothing there holds state or touches the
config; it is presentation only.

That file exists because of a specific decay pattern. The tabs were written at different times, and
each time one needed a small piece of chrome and didn't find it, it grew its own: three hand-rolled
+/- rows, caveat text in three different places, and two badges at two paddings (6/2 and 5/1) where
only one set a foreground colour or an accessibility label. `UIChromeConsistencyTest` scans `ui/`
for stray `Capsule()` badges and hardcoded status symbols, so a new one fails the test.

`StatusLabel.Kind` and `Banner.Kind` own the symbol/tint pairings. Red and green are the most
confusable pair on screen, so the symbol has to differ too, and that decision is made once rather
than per call site.

The web recreation of all of this — tokens, components, three click-through UI kits — lives in
`.claude/skills/aerospork-design/`. It is derived from this directory, so treat the Swift as the
source of truth and the web layer as documentation plus a prototyping surface.
