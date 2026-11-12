# 0009. An AppKit text view for Raw TOML, at 12 pt

- Status: accepted
- Date: 2026-11-12
- Enforced by: `UISettingsTest` (section order, restrained and quote-aware highlighting), `UIChromeConsistencyTest.testTheCodeEditorLivesInTheRawTomlPane`. Review only for the font size.
- Code: `CodeEditor`, `LineNumberRulerView` and `TomlSyntaxHighlighter` in `ConfigurationTabs/RawTomlTab.swift`, `ConfigurationWriter.diagnostic(_:)`

## Context

Raw TOML is the pane that can reach every config key, including the keys that no other pane can show.
SwiftUI `TextEditor` applies the text substitutions of macOS. A smart quote turns the `'` in `key = 'focus left'` into a character that is not valid TOML.
TOMLKit reports the line and the column of a syntax error, so the pane can point at the error and does not have to read the position out of a message.
The first round of the redesign chose 13 pt for the editor, to match the 13 pt of `NSFont.systemFontSize` elsewhere in the window. Nobody built that change, and every release since the panes were built ships the editor at 12 pt.

## Decision

The Raw TOML pane edits the config in an `NSTextView` that uses the monospaced system font at 12 pt.

## Consequences

- The text view disables smart quotes, smart dashes, text replacement and spelling correction. It provides native Find (⌘F), undo, a line-number ruler that marks the line of an error, and horizontal scrolling in place of soft wrap.
- The highlighter is restrained: it marks structure, keys, values and comments, and it ignores a `#` inside a quoted or multiline string.
- The pane shows the cursor position as `Ln`, `Col`, gives a Sections menu in document order, and jumps to the line of a parser error. A semantic error has a key path and no source position, so the pane shows no position for it.
- A monospaced glyph is wider than a proportional glyph of the same size, and long command strings are common in a config. At the 780-point minimum width, 12 pt fits about 8% more columns than 13 pt, so fewer lines need horizontal scrolling.
- The design kit's `CodeEditor.jsx` draws the editor at 13 px and disagrees with the Swift. When the kit is rebuilt for another reason, change the kit to 12 px. A change to `CodeEditor.jsx` alone forces a rebuild of `_ds_bundle.js`.
- If users ask for a larger editor font, add a size setting. Do not change the default for everyone.

## Alternatives considered

- SwiftUI `TextEditor`: its text substitutions corrupt TOML quotes, and it has no ruler and no native Find bar.
- 13 pt, as the first round chose: it matches the labels of the window but fits fewer columns at the minimum size.
- A third-party code editor: AeroSpork has only two third-party dependencies, and AppKit already provides everything this pane needs.
