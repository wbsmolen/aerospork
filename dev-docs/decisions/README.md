# Decision records

Each file records one design decision that is in the code today, with the reason for it.
Read the record before you change the behavior it describes. If the reason no longer holds, write a new record that supersedes the old one.

| # | Decision | Status |
|---|---|---|
| [0001](0001-settings-pane-toolbar.md) | A native pane toolbar for the Settings window | accepted |
| [0002](0002-settings-apply-live.md) | Structured panes apply live, Raw TOML applies on request | accepted |
| [0003](0003-settings-window-resizable.md) | The Settings window is resizable down to 780×520 | accepted |
| [0004](0004-opaque-content-system-chrome.md) | Opaque content, and system materials only on system chrome | accepted |
| [0005](0005-one-home-for-shared-settings-controls.md) | One home for every shared Settings control | accepted |
| [0009](0009-raw-toml-editor.md) | An AppKit text view for Raw TOML, at 12 pt | accepted |

Numbers 0006 to 0008 are reserved for records that have no citation yet: icon-only controls and hit targets, spellings that a pane cannot express, and badges for app vocabulary only.

The earlier redesign proposals, reviews and syntheses are in [`../archive/`](../archive/). Do not act on them.

## Write a record

1. Copy the template below into a new file named `NNNN-short-name.md`. Use the next free number.
2. Write the decision as one sentence in the simple present, with AeroSpork, the Settings window or a component as the subject.
3. Keep the record under 40 lines.
4. Add a row to the table above.

Each record holds one decision. To change a decision, write a new record, set the status of the old record to `superseded by NNNN`, and leave the rest of the old record as it is.

```markdown
# NNNN. <The decision as a noun phrase>

- Status: accepted | superseded by NNNN
- Date: YYYY-MM-DD
- Enforced by: <test names, or "review only">
- Code: <file or symbol>

## Context
<Two to five sentences: the forces and the facts. Not the history of the discussion.>

## Decision
<One sentence, simple present.>

## Consequences
- <What this makes easier.>
- <What this costs or gives up.>
- <What would make the decision worth a second look.>

## Alternatives considered
- <Option>: <one sentence on why it lost.>
```
