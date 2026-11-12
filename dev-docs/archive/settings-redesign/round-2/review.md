# Settings GUI redesign v2 — cross-proposal review

Mechanical referee pass over all seven tab proposals, cross-checked against each other and against
`Sources/AppBundle/` directly. No design opinions below beyond what's needed to adjudicate a
conflict or a factual claim. All line numbers below were re-read from the working tree at review
time, not copied from the proposals.

## 1. Verified claims

### 1a. Window Rules — `duringAeroSporkStartup: Bool?` already round-trips all three states

**Confirmed.** `ConfigurationViewModel.swift:566`: `duringStartup: cond?["during-aerospork-startup"]?.bool`
reads `nil` (key absent), `true`, and `false` correctly. `ConfigurationWriter.swift:472`:
`if let during = rule.duringStartup { block.append("if.during-aerospork-startup = \(bool(during))") }`
— `nil` correctly omits the key, `true`/`false` write it. `ConfigurationWriter.swift:421`
(`isShorthandExpressible`) additionally requires `duringStartup == nil` before a rule is eligible
for the `[on-window]` shorthand form, which is consistent, pre-existing behavior the proposal
doesn't need to touch. Window Rules' claim that its new `SegmentedPicker` is "strictly additive,
no writer or view-model changes needed" is correct.

### 1b. Monitors — `preservedWorkspaceNames` is fully derived, not a settable TOML key

**Confirmed.** `Config.swift:113` declares it a plain `var`, but the only two writers are
`parseConfig.swift:265-274` (computed from `config.modes` bindings' `workspace`/
`move-node-to-workspace` targets, unioned with `config.workspaceToMonitorForceAssignment.keys`).
`grep -rn "preservedWorkspace" Sources/AppBundle/ui/` returns zero hits — confirming the proposal's
own claim that it's unreachable from any tab today. `ConfigurationWriter.swift` never writes a
`preserved-workspace-names` key. The proposal's decision not to build a third editor for a value
that's a pure function of two others already on screen is correctly grounded.

### 1c. Raw TOML — `TOMLParseError` carries `line`/`column`, but `parseConfig.swift` discards it

**Confirmed.** `.build/checkouts/TOMLKit/Sources/TOMLKit/TOMLParseError.swift:50-65`:
`TOMLParseError.source: TOMLSourceRegion`, and `TOMLSourceRegion.begin`/`.end` are each a
`TOMLSourcePosition` with `line: Int`/`column: Int`. `parseConfig.swift:238-239`:
`catch let e as TOMLParseError { return .failure([.syntax(e.debugDescription)]) }` — flattens the
structured position into a string via `debugDescription` (`"\(description) (\(source))"`),
discarding programmatic access to `line`/`column`. The proposal's "Easy–Moderate" feasibility
rating for wiring this through is accurate: the position already exists, it's a plumbing problem
(`TomlParseError.syntax` needs a position field, `ConfigurationWriter.validate`'s `String?` return
needs to become a struct), not a new capability from TOMLKit.

### 1d. Gaps — `ConfigurationWriter.replaceGaps` rewrites the whole `[gaps]` section on any edit

**Confirmed.** `ConfigurationWriter.swift:566-578`: `replaceGaps` calls
`removeSections(&lines) { $0 == "gaps" || $0.hasPrefix("gaps.") }` then unconditionally re-emits all
six fields (`inner.horizontal`, `inner.vertical`, `outer.top/bottom/left/right`). The gate,
`ConfigurationViewModel.swift:138` (`var gapsEdited: Bool { currentGaps != loaded.gaps }`), is a
single bool over the whole struct — there is no per-field edit tracking to hang a per-field
provenance badge off. The proposal's decision to use one section-wide `StatusLabel` signal instead
of six per-field `Badge`s is correctly grounded in the real writer behavior, not an assumption.

All four load-bearing claims check out exactly as stated, including specific line numbers in three
of the four cases.

### Additional spot-checks (not required, done because the citations were unusually dense and worth machine-verifying)

- Monitors §5/§6's trace of `sortedMonitors` (`Monitor.swift:139-141`,
  `monitors.sortedBy([\.rect.minX, \.rect.minY])`), `MonitorDescriptionEx.resolveMonitor`'s
  `.sequenceNumber` case (`sortedMonitors.getOrNil(atIndex: number - 1)`), `.secondary`'s
  `topLeftCorner` comparison, `ConfigurationViewModel.reloadFromConfig`'s `descriptions.first`
  collapse (`ConfigurationViewModel.swift:351-355`), `monitorToken`'s fingerprint-to-string collapse
  (`:425-433`), and `ConfigurationWriter.unsupportedShapeReason`'s fingerprint-field check and
  fallback-list refusal (`ConfigurationWriter.swift:362-379`, matching the proposal's cited
  `:365`/`:371-378` almost to the line) — **all confirmed exactly**, including the specific field
  list (`display_name`, `width`, `height`, `vendor`, `model`, `serial`) the writer actually checks.
  This proposal's factual grounding is the most heavily cited of the seven and the most accurate.
- Events' `initAppBundle.swift:43` (`config.afterStartupCommand.runCmdSeq(...)`), `guide.adoc`'s
  `on-focused-monitor-changed`/`on-focus-changed` examples (confirmed at the cited lines), the
  `AEROSPORK_WINDOW_ID`/`AEROSPORK_WORKSPACE`/`list-exec-env-vars` documentation, and the real PATH
  default (`guide.adoc:235`: `/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}` vs. the current wrong
  Swift placeholder `/opt/homebrew/bin:/usr/bin` at `CallbacksTab.swift:44`) — **all confirmed**.
- Window Rules' claim that its proposed matcher order (App ID, App name, Window title, Workspace,
  Startup timing) matches `guide.adoc`'s own example — **confirmed**, `guide.adoc:544-548` lists
  `app-id`, `app-name-regex-substring`, `window-title-regex-substring`, `workspace`,
  `during-aerospork-startup` in exactly that order. Its "if not specified then the condition isn't
  checked" and "Only move-node-to-workspace and layout are supported" citations are also verbatim
  matches (`guide.adoc:579`, `:561`).

No factual claim checked in this pass turned out to be wrong. The one recurring class of error is
not "wrong claims about the config/writer," it's "wrong claims about what's already in Swift" —
covered in §6.

## 2. Shared-component conflicts

### `StatusLabel.Kind.neutral` — confirmed pre-existing, used compatibly by Gaps and Keys

`SettingsChrome.swift:266-267`: `enum Kind { case ok, warning, error, neutral }` — `neutral` is not
new. Both Swift's `StatusLabel` and the JSX `StatusLabel.jsx` define it identically (icon
`equal.circle`, `--label-secondary`/`.secondary` tint), and both already have a real precedent:
`RawTomlTab.swift:116`, `StatusLabel("Matches the file on disk", kind: .neutral)`. Gaps (§2a, a
conditional per-monitor-override notice) and Keys (Change C, cross-mode composer awareness) each
cite this precedent independently and use the kind for the same "informational, not a warning"
purpose it already has. **No conflict — this is the pattern working as intended**, two designers
converging on the same existing vocabulary rather than inventing two different "neutral inline
status" idioms.

One accurate cross-check inside this: Gaps' proposal explicitly flags that the JSX `StatusLabel`
takes an optional `sf` icon-override prop that Swift's does not, and says not to use it. Confirmed —
`StatusLabel.jsx:5-11` has `sf` as an override parameter; `SettingsChrome.swift`'s Swift
`StatusLabel` hard-codes the icon to `kind.icon` with no override. Gaps' proposal is right to flag
this as mock-only flexibility that would misrepresent what Swift can render.

### `Badge` — mostly compatible, one real contract gap in Keys

`Badge.prompt.md:1`: "Lowercase, one word, never colored as a status." `Badge.d.ts:1` (JSX):
"Lowercase capsule badge for row provenance." Both source-of-truth docs describe a fixed,
app-authored vocabulary (`generated`, `startup`).

- **Monitors** (`main`, `complex`) and **Window Rules** (`runtime`, alongside the existing
  `startup`) both add new badge text that is lowercase, one word, and app-authored — compliant, and
  both correctly cite the same existing precedent (`WindowRulesTab.swift:76`,
  `Badge("startup", tone: .muted, ...)` for `.muted`; `KeyBindingsTab.swift:191`,
  `Badge("generated", ...)` for default/`.standard`) for their tone choices. Monitors even flags the
  overlap explicitly and asks the reconciliation pass to double-check tone reasoning — it lines up:
  `main` is a qualifier (`.muted`, like `startup`), `complex` is default tone (like `generated`,
  which explains why a row behaves specially). **Converges compatibly, not a collision.**
- **Keys' cross-mode section (Change B1)** puts a **mode name** inside a `Badge`:
  `<Badge tone="muted">service</Badge>`, describing it as "arbitrary text children, no extension
  needed." Mode names are not fixed app vocabulary — `Config.swift:110`,
  `var modes: [String: Mode]`, and there is no name-shape validation anywhere in
  `parseConfig.swift` (grepped for it — none). A user is free to name a mode `Resize Mode` or
  `Launcher`, and nothing stops it from landing in this badge exactly as typed, breaking the
  documented "lowercase, one word" contract the moment a real config has a differently-cased or
  multi-word mode name. This is a genuine, if narrow, contract violation: every other Badge use
  across all seven proposals holds fixed, app-chosen text; this is the first one that puts
  arbitrary user data in a component whose own doc says "lowercase, one word." Worth a caveat before
  Swift implementation — either constrain the display (e.g., render the raw mode name as `Text` in
  the row instead of a `Badge`, consistent with how user-supplied names get curly-quoted as prose
  elsewhere in this same proposal, or accept the badge will occasionally look inconsistent for an
  edge-case mode name).

### `SegmentedPicker` — Window Rules' new use fits the documented ceiling, but the proposal doesn't argue the point the brief asked it to

`SegmentedPicker.prompt.md:1`: "Use when the options are few, short and worth showing at once; use
`Select` instead past three options or with long labels." `SegmentedPicker.jsx:3-4` (comment):
"used for short, mutually exclusive choices with 2-3 options (layout, split direction, **the Keys
mode switcher**)." Window Rules' citation of "the component's own doc comment names 'the Keys mode
switcher' as precedent" is **confirmed verbatim** against that comment.

Three fixed options ("Any"/"Startup"/"Runtime") for a `Bool?` sits inside the documented "2-3
options" ceiling on its face, so the outcome is fine. But the brief specifically asked whether
Window Rules reasons about the fixed-vs-growable distinction the way General did for its rejected
Keyboard-layout conversion — it does not. General's rejection (§2.4) explicitly invokes
`Select.prompt.md`'s "a list of options that can grow at runtime" language and argues Bool?'s three
states can't grow. Window Rules' justification (§3) is "same pattern already used for 2-3 choices" —
a cardinality argument, not a growability one. The distinction happens to not matter here (a `Bool?`
truly cannot grow a fourth state), but the proposal asserts fitness rather than arguing it the way
the brief modeled. Flag for the reconciliation pass to add one sentence of that reasoning, not a
defect in the design itself.

### `IconButton` — Keys is a new call site, but it's building on a component that doesn't exist in Swift yet (see §6)

Keys' Change D reuses `IconButton` (`systemImage: "doc.on.doc"`, no `role`) as a second call site
alongside the tab's existing Remove affordance. `IconButton.d.ts` confirms `role?: 'destructive'` is
the only non-default role, matching Keys' "Role: not destructive (`role: nil`)" framing exactly — no
prop mismatch. The real issue isn't a conflict with another proposal; it's that `IconButton` itself
is JSX-only today (§6).

### `CodeEditor` — confirmed untouched by any other proposal

Grepped all seven proposals for `CodeEditor`; only Raw TOML references it (new props
`errorLine?`, `warningLines?`, `onCursorMove?`, `sectionHeaders?`, additive to the existing
`NSViewRepresentable`/JSX wrapper). No collision. One factual problem inside Raw TOML's own claim
about this component, though — see §6.

## 3. Scope-creep flags

None found that invent capability ungrounded in a real `Config.swift` field, and none that touch
window-level chrome (the `TabView` shell) outside a tab's own content pane.

- Every proposal's new control traces to a real field: Monitors' position-number picker to
  `MonitorDescription.sequenceNumber` (already parseable/writable, just missing from the picker's
  option list); Window Rules' segmented picker to `duringAeroSporkStartup: Bool?` (already
  round-tripped, confirmed §1a); Gaps' link toggles to the six existing gap `Int`s (view-state only,
  the `@State` toggles are explicitly non-persisted); Keys' category grouping/cross-mode
  section/duplicate button are all client-side view logic over data the view model already exposes
  (`displayBindings(mode:)`, `existingBinding(mode:key:)`), with **no new `ConfigurationViewModel`
  method** required by Keys' own account.
- Raw TOML is the one tab that isn't grounded in a missing `Config.swift` field — the tab explicitly
  argues (§1) that it can't be, since it's already the universal escape hatch, and reframes "maximum
  customizability" as editing-surface quality instead. That's not scope creep in the sense the brief
  warned about (inventing new *config* capability); it doesn't touch anything outside the tab's own
  path-bar/editor/action-bar region, and adds no third bar strip. It is, however, real net-new
  AppKit engineering (a custom `NSRulerView` gutter, a hand-written incremental tokenizer) — flagged
  as a size/risk note in the proposal's own feasibility table (§4), which is the right place for it.
- Monitors' §5 recommends a Keys-tab footer addition for the other half of
  `preservedWorkspaceNames` visibility, but explicitly does not build it ("out of my tab's scope,
  flagging for whichever pass owns `KeyBindingsTab.swift`") — a cross-tab *recommendation*, not an
  edit. Correctly delegated, not scope creep.
- No proposal touches `ConfigurationWindow.swift`'s `TabView`, tab order, or tab labels.

## 4. Window-floor risk

`ConfigurationWindow.swift:63`: `.frame(minWidth: 780, idealWidth: 880, minHeight: 520,
idealHeight: 620)` — confirmed as the real floor all seven proposals target.

- **Window Rules** — strongest-justified of the three named for spot-check. Its width argument does
  real arithmetic against measured values: `WindowRulesTab.swift:19-20` confirms
  `list.frame(minWidth: 280, idealWidth: 340)` / `detail.frame(minWidth: 330)` exactly as cited, and
  `280+330=610`/`340+330=670`, both under 780 before the `HSplitView` divider — an actual sum, not
  an assertion. Height reasoning ("one more `LabeledContent` row, `Form` already scrolls") is
  qualitative but consistent with how the tab already behaves.
- **Raw TOML** — also does real arithmetic: `Ln 12, Col 4` (~70px) + `Sections…` (~65px) +
  `Open in TextEdit` (~120px) + `Reload` (~55px) + gaps (24px) ≈ 334px against a 752px usable strip
  width, cross-checked directly against `RawTomlTab.swift`'s actual buttons and padding. Solid.
- **Keys** — the thinnest of the three. Its §7 fit argument is almost entirely qualitative
  ("well inside the slack," "small next to that slack") rather than summed against the 780px floor
  the way Window Rules and Raw TOML do, despite Keys adding the most simultaneous new UI of any
  proposal (category headers + cross-mode section + composer line + duplicate button). None of the
  individual additions look implausible on their own (170px key column and the composer's flexible
  `SettingsField` are real, cited anchors), but there's no aggregate number anywhere in §7 the way
  610/670-vs-780 or 334-vs-752 give the other two. Not wrong, just under-justified relative to its
  own stated stress cases — worth asking for the same style of arithmetic before implementation,
  particularly for Change D's per-row `IconButton` addition stacked on top of the existing 170px
  recorder column and a already-compressible `SettingsField`.
- General, Gaps, Monitors, Events all make correctly-scoped "this only adds wrapped text inside an
  already-scrolling `Form`" arguments and don't add fixed-width elements; nothing to flag.

## 5. Voice/copy issues

Checked every new user-facing string proposed across all seven documents against
`readme.md`'s content rules (sentence case; no exclamation marks/emoji/jokes; curly quotes around
user-supplied names; placeholders as real examples; badge text lowercase/one-word).

- **No exclamation marks, emoji, or marketing language found anywhere.** All seven proposals stay in
  the "careful engineer" register.
- **Sentence case holds** for every new label, header, and footer, including compound section titles
  (General's "Menu bar & Dock" — capitalizing "Dock" matches the existing precedent at
  `GeneralSettingsTab.swift:28`, `"Show icon in the Dock"`; Keys' category labels "Move & workspace",
  "Layout & resize" correctly keep the second word lowercase).
- **Curly quotes around user-supplied names are used correctly** everywhere a proposal interpolates
  one: Keys' `"Nothing in "\(selectedMode)" matches "\(query)"."`, `"Duplicate "\(command)""`,
  `"Also bound in "\(mode)" mode."`; Monitors' `"main" pattern matches` in the badge help text.
- **The one gap is Keys' Badge-as-mode-name usage (§2 above)** — the same proposal that correctly
  curly-quotes mode names everywhere they appear as prose (B2's messages, Change C's composer line)
  does not quote or otherwise guard the mode name when it goes into a `Badge` instead, which is both
  a component-contract issue (§2) and, functionally, a missed instance of the same "user-supplied
  name" rule the rest of the proposal applies consistently.
- **Placeholders as real examples**: Events' corrected PATH placeholder
  (`/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}`) and per-section command placeholders
  (`move-mouse monitor-lazy-center`, `move-mouse window-lazy-center`) are both verified-real examples
  from `guide.adoc`, not invented syntax — confirmed in §1.
- **Badge text** — `main`, `complex`, `runtime` are all lowercase, one word, matching
  `Badge.prompt.md`'s rule (the mode-name case above is the exception, not these).

## 6. "Already shipped" impact

The brief told every designer that the prior round's `IconButton` migration, `PanelHeader`, and
casing/padding fixes were "already shipped in both the real Swift and the mockup." This is
confirmed false for everything except the two specific fixes CLAUDE.md itself calls out (the
`WorkspacesMonitorsTab` row-selection fix, and three Keys-tab glyph/overflow/badge fixes). Verified
directly:

| Claimed-shipped item | JSX (mockup) | Real Swift |
|---|---|---|
| `IconButton` component | Exists (`components/controls/IconButton.jsx`) | **Does not exist** — `grep -rn "IconButton" Sources/` returns nothing |
| `PanelHeader` component | Exists (`components/layout/PanelHeader.jsx`), used in `MonitorsTab.jsx`, `RulesTab.jsx` | **Does not exist** — zero hits in `Sources/`; `WindowRulesTab.swift:26-28` and `WorkspacesMonitorsTab.swift:32-35,83-86` still use raw `SectionLabel` + inline `.padding()` |
| `KeyBindingsTab` Remove → `IconButton`, curly-quoted label | Done (`KeysTab.jsx:77`) | **Not done** — `KeyBindingsTab.swift:169-172` is still a plain `Button` with `"Remove \(b.key)"`, no curly quotes |
| `CallbacksTab` Remove → `IconButton`, curly-quoted label | (not directly checked) | **Not done** — `CallbacksTab.swift:102-108`, `removeButton` is a private helper, generic `"Remove"`, no curly quotes |
| `CallbacksTab` add-button loses `.foregroundStyle(.accentColor)` | — | **Not done** — `CallbacksTab.swift:99` still has it |
| Key/Command header row (Keys tab) | Present (`KeysTab.jsx:62-63`, `<span>Key</span>`/`<span>Command</span>`) | **Not present** — `KeyBindingsTab.swift:150-155`, the `List` has no header row above it |
| `WorkspacesMonitorsTab` unified empty state (`ContentUnavailableViewCompat`) | Present (`MonitorsTab.jsx:24`, `<ContentUnavailable .../>`) | **Not done** — `WorkspacesMonitorsTab.swift:39-43` still shows a bare `SettingsHint` for the monitors panel |
| Monitor picker "— matches by name" disambiguation | Present (`MonitorsTab.jsx:11`) | **Not done** — `WorkspacesMonitorsTab.swift:128`, `Text(m.name).tag(m.name)` has no suffix |
| `GapsSettingsTab` preview section `SectionLabel("Preview","eye")` header | Present (`GapsTab.jsx:7`) | **Not done** — `GapsSettingsTab.swift:13-24`, the preview `Section` has no `header:` at all |
| `GapsPreview` fill `0.045`/stroke `0.16` (`--fill-subtle`/`--border-control`) | Present (`GapsPreview.jsx` via CSS vars; `colors.css:41,46` = `0.045`/`0.16`) | **Not done** — `GapsSettingsTab.swift:78,80` still has `Color.primary.opacity(0.05)` / `Color.secondary.opacity(0.35)` |
| `CodeEditor` font size 12→13 (`NSFont.systemFontSize`) | Present (`CodeEditor.jsx:3-4` comment: "13px monospaced... matches every other monospaced element") | **Not done** — `SettingsChrome.swift:376`, `.monospacedSystemFont(ofSize: 12, weight: .regular)` |
| `RawTomlTab` bar-strip padding → vertical 9/9 | — | **Not done** — `RawTomlTab.swift:61` (path bar) is still `8`, `:99` (action bar) is still `10` |

This is exactly the failure mode the task called out: the "already shipped" claim in the shared
brief was wrong for the general population of prior-round fixes, right only for the two specific
items CLAUDE.md names.

**Per-proposal impact:**

- **Caught it themselves, no caveat needed:**
  - **Events** explicitly re-verified: "I confirmed it's shipped in the JSX..., but
    `grep -rn "IconButton" Sources/AppBundle/ui/` returns nothing — the type doesn't exist in Swift
    yet... just noting the Swift file hasn't caught up yet." Its proposal treats the JSX as the
    working baseline and doesn't depend on the Swift side being further along than it is. Clean.
  - **Raw TOML** also independently caught a related discrepancy on its own tab: "I read the strip
    padding as `.padding(.vertical, 8)` on the path bar and `10` on the action bar in the current
    `RawTomlTab.swift`, not the `9`/`9` the task brief describes as already shipped... Not this
    proposal's problem to reconcile." Confirmed accurate (§ table above) and correctly scoped as not
    its job to fix. Its separate, load-bearing claim that the `CodeEditor` font size is "unchanged
    (13px, already corrected in the prior pass — not re-litigating)" **is wrong** — real Swift is
    still 12px (`SettingsChrome.swift:376`) — but since the proposal isn't proposing to change the
    font size either way, this doesn't break anything it's building; it just means whoever
    implements Raw TOML's gutter/highlighting in Swift should not assume 13px is already true and
    should carry the 12→13 fix forward alongside the new gutter work, or the gutter's row height
    (tuned to "1.45 line height" matching the editor) will be calibrated against the wrong base font
    size.
- **Needs a caveat before Swift implementation:**
  - **Keys** opens by saying it "builds forward from the already-fixed state (modifier glyphs,
    mode-picker degrade at 5, capitalized `generated` badge, uniform 170px recorder/composer width,
    **Key/Command header row**)." Four of those five are real and confirmed in Swift
    (`KeyBindingsTab.swift:22` for the degrade-at-5 logic, `:520` for modifier glyphs, `:166/179/245`
    for the 170px width, `:191` for the `generated` badge) — those three plus the width match
    CLAUDE.md's "three Keys-tab glyph/overflow/badge fixes" almost exactly. The header row is the
    one item on that list that is **not** in Swift. More significantly, Keys' Change D (duplicate
    button) and its framing that "no new shared component is required" both depend on `IconButton`
    already existing in Swift, which it doesn't — the Swift-implementation phase for this tab needs
    to build `IconButton` in `SettingsChrome.swift` first (or concurrently), plus the Key/Command
    header row, before Change D can land as designed "additively."
  - **Monitors** frames its whole approach on "the prior pass already fixed its real bugs (row
    selection, unified empty states, `PanelHeader`, the disambiguating '— matches by name' label). I'm
    not touching that skeleton." Row selection is genuinely fixed (confirmed:
    `WorkspacesMonitorsTab.swift:97-148`, the inert dot column + `.tableStyle(.inset)` +
    `.onDeleteCommand` pattern is real). The other three are not (table above). None of Monitors'
    *new* work (position-number picker, `main` badge, `complex` badge) depends on `PanelHeader` or the
    empty-state/disambiguation fixes existing, so the substance is unaffected — but a Swift
    implementer following this proposal literally would be building the position/main/complex
    additions onto a header/empty-state/label baseline that isn't there yet, and should build (or at
    least be aware of) those three first.
  - **Window Rules** cites "the prior pass already fixed its header padding via `PanelHeader`" as
    context (not something it modifies). Confirmed not real in Swift
    (`WindowRulesTab.swift:26-28` is still raw `SectionLabel` + `.padding(.horizontal, 14)`/
    `.padding(.vertical, 10)`, not the `PanelHeader`/16-14-8 numbers `synthesis.md` specified). Since
    Window Rules doesn't touch this header at all, the impact is limited to a documentation
    accuracy note, not a build risk.
  - **Gaps** is the proposal most exposed by this: §2a states plainly "No visual change to
    `GapsPreview` itself or its `Section` header (`SectionLabel("Preview", "eye")` was already fixed
    in the prior pass — fill `0.045`, stroke `0.16` — leave as-is)." **All three parts of that
    sentence are wrong for Swift** — no header exists at all on that `Section`
    (`GapsSettingsTab.swift:13-24` has no `header:` argument), and the fill/stroke are still the old
    `0.05`/`0.35` values (`:78,80`). This is load-bearing for §2a's actual change: the proposal
    describes adding a conditional `footer:` to an existing `Section { ... } header: { SectionLabel(...) }`
    block, but the block it would actually be editing has no header at all today. A Swift
    implementer needs to add the missing header, fix the fill/stroke tokens, *and* add Gaps' new
    conditional footer — three tasks where the proposal accounted for one. This doesn't invalidate
    the footer design itself, but the proposal should not be handed to Swift implementation without
    this caveat attached.
- **Unaffected:** **General** makes no claim about, and no change dependent on, any of the disputed
  "already shipped" items — clean.

## 7. Everything else

- **Window-size floor**: confirmed real (`ConfigurationWindow.swift:63`); no proposal adds width or
  height to an always-visible element outside the risk noted in §4.
- **`Toggle`** — Gaps (first use in that tab) and Events (fixing the JSX to use it instead of a raw
  checkbox; Swift's `CallbacksTab.swift:39` already correctly uses SwiftUI `Toggle`) both cite the
  same `label`/`checked`/`onChange` shape (`Toggle.d.ts`), both flag their own usage explicitly for
  the reconciliation pass, and neither changes its contract. Converges cleanly.
- **`Select`/`Picker`** — General's citation of `Select.prompt.md` ("a list of options that can grow
  at runtime (connected monitors, modes, keyboard layouts)") is a verbatim match against the actual
  doc, correctly grounding its rejection of a `SegmentedPicker` conversion for Keyboard layout.
  Monitors only adds `options`/`Text` entries to the existing `Picker`, no shape change. No conflict
  between the two.
- **`ContentUnavailableViewCompat`** — Keys (Change B2) only changes existing `title`/`message`/
  `actionTitle`/`action` argument values per query state, no prop additions; consistent with every
  other tab's usage.
- **General, Gaps, Events, Window Rules** all correctly identify and reject an over-scoped
  alternative in their own document (General: section restructuring, `SegmentedPicker` for keyboard
  layout, schematic previews; Gaps: draggable preview, per-monitor editing; Events: nested section
  headers, reorder affordance, run-now button, live validation; Window Rules: a structured
  action-builder for "Then run") with reasoning grounded in either a documented component rule or an
  explicit precedent elsewhere in the window, not just "seemed like scope creep." This is a
  consistent strength across the round.
- Every proposal's line-number citations against `Config.swift`, `ConfigurationViewModel.swift`,
  `ConfigurationWriter.swift`, and `docs/guide.adoc` that were spot-checked in §1 matched the working
  tree exactly, including several citations accurate to a single line number — the factual research
  underlying all seven proposals is solid. The one systematic weak point across the round is not
  research into the config/writer layer (uniformly strong) but trust in the shared brief's Swift-vs-
  mockup baseline claim (uniformly weak except where a designer re-verified it themselves).
