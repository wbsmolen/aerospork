# Raw TOML tab — redesign proposal

## 1. Direction

This tab is not a config-surface-gap problem — it already IS the gap-closer, per `CLAUDE.md`:
"the guarantee that no config key is unreachable from the GUI." Auditing it for missing structured
controls makes no sense; there's nothing to add a control for. So "maximum customizability" here
means something different from the other six tabs: **is the text-editing surface itself as good as
a real code editor gets, within what an `NSTextView` can honestly do?**

Direction: turn the plain `NSTextView` into a minimal, restrained code editor — gutter with line
numbers, TOML-aware highlighting, exact-position error markers where the parser can give us a
position (and an honest best-effort fallback where it can't), a way to jump to a section, and free
find-in-editor via AppKit's own find bar. Everything is additive to the existing three-region layout
(path bar → editor → action bar); nothing about that shape changes.

The one deliberate constraint I'm imposing on myself: **no rainbow syntax highlighting.** The design
system is explicit that "colour carries meaning only: red = config not loaded, orange = warning,
green = valid," and this app has never used color as decoration — no gradient, no brand color on a
button, six system colors total. A VSCode-style palette per token type (strings green, numbers
purple, keys blue...) would be the single most out-of-character thing I could ship on this tab. So
the highlighting scheme below uses exactly one new-to-this-surface color relationship (the existing
accent, already used for "the important active thing" — the armed key recorder, the gaps-preview
accent tile) plus the existing label-opacity hierarchy, and reserves red/orange for what they already
mean in this app: an actual parse error or a deprecation warning, now anchored to a line instead of
just a joined string at the bottom.

What I'm explicitly **not** proposing: a minimap (config files run tens to low hundreds of lines —
there's nothing to overview), an editor preferences pane (font size/theme toggles — nothing in the
brief or the codebase asks for per-user editor tuning, and it'd be new surface for a need nobody's
expressed), or autocomplete/IntelliSense (would need a TOML schema model that doesn't exist and is a
different project). Restraint is the point of this tab as much as the feature list is.

## 2. Specific changes

### 2.1 Layout — path bar gains a nav cluster, editor gains a gutter, nothing else moves

Current shape stays: `pathBar` (top, pinned) → `Divider` → `CodeEditor` (fills) → `actionBar`
(bottom, pinned). I'm not adding a third bar strip — the design system is explicit that stacked bar
strips get merged, not layered.

**Path bar**, trailing cluster, left to right, `HStack(spacing: 8)` as today:
`Ln 1, Col 1` (caret position, new) → `Sections…` (new `Menu`, styled exactly like the action bar's
existing `Restore…`) → `Open in TextEdit` (existing) → `Reload` (existing).

- **`Ln 1, Col 1`**: plain text, `--text-callout` (12px) system font (**not** monospaced — per the
  design system, mono is for "anything the user could type into the config file"; this is a derived
  UI readout, not typed content, same register as the `pt`/`px` unit labels next to `NumberField`),
  `--label-secondary`. Updates on every selection change. 1-indexed, matching how editors and the
  parser's own error messages report lines.
- **`Sections…`**: a `Menu` — same `.menuStyle(.borderlessButton).fixedSize()` treatment as
  `Restore…` already gets in the action bar, just relocated concept, new instance. Items are every
  `[section]` / `[[array-of-table]]` header line in the buffer, **in document order** (not
  alphabetical — matches how someone thinks about "where in the file," and matches `Restore…`'s own
  newest-first-not-alphabetical backup ordering philosophy: order by what's useful to scan, not by
  string sort), label = the header exactly as written (`[mode.main]`, `[[on-window-detected]]`),
  monospaced within the menu row since it's literal file text. Selecting one scrolls the editor and
  places the caret at that line. Disabled when the buffer has no section headers, same precedent as
  `Restore…` being disabled with no backups — no explanatory copy needed, a disabled control with a
  stable tooltip is the established pattern.

No new bar-strip padding decisions needed — I'm adding items to the existing trailing `HStack`, not
touching the strip's own padding. (Note: I read the strip padding as `.padding(.vertical, 8)` on the
path bar and `10` on the action bar in the current `RawTomlTab.swift`, not the `9`/`9` the task
brief describes as already shipped and which the JSX mock already shows. Not this proposal's
problem to reconcile — whatever the mockup builder inherits there is what I'm building on top of.)

**Editor row**: gains a fixed-width **gutter** to the left of the text content, inside the same
scroll region (this is the AppKit-equivalent of putting a `verticalRulerView` on the `NSScrollView`
that already backs `CodeEditor` — the ruler lives in the scroll view, not in the text container, so
it doesn't interact with the existing 10/12pt `textContainerInset`).

- Width: auto-sized to fit the buffer's max line-number digit count, minimum 3 digits (so short
  files aren't oddly narrow), i.e. `34px` typical, growing for a 4+-digit file.
- Numbers: `--text-subheadline` (11px, the same register the design system already uses for "table
  headers" — a line-number column is functionally a row index), `--label-tertiary`, right-aligned,
  system font (not mono — same reasoning as Ln/Col: it's a UI readout about the code, not code).
  Row height matches the editor's own line height (1.45) so numbers line up with their line.
  1-indexed.
- Background: `Color.primary.opacity(0.045)` — reuse the existing `--fill-subtle` token, don't
  invent a new opacity constant. A single 1px `--separator` hairline divides gutter from text, same
  as every other chrome/content boundary in this app.
- Error/warning markers live in this gutter — see 2.3.

### 2.2 TOML syntax highlighting

Three categories, not the naive "everything gets its own hue" scheme, for the reason in §1:

| Token | Treatment |
|---|---|
| `[section]` / `[[array-of-tables]]` header lines | `--accent`, `--weight-medium` |
| `# comment` (from `#` to end of line) | `--label-tertiary`, regular weight |
| key (bare or dotted, before `=`) | `--label` (default), `--weight-medium` |
| everything else — strings, numbers, booleans, dates, array/inline-table punctuation, the `=` itself | `--label-secondary` (default weight) |

Deliberately **not** distinguishing strings from numbers from booleans — TOML's value types don't
need visual disambiguation the way "this is a key I can search for" vs. "this is its value" does,
and a third or fourth hue is exactly the rainbow-decoration slope I ruled out in §1. The one axis
that matters for scanning a config file is: *structure* (section headers, in accent) → *the thing
you'd search for* (keys, full-opacity + medium weight) → *its value* (secondary opacity, everything
else) → *not-code* (comments, tertiary opacity). That's four visual tiers built entirely from tokens
that already exist.

**Mockup recipe** (fakeable in the JSX with plain CSS/JS, no library):
Wrap the gutter's sibling column in a single `overflow-y: auto` flex row so gutter and editor scroll
in lockstep with no manual scroll-sync JS needed. Inside that column, stack two full-size layers in
a `position: relative` box: a `<pre>` underneath (the highlighted HTML, built by a small per-line
tokenizer: split on `\n`, for each line first extract a comment span (`#.*$`), then match a
`^\s*[\[\[]?[^\[\]=]+[\]\]]?\s*$` header line, else match a leading key span
(`^\s*([A-Za-z0-9_.\-"]+)\s*=`) and wrap the rest in the value span, re-`escape`+join with `\n`,
render via `dangerouslySetInnerHTML` or an array of `<span>`s), and a `<textarea>` on top with
`color: transparent; caret-color: var(--label); background: transparent`, identical
font/size/line-height/padding to the `<pre>` so characters land exactly on top of their highlighted
twin. Auto-grow the `<textarea>`'s height to its `scrollHeight` on every change so the *outer* flex
row owns scrolling instead of the textarea itself (avoids nested scrollbars, and is what keeps the
gutter in lockstep for free — same trick used by every "highlighted textarea overlay" library, no
new dependency needed).

Known, called-out mockup simplification: the naive `#.*$` comment regex will incorrectly start a
comment at a `#` inside a quoted string (e.g. `key = "a # not a comment"`). Fine for an illustrative
mockup; the real tokenizer (§4) needs to skip over string spans before looking for `#`.

### 2.3 Inline error/warning markers

Two tiers, honestly different in precision — see §4 for why. Both render the same way: a 3px
colored bar on the gutter's inner-left edge for the affected line, using `--status-error` (red) for
an actual parse failure and `--status-warning` (orange) for a `deprecation` finding — i.e. exactly
`StatusLabel.Kind`/`Banner.Kind`'s existing vocabulary, applied at line granularity instead of only
at the bottom-bar summary. The line number digit itself also tints to match, so the marker reads at
a glance without needing to resolve a thin 3px bar.

The action bar's existing error `StatusLabel` becomes clickable when a position is known: hover
shows an underline + pointer cursor, tooltip "Jump to line N", click scrolls the editor and places
the caret there. When no position could be resolved (semantic-error fallback missed), it stays
exactly as it is today — plain, unclickable text. Never guess and point at the wrong line.

### 2.4 Search-in-editor

No new chrome. `NSTextView` already owns a find-bar implementation (`usesFindBar`) that draws and
manages its own floating overlay above the text — that's system UI, not something this tab designs.
⌘F when the editor has focus is the entire feature; no button needed for discoverability any more
than TextEdit or Xcode need one. Not represented in the JSX mock beyond a one-line comment noting
it's system-drawn — building a fake find-bar overlay would be inventing UI that doesn't belong to
this design system.

## 3. Shared components used or extended

- **`CodeEditor`** (`components/brand/CodeEditor.jsx`) — extended, not replaced. New props needed
  on the real component: `errorLine?: number`, `warningLines?: number[]`, `onCursorMove?: (line,
  col) => void`, `sectionHeaders?: {label: string, line: number}[]` (derived by the tab from the
  buffer and passed down, not computed inside `CodeEditor` itself — keeps the component a dumb
  renderer). Font size unchanged (13px, already corrected in the prior pass — not re-litigating).
  This is the one component every other tab has zero reason to touch, so no cross-tab collision risk
  I can see — flagging by name per the instructions anyway.
- **`Menu`/borderless-menu pattern** — reusing the exact pattern the action bar's `Restore…` already
  establishes in this same tab (`.menuStyle(.borderlessButton).fixedSize()`), not a new component.
  In the JSX mock, model `Sections…` the same way `Restore…` is modeled today.
- **`StatusLabel`** — no shape change, just an added tap affordance on the existing error instance
  in this tab. No new `Kind` needed; still exactly `.error`/`.ok`/`.neutral`.
- Nothing from `IconButton`, `Banner`, `SettingsFooter`, `Badge`, `ListActionBar`, `PanelHeader`, or
  `FormSection` — none of them fit a bare editor-plus-two-bars layout, and I didn't want to force one
  in just to "use" a shared piece.

## 4. Feasibility, honestly, per idea

| Idea | Rating | Why |
|---|---|---|
| **Line numbers gutter** | Moderate | `NSTextView` has no built-in gutter. The standard AppKit idiom is a custom `NSRulerView` subclass set as the scroll view's `verticalRulerView`, drawing numbers via `NSLayoutManager.enumerateLineFragments`/`lineFragmentRect(forGlyphAt:effectiveRange:)`. Well-trodden (it's how essentially every line-numbered `NSTextView` editor does it, going back to widely-copied examples like NoodleKit's line-number view), no third-party framework needed, but it is real new AppKit code, not a property flip. |
| **TOML syntax highlighting (3-tier, §2.2)** | Moderate | Not "full syntax highlighting for an arbitrary grammar" — that would be Hard, and isn't what's needed here. The TOML this app actually writes is a narrow, known subset (dotted keys, basic/literal/multi-line strings, numbers, booleans, arrays, inline tables, `[section]`/`[[array-of-tables]]` headers, `#` comments), so a small hand-written line-oriented tokenizer applied via `NSTextStorage`/`NSLayoutManager` on `textDidChange` (re-highlighting just the edited paragraph range, not the whole buffer, for performance) is realistic near-term work. The one genuinely fiddly sub-case: multi-line triple-quoted strings need re-highlighting a wider surrounding range on edit, not just the changed line, since the comment/string boundary can span edits. That corner is the part I'd budget real time for; the rest is mechanical. |
| **Inline error markers — syntax errors** | Easy–Moderate | The position already exists and is currently thrown away. TOMLKit's underlying `TOMLParseError` (from toml++, distinct from this app's own `TomlParseError`) carries a `source: TOMLSourceRegion` with real `line`/`column` (`TOMLParseError.swift` in the TOMLKit checkout). `parseConfig.swift` catches it and collapses it to `.syntax(e.debugDescription)` — a string, discarding `e.source`. Wiring it through means: (1) give the app's `TomlParseError.syntax` case a `TOMLSourcePosition?` alongside its message, (2) change `ConfigurationWriter.validate`'s return type from `String?` to something that keeps that position (e.g. a small `struct` with `message` + optional `line`) instead of immediately flattening to a joined string, (3) thread it into `RawTomlTab`'s `rawTomlError`. Mostly plumbing through code that already computes the answer — no new capability needed from TOMLKit. |
| **Inline error markers — semantic errors** | Moderate, and permanently best-effort | This is the more common error in practice (wrong type, bad enum value, unknown key) and it's the harder case: `TomlParseError.semantic` only carries a `TomlBacktrace` — a dotted **key path** like `gaps.inner.top` — never a line/column. TOMLKit doesn't expose per-value source positions at all (only parse-error positions), so there's no "read it off the parser" answer here. The only route is a text search: find the nearest preceding `[section.header]` line matching the backtrace's outer keys, then search forward for the leaf key. That's a real heuristic — it can mismatch when the same leaf key name appears under more than one section — so it must be built to degrade to "no marker" rather than confidently point at a wrong line. Worth doing, but should ship as visibly lower-confidence than the syntax-error case, not the same guarantee. |
| **Jump to section** | Easy | Pure client-side line scan for header-shaped lines (`^\s*\[+[^\[\]]+\]+\s*$`), no parser involvement at all. Reuses the tab's own existing `Menu` pattern verbatim. The main "work" is just calling `NSTextView.scrollRangeToVisible`/`setSelectedRange`. |
| **Search-in-editor** | Easy | `textView.usesFindBar = true` is close to a one-line flip; AppKit owns the entire find-bar UI (rendering, incremental match, next/previous, close), so there's no custom interface to design or build — the opposite of the other items here. |
| **Caret position (`Ln`, `Col`)** | Easy | One `NSTextViewDelegate.textViewDidChangeSelection` callback computing line/column from `selectedRange()` against the current string, published to a small `@State`/`@Published` the path bar reads. No gutter, no highlighting, no parser involvement. |

## 5. Fits at 780×520

Nothing here adds height: path bar and action bar keep their existing single-row heights (the
`Ln`/`Col` label and `Sections…` menu are inline additions to the path bar's existing `HStack`, not
new rows), and the gutter lives inside the editor's existing flexible middle region, which just gives
up ~34px of its own horizontal space to the gutter rather than growing the window.

Width check on the path bar, worst case (longest realistic config path, e.g.
`/Users/someone/.aerospork-debug.toml`, which already head-truncates today): trailing cluster is
`Ln 12, Col 4` (~70px) + `Sections…` (~65px) + `Open in TextEdit` (~120px, existing) + `Reload`
(~55px, existing) + three 8px gaps (24px) ≈ 334px, plus the leading doc icon and its padding
(~30px) and the `Spacer(minLength: 12)`. At the 780px floor minus the strip's 14px×2 horizontal
padding (752px usable), that leaves ~376px for the path text — comfortably more than today, when
the same trailing region already has to fit `Open in TextEdit` + `Reload` alone. The path text
already truncates from the head (`.truncationMode(.head)`), so any further squeeze degrades
gracefully rather than breaking layout. The gutter (34–40px) comes out of the editor's own already-
generous middle region, which has no other horizontal constraint competing with it.
