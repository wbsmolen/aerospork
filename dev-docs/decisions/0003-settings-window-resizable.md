# 0003. The Settings window is resizable down to 780×520

- Status: accepted
- Date: 2026-08-02
- Enforced by: review only
- Code: `Sources/AppBundle/ui/ConfigurationWindow.swift` (`.frame(minWidth:idealWidth:minHeight:idealHeight:)`, `ResizableWindowEnforcer`)

## Context

At 780 points wide, the Window Rules split view has room for a table and a form side by side.
At 520 points high, a grouped form shows more than two sections before it scrolls.
A SwiftUI `Settings` scene makes a window without `.resizable` in its style mask.
`.windowResizability(.contentMinSize)` on the scene does not change the style mask, so without more work the window stays at its ideal size.
In a window of a fixed size, a pane whose content overflows cannot be recovered.

## Decision

AeroSpork inserts `.resizable` into the style mask of the Settings window and sets its minimum content size to 780×520.

## Consequences

- An invisible `NSViewRepresentable` reaches the `NSWindow` and sets the mask. The scene sets its own mask again after the view arrives in the window, so the view watches `NSWindow.didUpdateNotification` and inserts the bit again only when it is missing.
- At the minimum size, the content scrolls and the toolbar and action bars stay in view. The compact size is a constraint test, not a smaller copy of the ideal layout. The [compact renders](assets/settings-light-compact.png) in [0001](0001-settings-pane-toolbar.md) show it.
- The window does not save its frame. It opens at 880×620 each time.
- The resize behavior is not tested on macOS 13.0 to 13.2.
- If a later SwiftUI makes a `Settings` scene resizable on its own, remove the enforcer.

## Alternatives considered

- `.windowResizability(.contentMinSize)` alone: an earlier version of the design record said that this made the window resizable. The style mask showed that it did not, and the accessibility size of the window was not settable.
- A window of a fixed size: content that overflows has nowhere to go.
