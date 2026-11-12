# 0004. Opaque content, and system materials only on system chrome

- Status: accepted
- Date: 2026-08-02
- Enforced by: review only
- Code: `.background(.bar)` in `SettingsChrome.swift` (`SettingsFooter`, `ListActionBar`), `KeyBindingsTab.swift`, `RawTomlTab.swift` (path bar, action bar)

## Context

AeroSpork supports macOS 13 through macOS 27.
On newer releases, the system draws Liquid Glass on its own controls and navigation chrome. It is not a background for content.
Text in a form, a table or an editor is harder to read on a translucent background.
An imitation of Liquid Glass painted by the app looks wrong on the releases that do not have it, and it falls behind the real one on the releases that do.

## Decision

Forms, tables and editors in the Settings window stay opaque, and only system-supplied chrome, such as the toolbar and the `.bar` material of the path and action bars, uses a system material.

## Consequences

- Native SwiftUI and AppKit controls bring the newer system rendering at runtime. The app paints no imitation of Liquid Glass on an older release, and it has no code that depends on the OS release for materials.
- Cards have no decorative drop shadow. Hierarchy comes from grouped forms, separators and the toolbar.
- The design kit imitates the system materials only so that a browser render shows the hierarchy. That imitation is not a model for the Swift.
- If a new system material for content appears, and it reads well on every supported release, reconsider this decision.

## Alternatives considered

- A translucent background for the whole window: content is harder to read, and the effect differs from release to release.
- A custom glass effect: it imitates the system on releases that do not have one and competes with the system on releases that do.
