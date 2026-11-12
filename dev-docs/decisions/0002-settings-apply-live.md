# 0002. Structured panes apply live, Raw TOML applies on request

- Status: accepted
- Date: 2026-08-02
- Enforced by: `SettingsApplyTest` (the flush on close, Raw TOML apply and refusal), `testWriterNoOpSaveIsByteIdentical`, `ConfigSafetyWriterFuzzTest`
- Code: `ConfigurationViewModel.binding(_:)` and `scheduleAutoSave()`, `ConfigurationTabs/RawTomlTab.swift` (Apply)

## Context

A macOS settings window applies each change when the user makes it. It has no Save button.
Each save in AeroSpork reloads the whole config and starts a refresh, so a save on every keystroke makes the window manager do redundant work.
Text typed into a TOML editor is not valid TOML for most of the time that the user types it.
A live save is safe only because `ConfigurationWriter` leaves each section that the user did not edit byte for byte as it was (the writer invariant in `CLAUDE.md`).

## Decision

A structured pane writes each change 600 ms after the last edit, and the Raw TOML pane writes only when the user chooses Apply.

## Consequences

- The Settings window has no global Save button. A new edit inside the 600 ms restarts the wait.
- When the window closes inside the 600 ms, AeroSpork writes the pending edit at once. Before, AeroSpork dropped the edit. If `ConfigurationWriter` refuses the write, AeroSpork logs the refusal, because no window is left to show it.
- Raw TOML validates the text 180 ms after the last keystroke and shows the exact line and column of a parser error. Apply (⌘S) stays disabled until the text is valid, and Apply makes a backup of the current file first.
- A pane that cannot express a spelling in the config marks the value as generated, complex, custom or per-monitor and keeps it. The pane never flattens the value. A live save depends on this rule.
- A change to the writer invariant makes this decision unsafe. Reconsider both together.

## Alternatives considered

- A Save button for every pane: it is not the macOS convention, and the user can close the window with changes that were never written.
- Live apply for Raw TOML: half-typed text would fail to parse on most keystrokes, and a valid intermediate state could reach the window manager.
