import Common
import SwiftUI

struct KeyBindingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var selectedMode = mainModeId
    @State private var newKey = ""
    @State private var newCommand = ""
    @State private var recording = false
    /// Which row's recorder is armed, by key. One piece of state instead of one per row.
    @State private var recordingRow: String?
    @State private var newMode = ""
    @State private var addingMode = false
    @State private var query = ""

    private var allRows: [ConfigurationViewModel.DisplayBinding] { viewModel.displayBindings(mode: selectedMode) }

    /// A real keymap is 40-80 bindings -- and under config v2 most of them are *generated*, so the
    /// list is longer than anything written in the file. Scrolling it looking for "the one that
    /// moves a window to monitor 2" is the single slowest thing in this window.
    private var rows: [ConfigurationViewModel.DisplayBinding] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return allRows }
        return allRows.filter { $0.key.lowercased().contains(needle) || $0.command.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(spacing: 0) {
            modeBar
            Divider()
            content
            composer
        }
        .onAppear {
            let names = viewModel.allModeNames
            if !names.contains(selectedMode), let first = names.first { selectedMode = first }
        }
    }

    private var modeBar: some View {
        HStack(spacing: 10) {
            if viewModel.allModeNames.isEmpty {
                Text("No modes").foregroundStyle(.secondary)
            } else {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(viewModel.allModeNames, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // One menu instead of two naked +/- buttons whose meaning ("add a *mode*, not a
            // binding") was only discoverable through a tooltip.
            Menu {
                Button("New mode…") { addingMode = true }
                Button("Delete “\(selectedMode)”", role: .destructive) { removeMode() }
                    .disabled(!viewModel.canRemoveMode(selectedMode))
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .popover(isPresented: $addingMode) {
                HStack {
                    TextField("mode name, e.g. resize", text: $newMode)
                        .frame(width: 190)
                        .onSubmit(commitMode)
                    Button("Add", action: commitMode)
                        .keyboardShortcut(.defaultAction)
                        .disabled(newMode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding()
            }

            Spacer(minLength: 16)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter", text: $query)
                    .textFieldStyle(.plain)
                    // Compressible. The mode picker beside it is `.fixedSize()`, so at the 780pt
                    // minimum width a handful of modes pushed a hard-150pt filter box off the edge.
                    .frame(minWidth: 70, idealWidth: 150)
                    .accessibilityLabel("Filter bindings")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.allModeNames.isEmpty {
            ContentUnavailableViewCompat(
                icon: "keyboard",
                title: "No key bindings",
                // No backticks: SwiftUI's markdown parser reads the `[` of a code span containing
                // brackets as the start of a link, fails, and falls back to the literal text --
                // backticks and all. Anything with brackets in it is written as plain prose.
                message: "Your config binds nothing and generates nothing. Record a shortcut below to add the first binding.",
            )
        } else if rows.isEmpty {
            ContentUnavailableViewCompat(
                icon: query.isEmpty ? "keyboard" : "magnifyingglass",
                title: query.isEmpty ? "“\(selectedMode)” has no bindings" : "No matches",
                message: query.isEmpty
                    ? "Record a shortcut below to add the first one."
                    : "Nothing in “\(selectedMode)” matches “\(query)”.",
                // The query is whatever the user typed; markdown would render `*foo*` as italic foo
                // rather than the text they are actually searching for.
                messageIsMarkdown: query.isEmpty,
            )
        } else {
            List {
                ForEach(rows) { row($0) }
            }
            .listStyle(.inset)
        }
    }

    /// An editable row is one the writer owns. A generated or `[keys]` row is shown read-only with
    /// its origin, and Override copies it into the writable set -- where it layers on top, exactly
    /// as the parser layers `[mode.*]` over both.
    @ViewBuilder
    private func row(_ b: ConfigurationViewModel.DisplayBinding) -> some View {
        HStack(spacing: 8) {
            if let rowId = b.rowId {
                KeyRecorderField(notation: key(rowId, b.key), isRecording: recorder(b.key), showsClear: false)
                    .frame(width: 150, height: 22)
                SettingsField("Command", prompt: "focus left", text: command(rowId, b.command))
                    .accessibilityLabel("Command for \(b.key)")
                Button { remove(rowId) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Remove this binding")
                    .accessibilityLabel("Remove \(b.key)")
            } else {
                Text(KeyNotation.pretty(b.key))
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 150, alignment: .leading)
                Text(b.command)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // Read-only rows have no field to scroll, so a chained command truncated with
                    // no way to see the rest short of clicking Override, which edits the config.
                    .help(b.command)
                Spacer(minLength: 8)
                // Generated bindings appear nowhere in the config file, so without this the tab
                // shows dozens of rows the user cannot find when they go looking.
                Badge("generated", help: "Generated from mod and workspaces. It is not written in your config file.")
                Button("Override") { override(b) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Override \(b.key)")
            }
        }
        .padding(.vertical, 1)
    }

    private func key(_ id: ConfigurationViewModel.BindingRow.ID, _ current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { new in
                // A cleared recorder would write an empty TOML key, which does not parse.
                guard !new.isEmpty, new != current else { return }
                // Re-keying onto a key another row already owns used to produce two rows with the
                // same TOML key -- one invisible in this table, and a file that no longer parses.
                guard viewModel.updateBinding(mode: selectedMode, id: id, key: new) else {
                    viewModel.errorMessage = "\(KeyNotation.pretty(new)) is already bound in “\(selectedMode)”. "
                        + "Edit or remove that binding first."
                    return
                }
                viewModel.errorMessage = nil
                viewModel.scheduleAutoSave()
            },
        )
    }

    private func command(_ id: ConfigurationViewModel.BindingRow.ID, _ current: String) -> Binding<String> {
        Binding(
            get: { current },
            set: { new in
                guard new != current else { return }
                viewModel.updateBinding(mode: selectedMode, id: id, command: new)
                viewModel.scheduleAutoSave()
            },
        )
    }

    private func recorder(_ key: String) -> Binding<Bool> {
        Binding(get: { recordingRow == key }, set: { recordingRow = $0 ? key : nil })
    }

    /// What the shortcut in the composer is bound to *right now*, if anything. Recomputed per
    /// keystroke over ~80 rows, which is nothing next to the SwiftUI update it rides along with.
    private var conflict: ConfigurationViewModel.DisplayBinding? {
        viewModel.existingBinding(mode: selectedMode, key: newKey)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                KeyRecorderField(notation: $newKey, isRecording: $recording)
                    .frame(width: 170, height: 22)
                SettingsField("New command", prompt: "command, e.g. focus left", text: $newCommand)
                    .onSubmit(add)
                // "Add" on a taken shortcut is a lie: it replaces. Saying which of the two it is
                // *before* the click is the whole point of the conflict check.
                Button(conflict == nil ? "Add" : "Replace", action: add)
                    .disabled(newKey.isEmpty || newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            if let conflict {
                conflictBanner(conflict)
                    .padding(.horizontal, 14)
                    .padding(.top, 7)
            }

            // One bottom strip, not a composer bar plus a separate footer bar under it.
            SettingsHint(summary)
                .padding(.horizontal, 14)
                .padding(.top, 7)
                .padding(.bottom, 10)
        }
        .background(.bar)
    }

    /// Names the shortcut, what owns it, and offers to go look at it. Without the last part
    /// "already bound" is a dead end in a list of eighty rows.
    private func conflictBanner(_ conflict: ConfigurationViewModel.DisplayBinding) -> some View {
        HStack(spacing: 6) {
            // Not a `StatusLabel`: the text is composite (a mono command spliced into prose, then a
            // button), which its plain-String API cannot express. The symbol and tint still come
            // from there, so a warning looks the same here as it does anywhere else.
            Image(systemName: StatusLabel.Kind.warning.icon)
                .foregroundStyle(StatusLabel.Kind.warning.tint)
            (Text("\(KeyNotation.pretty(conflict.key)) is already bound to ")
                + Text(conflict.command).font(.system(.callout, design: .monospaced)))
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            if conflict.origin == .generated {
                Text("(generated)").font(.callout).foregroundStyle(.secondary)
            }
            Button("Show") { query = conflict.key }
                .buttonStyle(.borderless)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// Says out loud how many of the listed bindings are written in the file and how many are not.
    /// Without it the tab looks like a config with 91 binding lines, which is the misconception
    /// config v2 exists to kill.
    private var summary: String {
        let generated = allRows.count { $0.origin == .generated }
        var parts: [String] = []
        if generated > 0 { parts.append("\(generated) generated by mod") }
        parts.append("\(allRows.count { $0.origin == .explicit }) written in your config")
        let separator = ConfigurationViewModel.commandSeparator.trimmingCharacters(in: .whitespaces)
        return parts.joined(separator: ", ") +
            (generated > 0 ? ". Generated bindings have no line to edit — Override copies one here first." : "") +
            " Chain commands with `\(separator)`."
    }

    /// Only clear the fields when the binding was actually taken. Clearing unconditionally is how
    /// a typed binding used to disappear without a trace.
    private func add() {
        guard viewModel.addBinding(mode: selectedMode, key: newKey, command: newCommand) else { return }
        viewModel.scheduleAutoSave()
        newKey = ""
        newCommand = ""
    }

    /// Copies a generated binding into the writable set, seeded with what it does now. Removing the
    /// copy later restores the generated one -- nothing was ever taken away, only shadowed.
    private func override(_ b: ConfigurationViewModel.DisplayBinding) {
        guard viewModel.addBinding(mode: selectedMode, key: b.key, command: b.command) else { return }
        viewModel.scheduleAutoSave()
    }

    private func commitMode() {
        let name = newMode.trimmingCharacters(in: .whitespaces)
        guard viewModel.addMode(name) else { return }
        selectedMode = name
        newMode = ""
        addingMode = false
        // An empty mode writes no TOML, so there is nothing to save until it has a binding.
    }

    private func removeMode() {
        viewModel.removeMode(selectedMode)
        selectedMode = viewModel.allModeNames.first ?? mainModeId
        viewModel.scheduleAutoSave()
    }

    private func remove(_ id: ConfigurationViewModel.BindingRow.ID) {
        viewModel.removeBinding(mode: selectedMode, id: id)
        viewModel.scheduleAutoSave()
    }
}

/// Click, then press a shortcut. Beats typing `alt-shift-h` by hand and guessing the notation.
private struct KeyRecorderField: View {
    @Binding var notation: String
    @Binding var isRecording: Bool
    /// Off for an existing row: clearing it would leave a binding with no key, which is not a
    /// thing that can be written, so the button would be visibly dead.
    var showsClear = true

    var body: some View {
        Recorder(notation: $notation, isRecording: $isRecording)
            .overlay(alignment: .trailing) {
                if showsClear, !notation.isEmpty {
                    Button { notation = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 4)
                        .help("Clear")
                        .accessibilityLabel("Clear this shortcut")
                }
            }
    }

    private struct Recorder: NSViewRepresentable {
        @Binding var notation: String
        @Binding var isRecording: Bool

        func makeNSView(context: Context) -> RecorderView {
            let v = RecorderView(frame: .zero)
            v.onCapture = { notation = $0; isRecording = false }
            return v
        }

        func updateNSView(_ nsView: RecorderView, context: Context) {
            nsView.onCapture = { notation = $0; isRecording = false }
            nsView.displayed = notation
            nsView.needsDisplay = true
        }
    }

    final class RecorderView: NSView {
        var onCapture: ((String) -> Void)?
        var displayed = "" {
            didSet { setAccessibilityValue(displayed.isEmpty ? "" : KeyNotation.pretty(displayed)) }
        }

        private var recording = false

        /// A hand-drawn `NSView` is invisible to accessibility unless it says otherwise, and this
        /// one is the primary control of the tab.
        override init(frame: NSRect) {
            super.init(frame: frame)
            setAccessibilityElement(true)
            setAccessibilityRole(.textField)
            setAccessibilityLabel("Shortcut recorder")
            setAccessibilityHelp("Click, then press the key combination you want to bind")
        }

        required init?(coder: NSCoder) { die("RecorderView is never loaded from a nib") }

        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool { recording = true; needsDisplay = true; return true }
        override func resignFirstResponder() -> Bool { recording = false; needsDisplay = true; return true }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

        /// Without this, a shortcut that is also a menu equivalent never reaches `keyDown` -- so
        /// trying to record ⌘Q quit the app and ⌘W closed the settings window instead of being
        /// captured. While recording, we are the only thing that gets to see the key.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, window?.firstResponder === self else { return false }
            keyDown(with: event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard let notation = KeyNotation.from(event: event) else { return }
            displayed = notation
            onCapture?(notation)
            window?.makeFirstResponder(nil)
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.textBackgroundColor).setFill()
            path.fill()
            (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = recording ? 2 : 1
            path.stroke()

            let text = !displayed.isEmpty ? KeyNotation.pretty(displayed) : (recording ? "Press a shortcut…" : "Click to record")
            // Monospace is for the captured notation -- something the user could type into their
            // config. The instructional placeholder is prose and takes the system face, the same
            // split the colour below already makes.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: displayed.isEmpty
                    ? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                    : NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
                .foregroundColor: displayed.isEmpty ? NSColor.placeholderTextColor : NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            // `draw(in:)`, not `draw(at:)`: without a bounding rect AppKit clips at the view edge
            // mid-glyph with no ellipsis, and a binding like `alt-shift-leftSquareBracket` is wider
            // than the 150pt field.
            let inset: CGFloat = 8
            (text as NSString).draw(
                in: NSRect(x: inset, y: (bounds.height - size.height) / 2,
                           width: max(0, bounds.width - inset * 2), height: size.height),
                withAttributes: attrs,
            )
        }
    }
}

enum KeyNotation {
    /// Build aerospork key notation (`alt-shift-h`) from a real key event.
    static func from(event: NSEvent) -> String? {
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("alt") }
        if flags.contains(.shift) { parts.append("shift") }
        if flags.contains(.command) { parts.append("cmd") }
        guard let key = keyName(for: event) else { return nil }
        parts.append(key)
        return parts.joined(separator: "-")
    }

    private static func keyName(for event: NSEvent) -> String? {
        // Named keys first; charactersIgnoringModifiers is empty or unhelpful for these.
        switch Int(event.keyCode) {
            case 36: return "enter"
            case 48: return "tab"
            case 49: return "space"
            case 51: return "backspace"
            case 53: return "esc"
            case 123: return "left"
            case 124: return "right"
            case 125: return "down"
            case 126: return "up"
            default: break
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), let first = chars.first else { return nil }
        switch first {
            case "-": return "minus"
            case "=": return "equal"
            case ".": return "period"
            case ",": return "comma"
            case "/": return "slash"
            case "\\": return "backslash"
            case "'": return "quote"
            case ";": return "semicolon"
            case "`": return "backtick"
            case "[": return "leftSquareBracket"
            case "]": return "rightSquareBracket"
            default: return first.isLetter || first.isNumber ? String(first) : nil
        }
    }

    /// Render notation with real modifier glyphs. Only the leading modifier tokens are replaced, so
    /// a key literally named e.g. "command" in the tail is left alone.
    static func pretty(_ notation: String) -> String {
        let glyphs = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"]
        var parts = notation.split(separator: "-").map(String.init)
        guard parts.count > 1 else { return notation }
        let key = parts.removeLast()
        return parts.map { glyphs[$0] ?? "\($0)-" }.joined() + key
    }
}
