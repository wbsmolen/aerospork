# Monitors tab redesign proposal

Author: UI Designer (Monitors tab)

## 1. Direction and why

The current tab already has the right skeleton — a read-only "what's actually connected" panel
above an editable assignments table, tied together by one `ListActionBar` — and the prior pass
already fixed its real bugs (row selection, unified empty states, `PanelHeader`, the disambiguating
"— matches by name" label). I'm not touching that skeleton. The redesign is about closing three
gaps I found by reading the config surface behind the tab rather than just its current UI, all of
which serve "maximum customizability" directly:

1. **A fully safe, documented monitor-pattern (`sequenceNumber`, e.g. `1 = 1` — "1-based, left to
   right") has no entry point in the structured picker at all.** You can only reach it today by
   opening Raw TOML. It costs nothing to add — it round-trips perfectly, same as `main`/`secondary` —
   and it's genuinely useful for "pin this workspace to whichever monitor is physically leftmost,"
   a different intent than "pin it to this named monitor."
2. **The structured editor silently collapses two real config shapes it cannot fully represent —
   fallback lists and rich hardware fingerprints — and today nothing in the row tells you that's
   happening.** I traced this in `ConfigurationViewModel.reloadFromConfig` and
   `ConfigurationWriter.unsupportedShapeReason` (detail in §6): the picker shows you `descriptions
   .first` with no indication more exist, and a `.fingerprint` keyed on anything but a UUID renders
   as a plain name — indistinguishable from an ordinary `pattern` match. The first time a user finds
   out is when they touch something unrelated elsewhere in the window and every structured save in
   the whole app is refused. That's a bad surprise to leave undocumented in the row itself.
3. **The read-only "Connected monitors" panel and the picker below it don't correlate.** The picker
   offers `Main`/`Non-main` tokens; the monitor list above never says which physical monitor is
   main. Fixing (1) means the picker will also offer position numbers; the monitor list should show
   those too, so a user can look up at the panel and read off exactly what to pick below, instead of
   guessing or checking System Settings separately.

None of these need a new component. All three are additive content inside the existing table cell
and the existing monitor row — no new columns, no new panels, no change to the table's selection
mechanism.

## 2. Specific changes

### 2a. Monitor picker gains a "position" option per connected monitor

`viewModel.liveMonitors` is already `sortedMonitors` (sorted by `rect.minX`, then `minY` —
confirmed in `Sources/AppBundle/model/Monitor.swift:139-141`) mapped 1:1 into `MonitorRow`, and
`MonitorDescriptionEx.resolveMonitor` already resolves `.sequenceNumber(n)` as
`sortedMonitors[n-1]` (`Sources/AppBundle/model/MonitorDescriptionEx.swift:6`). So `liveMonitors`
index `i` **is** sequence number `i+1` today, with zero new plumbing — the tab just never offers it
as a picker option, even though `docs/guide.adoc:719` documents it as the first, simplest pattern.

In `WorkspacesMonitorsTab.swift`, insert a new block into the `Picker`, between the existing
`Main`/`Non-main` pair and the per-monitor name/UUID block:

```swift
Text("Main").tag("main")
Text("Non-main").tag("secondary")
Divider()
ForEach(Array(viewModel.liveMonitors.enumerated()), id: \.element.id) { index, _ in
    Text("Position \(index + 1) — left to right").tag(String(index + 1))
}
Divider()
ForEach(viewModel.liveMonitors) { m in
    Text(m.name).tag(m.name)
    if let uuid = m.uuid { Text("\(m.name) — this exact monitor").tag(uuid) }
}
```

`knownTokens` (used to decide whether the current raw value needs the trailing "unrecognized value"
fallback entry) gains `String(index + 1)` for each monitor alongside the existing name/UUID
insertions, so a config that already says `2` doesn't get a spurious duplicate "current value" entry.

Tag value is the bare `String(n)` — the exact string `parseMonitorDescription` already accepts
(`Int(raw)`, 1-based) and `monitorToken(.sequenceNumber(n))` already emits, so this is a pure
addition to the menu, not a new code path in the parser or writer.

Label wording follows the file's own existing disambiguation convention (`"\(m.name) — this exact
monitor"`, `"\(m.name) — matches by name"` per the last pass) — `"Position 1 — left to right"` names
the mechanism inline rather than needing a section header the flat `Picker` can't render.

Grouped as its own block between two `Divider()`s, separate from the per-monitor name/UUID block:
position numbers answer "which physical slot," names/UUIDs answer "which specific monitor" — two
different intents, worth visually separating rather than interleaving three tags per monitor.

**Web mockup (`MonitorsTab.jsx`)** — extend the existing `monitorOptions` array construction:

```js
const monitorOptions = [
  { value: 'main', label: 'Main' },
  { value: 'secondary', label: 'Non-main' },
  { separator: true },
  ...monitors.map((m, i) => ({ value: String(i + 1), label: `Position ${i + 1} — left to right` })),
  { separator: true },
  ...monitors.flatMap((m) => [
    { value: m.name, label: m.uuid ? m.name + ' — matches by name' : m.name },
    ...(m.uuid ? [{ value: m.uuid, label: m.name + ' — exact display' }] : []),
  ]),
];
```

No changes to `Select` itself — this is new `options` content, not a new prop or variant.

**Pre-existing bug found, unrelated to this proposal, worth a one-line fix alongside it:** the
current mockup's `main` option is labeled `'Primary'` (`MonitorsTab.jsx:6`); the real Swift says
`Text("Main")`. That's drift between mock and source that predates this pass — correct the mock's
label to `'Main'` while touching this array.

### 2b. Connected-monitors panel: show position number and "main" status

Each monitor row gains a small leading position digit (mirrors the position numbers now offered in
2a) and, when applicable, a `main` badge next to the name — so the read-only panel and the editable
picker use the same vocabulary and a user never has to leave the tab (or check System Settings) to
know which physical monitor "Main" or "Position 2" refers to.

`ConfigurationViewModel.MonitorRow` gains one field:

```swift
struct MonitorRow: Identifiable {
    let id = UUID()
    var name: String
    var resolution: String
    var uuid: String?
    var isMain: Bool  // new
}
```

Set in `loadMonitors()` by comparing each monitor's origin to `mainMonitor`'s, the same comparison
`MonitorDescriptionEx.swift:11` already makes for the `secondary` pattern:

```swift
private func loadMonitors() -> [MonitorRow] {
    sortedMonitors.map { monitor in
        let fingerprint = (monitor as? LazyMonitor)?.fingerprint
        let width = fingerprint?.widthPixels ?? Int(monitor.width)
        let height = fingerprint?.heightPixels ?? Int(monitor.height)
        return MonitorRow(
            name: monitor.name, resolution: "\(width)×\(height)", uuid: fingerprint?.displayUUID,
            isMain: monitor.rect.topLeftCorner == mainMonitor.rect.topLeftCorner,
        )
    }
}
```

In the monitor row view, change the `ForEach` to carry an index and add the digit + badge:

```swift
ForEach(Array(viewModel.liveMonitors.enumerated()), id: \.element.id) { index, monitor in
    HStack(spacing: 10) {
        Text(String(index + 1))
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 14, alignment: .trailing)
        Image(systemName: "display")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(width: 26)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(monitor.name).fontWeight(.medium)
                if monitor.isMain {
                    Badge("main", tone: .muted, help: "AeroSpork's main display — the monitor the “main” pattern matches.")
                }
            }
            Text(monitor.resolution)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        Spacer(minLength: 12)
        // UUID + CopyButton unchanged
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 9)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.045)))
}
```

`tone: .muted` matches the existing precedent in `WindowRulesTab.swift:76`
(`Badge("startup", tone: .muted, ...)`) — a badge that *qualifies* a row, as opposed to the
default `.standard` tone used where a badge *explains why a row behaves specially*
(`KeyBindingsTab`'s `Badge("generated", ...)`, no `tone:` argument). "main" is a qualifier, not an
explanation, so it takes the muted tone; §2c's "complex" badge below is the other case and takes
the default tone to match "generated."

**Web mockup**: add a `{i+1}` span (same tertiary/mono styling as the caption UUID text, 14px
width) before the existing `Icon sf="display"` span, and conditionally render a `Badge` (already a
cataloged component, `components/feedback/Badge.jsx`) next to the name span when `m.isMain`. Sample
data (`monitors` prop) gains an `isMain` boolean per entry.

### 2c. Assignments table: "complex" badge for rows the editor can't fully round-trip

This is the direct answer to the brief's clarity caveat (§6 has the full trace). Add a `Badge` next
to the `Picker` inside the existing Monitor column's cell — no new column, no table restructuring:

```swift
TableColumn("Monitor") { row in
    HStack(spacing: 6) {
        Picker("Monitor for this workspace", selection: binding(row.id, \.monitor)) { /* unchanged */ }
            .labelsHidden()
        if isComplex(row.id) {
            Badge("complex", help: "Written with more detail than this editor can show — a fallback list of monitors, or a fingerprint keyed on more than its UUID. Any structured save in this window is refused until this changes; edit it in Raw TOML.")
        }
    }
}
```

`isComplex` needs one new piece of state: whether the *original* `[MonitorDescription]` for that
workspace (before it got collapsed to a single `WorkspaceAssignmentRow.monitor` token) was itself
simple. Compute it once in `reloadFromConfig()`, where `config.workspaceToMonitorForceAssignment` is
already being walked to build `assignments` — a parallel `Set<WorkspaceAssignmentRow.ID>` (or a
field directly on the row) marking rows where:

- `descriptions.count > 1` (a fallback list — the case `ConfigurationWriter.swift:371-378` refuses
  to save), **or**
- the single description is `.fingerprint` and any field other than `displayUUID` is set
  (`vendorID`, `modelID`, `serialNumber`, `displayNamePattern`, `widthPixels`, `heightPixels` —
  the same field set `ConfigurationWriter.swift:365` checks for, minus `uuid` which is the one
  fingerprint shape the writer *does* accept).

This mirrors the writer's own refuse-condition rather than inventing a second, possibly-diverging
definition of "complex" — same two shapes, same reasoning, just surfaced before the save attempt
instead of after.

**Web mockup**: give each row in the `assignments` sample data an optional `complex: boolean`, and
in the `monitor` column's `render`, wrap the existing `<Select>` and a conditional `<Badge>` in a
flex row (`display: flex, gap: 6, alignItems: center`), `Select` at `flex: 1`. No `DataTable` change
needed — this is cell content, same as the existing `handle` column's dot.

### 2d. `ListActionBar` hint gains one clause (ties into `preservedWorkspaceNames`, see §5)

Extend the existing hint string (no new component, no layout change):

> "Hardware fingerprints already in your config are preserved — they just show up here under the
> monitor's name. A DisplayLink monitor reports no vendor or serial, so its UUID is the only thing
> that pins a workspace to that exact monitor. A workspace name listed here also stays available —
> in the menu bar, in app switching — even with no windows on it; a name bound to a key (Keys tab)
> does the same."

## 3. Shared components used or touched (for the cross-tab reconciliation pass)

- **`Badge`** — reused twice, both as-is, no signature change: `main` (`.muted` tone, on the
  connected-monitors row) and `complex` (`.standard`/default tone, in the assignments table's
  Monitor cell). Both match existing precedent exactly (`WindowRulesTab`'s `"startup"` for `.muted`,
  `KeyBindingsTab`'s `"generated"` for default). Flagging both explicitly since Keys tab also uses
  `Badge("generated", ...)` in the same window — same component, same visual language, not a
  collision, but worth the reconciliation pass double-checking tone choices land the same way I
  reasoned about them here.
- **`Select`** (mock) / **`Picker`** (Swift) — no signature or component change, only more `options`/
  `Text` entries passed in.
- **`PanelHeader`, `ContentUnavailable`/`ContentUnavailableViewCompat`, `DataTable`/`Table`,
  `ListActionBar`, `CopyButton`** — unchanged, reused exactly as the prior pass left them.
- No new components proposed.

**Considered and rejected:** turning the Monitor picker into a free-text-with-suggestions field so a
user could type a brand-new regex pattern without leaving structured UI. Rejected — no component in
the catalog is an editable combo box (`Select` is a plain `<select>`/`Picker`), so this would mean
designing new interaction chrome from scratch for one field, which cuts against "lean on the shared
toolkit" and isn't precedented anywhere else in the window. Raw TOML remains the path for a brand
new regex or fingerprint; the picker's job stays "choose among the safe, known-shape patterns,"
which is what §2a's addition extends.

## 4. Fits at 780×520

Nothing here changes vertical structure: same two panels (monitors panel `minHeight ~120` /
`maxHeight 200`, assignments panel flexible), same `Divider()`, same pinned `ListActionBar` — all
already confirmed against the floor by the prior pass. My changes are all *inside* existing rows/
cells:

- Monitor row: +14px leading digit slot, +1 small `Badge` inline with the name — both trivial next
  to the row's existing budget (26px icon + flexible name/resolution block + UUID text + copy
  button already fit comfortably at 780px; the leading digit and inline badge add well under 70px
  total, and the trailing UUID/copy block is unchanged).
- Assignments table: no new column. The Monitor column already flexes to fill remaining width after
  the fixed 20px dot column and the 110–140px Workspace column; at a 780px window that column has
  several hundred px free, easily enough for the existing `Picker` plus one small `Badge`.
- Picker menu: new *rows inside a dropdown menu*, not new on-screen width — menus aren't bound by
  the window's minimum width the way inline content is.
- `ListActionBar` hint: one added clause to existing wrapped, multi-line text — no new bar, no fixed
  height added (the hint area already wraps to however many lines it needs).

No column widths, row heights, or panel heights change. Confirmed no width or height is added to the
tab as a whole.

## 5. Findings and proposal for `preservedWorkspaceNames`

Read `Config.swift:113`, `parseConfig.swift:263-275`, `Workspace.swift:11-53,94-104`, and
`migrateConfigV2.swift:209` (equality check only, not a UI concern).

**It is not a settable config key at all — it's fully derived, at parse time, from two things the
user already edits elsewhere:**

```swift
// parseConfig.swift:265-274
if isUserConfig {
    config.preservedWorkspaceNames = config.modes.values.lazy
        .flatMap { mode in Array(mode.bindings.values) }
        .flatMap { binding in
            binding.commands.filterIsInstance(of: WorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw } +
                binding.commands.filterIsInstance(of: MoveNodeToWorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw }
        }
        + (config.workspaceToMonitorForceAssignment).keys
} else {
    config.preservedWorkspaceNames = Array(config.workspaceToMonitorForceAssignment.keys)
}
```

i.e. it's the union of (a) every workspace name targeted by a `workspace`/`move-node-to-workspace`
command in any keybinding, and (b) every key in `workspace-to-monitor-force-assignment` — which is
exactly the assignments table already on screen in this tab. `Workspace.swift` then uses that set
purely as a read: `getStubWorkspace` prefers a preserved name when inventing a new empty workspace
for a monitor (so idle monitors show a name the user can actually switch to), and
`garbageCollectUnusedWorkspaces`'s doc comment confirms the set exists only to stop a stub workspace
from hijacking a name the user has bound, not to keep anything alive by itself.

**Confirmed unreachable from any tab.** Grepped `Sources/AppBundle/ui/` — zero hits outside my own
tab's data (which only supplies half of it, via the assignments table). Read `GeneralSettingsTab
.swift` and `CallbacksTab.swift` (Events) in full: neither mentions it, confirming it isn't
misrouted to either.

**Proposal: don't build an editor for it — there's nothing independent to edit.** Building a third
"preserved workspace names" control would create a third source of truth for a value that's a pure
function of two others, with the very real risk of it drifting out of sync with what the keybindings
and assignments actually produce (exactly the kind of thing this system's own "say what is not
written in the file" principle exists to avoid — this value in particular is *never* written to the
file). The correct fix is visibility, not editability, and it splits across two tabs since it's
computed from both:

- **In this tab** (proposed above, §2d): one added clause on the existing `ListActionBar` hint,
  stating the direct consequence of a name appearing in the assignments table — it's already 100%
  visible here (every row's Workspace column *is* a preserved name), so this is copy-only.
- **Recommended for Keys tab, not built by me** (out of my tab's scope, flagging for whichever pass
  owns `KeyBindingsTab.swift`): the other half — a name used in a `workspace`/
  `move-node-to-workspace` binding — is invisible today with no view-model access from this tab.
  `KeyBindingsTab.swift`'s existing summary footer (~line 305-311, the "N generated by mod / N
  written in your config" text) is the natural place to add a matching one-line consequence,
  using the same "stays available even with no windows" vocabulary as §2d's hint so the two tabs
  read as one explanation split across two places, not two different explanations.

## 6. Fingerprint / fallback-list editing — explicit confirmation

**I did not propose editing fingerprint objects or fallback lists in the structured table.** Every
picker option in §2a (`main`, `secondary`, position number, name, UUID) is a single simple token,
exactly the same shape the picker already supports today — I only added *one new safe token type*
(`sequenceNumber`) that was missing, I did not touch how complex values are represented or edited.

What I traced in the source to ground §2c, precisely:

- `ConfigurationViewModel.reloadFromConfig` (line 351-355): `assignments = config
  .workspaceToMonitorForceAssignment... .compactMap { workspace, descriptions in descriptions.first
  .map { ... } }` — only the first `MonitorDescription` in a workspace's list is ever loaded into
  the row model. Extra fallback entries are dropped from the in-memory model at load time, before
  the user has touched anything.
- `monitorToken` (line 425-433): `.fingerprint(let data): return data.displayUUID ??
  data.displayNamePattern ?? "fingerprint"` — a fingerprint keyed on `display_name` alone renders
  identically to an ordinary `pattern` name match. There is currently no visual difference between
  "this is a plain name regex" and "this is a hardware fingerprint that happens to key on a name,"
  even though only the former safely round-trips.
- `ConfigurationWriter.unsupportedShapeReason` (lines 346-379) already refuses — not
  degrades — a structured save touching *any* `workspace-to-monitor-force-assignment` entry that is
  a list or a fingerprint keyed on anything but `uuid`, for the whole file, not just the tab or row
  that was edited. The comment there documents this shipped once as silent data loss (`ACME Display
  32 (1)` → bare `name`) before the refuse-guard was added.

So today: a user can open this tab, see an ordinary-looking name in a Monitor cell, edit an
unrelated row's workspace name, hit save (600ms autosave, no explicit Save button), and get a
window-wide error banner blocking every structured save in the app until they either revert or go
fix a row they may not have even touched, in Raw TOML — with zero warning beforehand that the row
they *can* see was ever at risk. §2c's `complex` badge is a proactive version of exactly the message
the writer already produces on refusal (I reused its own reasoning for what counts as "complex"),
surfaced on the specific affected row before the surprise, not a new editing capability. Raw TOML
remains the only way to edit or add a fallback list or a rich fingerprint, unchanged from today.

## 7. Table/selection structure

**I did not redesign the assignments table's structure or its row-selection mechanism.** The
already-shipped fix (inert leading dot column, `Table(...).tableStyle(.inset)`,
`.onDeleteCommand`) stays exactly as-is — it works, and re-litigating it is explicitly out of scope
per the brief. §2c's `complex` badge lives *inside* the existing Monitor column's cell, alongside
the existing `Picker`, not as a new column; it doesn't add a click target that could compete with
the Table's row-selection handler (a `Badge` has no `onTapGesture`/button action in this design —
it's `.help()`/tooltip only, same as the existing UUID `Text` in the monitors panel above it), so it
introduces no new instance of the "control swallows the click" failure mode the dot column was added
to fix.
