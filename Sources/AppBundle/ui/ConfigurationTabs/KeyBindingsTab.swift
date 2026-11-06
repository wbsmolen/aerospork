import Common
import SwiftUI

struct KeyBindingsTab: View {
    private struct BindingCategory: Identifiable {
        let id: String
        let title: String
        let icon: String
        let commandPrefixes: Set<String>
    }

    private struct OtherModeMatch: Identifiable {
        let mode: String
        let binding: ConfigurationViewModel.DisplayBinding

        var id: String { "\(mode)\u{0}\(binding.key)\u{0}\(binding.command)" }
    }

    private static let categories = [
        BindingCategory(
            id: "focus", title: "Focus", icon: "scope",
            commandPrefixes: ["focus", "focus-monitor", "focus-back-and-forth"],
        ),
        BindingCategory(
            id: "move", title: "Move & workspace", icon: "rectangle.3.group",
            commandPrefixes: [
                "move", "move-mouse", "move-node-to-monitor", "move-node-to-workspace",
                "move-workspace-to-monitor", "summon-workspace", "workspace", "workspace-back-and-forth",
            ],
        ),
        BindingCategory(
            id: "layout", title: "Layout & resize", icon: "rectangle.split.2x1",
            commandPrefixes: [
                "balance-sizes", "flatten-workspace-tree", "fullscreen", "join-with", "layout",
                "macos-native-fullscreen", "macos-native-minimize", "resize", "split",
            ],
        ),
        BindingCategory(
            id: "system", title: "Mode & system", icon: "gearshape",
            commandPrefixes: [
                "close", "close-all-windows-but-current", "config", "enable", "exec-and-forget", "mode",
                "open-settings", "reload-config", "trigger-binding", "volume",
            ],
        ),
        BindingCategory(id: "other", title: "Other", icon: "ellipsis", commandPrefixes: []),
    ]

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

    /// A segmented control's width is the sum of its segments' intrinsic widths and cannot shrink
    /// below that. The stock config (2 modes) fits comfortably at the 880pt ideal width; the old
    /// `.fixedSize()`-only version overflowed the 780pt minimum at 9. 5 is the point past which a
    /// realistic mode name (5-10 chars) plus segment padding starts crowding the filter box before
    /// that ceiling, so it is where this switches to a bounded-width menu instead of trying to keep
    /// shrinking a control that has a hard floor.
    static func modePickerIsSegmented(count: Int) -> Bool { count <= 5 }

    private var allRows: [ConfigurationViewModel.DisplayBinding] { viewModel.displayBindings(mode: selectedMode) }

    /// A real keymap is 40-80 bindings -- and under config v2 most of them are *generated*, so the
    /// list is longer than anything written in the file. Scrolling it looking for "the one that
    /// moves a window to monitor 2" is the single slowest thing in this window.
    private var rows: [ConfigurationViewModel.DisplayBinding] {
        let needle = normalizedQuery
        guard !needle.isEmpty else { return allRows }
        return allRows.filter { $0.key.lowercased().contains(needle) || $0.command.lowercased().contains(needle) }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Search is global even though editing remains scoped to the selected mode. A shortcut can
    /// otherwise look missing simply because the user forgot which mode owns it.
    private var otherModeMatches: [OtherModeMatch] {
        guard !normalizedQuery.isEmpty else { return [] }
        return viewModel.allModeNames
            .filter { $0 != selectedMode }
            .flatMap { mode in
                viewModel.displayBindings(mode: mode).compactMap { binding in
                    guard binding.key.lowercased().contains(normalizedQuery)
                        || binding.command.lowercased().contains(normalizedQuery)
                    else { return nil }
                    return OtherModeMatch(mode: mode, binding: binding)
                }
            }
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
            } else if Self.modePickerIsSegmented(count: viewModel.allModeNames.count) {
                Picker("Mode", selection: $selectedMode) {
                    ForEach(viewModel.allModeNames, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            } else {
                // A segmented control has a hard per-segment width floor and cannot shrink past
                // it -- past this many modes it overflows the window no matter what its neighbours
                // give up. `.menu` is bounded to one control's width regardless of option count.
                Picker("Mode", selection: $selectedMode) {
                    ForEach(viewModel.allModeNames, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 150)
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
                    // Compressible, and capped. The mode picker beside it is `.fixedSize()`, so a
                    // hard 150pt pushed the filter off the edge once a config had enough modes.
                    //
                    // `maxWidth` is not optional here: `minWidth:idealWidth:` alone leaves the upper
                    // bound to the child, and a `.plain` TextField is greedy -- it ties with the
                    // Spacer and swallows the slack, so at 880pt with the stock two modes the search
                    // pill rendered 649pt wide instead of 150.
                    //
                    // This buys one more mode, not a fix: the segmented picker is still
                    // `.fixedSize()`, so a config with nine modes still overflows 780pt.
                    .frame(minWidth: 70, idealWidth: 150, maxWidth: 150)
                    .accessibilityLabel("Filter bindings")
                if !query.isEmpty {
                    IconButton(systemImage: "xmark.circle.fill", label: "Clear search") { query = "" }
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
            let matchingModeSet = Set(otherModeMatches.map(\.mode))
            let matchingModes = viewModel.allModeNames.filter { matchingModeSet.contains($0) }
            ContentUnavailableViewCompat(
                icon: query.isEmpty ? "keyboard" : "magnifyingglass",
                title: query.isEmpty ? "“\(selectedMode)” has no bindings" : "No matches",
                message: noMatchesMessage(matchingModes: matchingModes),
                // The query is whatever the user typed; markdown would render `*foo*` as italic foo
                // rather than the text they are actually searching for.
                messageIsMarkdown: query.isEmpty,
                actionTitle: noMatchesActionTitle(matchingModes: matchingModes),
                action: {
                    if matchingModes.count == 1, let mode = matchingModes.first {
                        selectedMode = mode
                    } else {
                        query = ""
                    }
                },
            )
        } else {
            List {
                if normalizedQuery.isEmpty {
                    let populated = Self.categories.filter { category in
                        rows.contains { self.category(for: $0.command) == category.id }
                    }
                    if populated.count < 2 {
                        ForEach(rows) { row($0) }
                    } else {
                        ForEach(populated) { category in
                            let categoryRows = rows.filter { self.category(for: $0.command) == category.id }
                            Section {
                                ForEach(categoryRows) { row($0) }
                            } header: {
                                Label("\(category.title) — \(categoryRows.count)", systemImage: category.icon)
                            }
                        }
                    }
                } else {
                    if !rows.isEmpty {
                        Section("In \(selectedMode)") {
                            ForEach(rows) { row($0) }
                        }
                    }
                    if !otherModeMatches.isEmpty {
                        Section("In other modes — \(otherModeMatches.count)") {
                            ForEach(otherModeMatches) { otherModeRow($0) }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func noMatchesMessage(matchingModes: [String]) -> String {
        guard !query.isEmpty else { return "Record a shortcut below to add the first one." }
        let base = "Nothing in “\(selectedMode)” matches “\(query)”."
        if matchingModes.count == 1, let mode = matchingModes.first { return "\(base) It’s bound in “\(mode)” instead." }
        if matchingModes.count > 1 { return "\(base) It’s bound in other modes." }
        return base
    }

    private func noMatchesActionTitle(matchingModes: [String]) -> String? {
        guard !query.isEmpty else { return nil }
        if matchingModes.count == 1, let mode = matchingModes.first { return "Go to “\(mode)”" }
        return "Clear filter"
    }

    private func category(for command: String) -> String {
        let prefix = command
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace }
            .first
            .map(String.init) ?? ""
        return Self.categories.first { !$0.commandPrefixes.isEmpty && $0.commandPrefixes.contains(prefix) }?.id
            ?? "other"
    }

    private func otherModeRow(_ match: OtherModeMatch) -> some View {
        HStack(spacing: 8) {
            Text(match.mode)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)
            Text(KeyNotation.pretty(match.binding.key))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            Text(match.binding.command)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if match.binding.origin == .generated {
                Badge("generated", help: "Generated from mod and workspaces. It is not written in your config file.")
            }
            Button("Go") { selectedMode = match.mode }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show this binding in \(match.mode)")
        }
        .help("\(match.mode): \(match.binding.command)")
    }

    /// An editable row is one the writer owns. A generated or `[keys]` row is shown read-only with
    /// its origin, and Override copies it into the writable set -- where it layers on top, exactly
    /// as the parser layers `[mode.*]` over both.
    @ViewBuilder
    private func row(_ b: ConfigurationViewModel.DisplayBinding) -> some View {
        HStack(spacing: 8) {
            if let rowId = b.rowId {
                KeyRecorderField(notation: key(rowId, b.key), isRecording: recorder(b.key), showsClear: false)
                    .frame(width: 170, height: 22)
                SettingsField("Command", prompt: "focus left", text: command(rowId, b.command))
                    .accessibilityLabel("Command for \(b.key)")
                IconButton(systemImage: "doc.on.doc", label: "Duplicate “\(b.command)”") { duplicate(b) }
                IconButton(systemImage: "minus.circle", label: "Remove “\(b.key)”", role: .destructive) {
                    remove(rowId)
                }
            } else {
                Text(KeyNotation.pretty(b.key))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(KeyNotation.pretty(b.key))
                    .frame(width: 170, alignment: .leading)
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
                IconButton(systemImage: "doc.on.doc", label: "Duplicate “\(b.command)”") { duplicate(b) }
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

            if let otherModeSummary {
                StatusLabel(otherModeSummary, kind: .neutral)
                    .padding(.horizontal, 14)
                    .padding(.top, 7)
            }

            // One bottom strip, not a composer bar plus a separate footer bar under it.
            // `summary` grows with the keymap (mod-generated count, written count, both trailing
            // sentences) and the tab has no ScrollView wrapping modeBar+composer, so an unbounded
            // hint could push the composer past the window edge. Capped at two lines with the full
            // text on hover/VoiceOver instead.
            SettingsHint(summary)
                .lineLimit(2)
                .help(summary)
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
                Badge("generated", help: "Generated from mod and workspaces. It is not written in your config file.")
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
            " Chain commands with `\(separator)`. A workspace named by a binding stays available even with no windows."
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

    private func duplicate(_ binding: ConfigurationViewModel.DisplayBinding) {
        newKey = ""
        newCommand = binding.command
        recording = false
    }

    private var otherModeOwners: [String] {
        guard !newKey.isEmpty else { return [] }
        return viewModel.allModeNames.filter { mode in
            mode != selectedMode && viewModel.existingBinding(mode: mode, key: newKey) != nil
        }
    }

    private var otherModeSummary: String? {
        let owners = otherModeOwners
        guard !owners.isEmpty else { return nil }
        if owners.count == 1 { return "Also bound in “\(owners[0])” mode." }
        let named = owners.prefix(2).map { "“\($0)”" }.joined(separator: ", ")
        let remainder = owners.count > 2 ? ", and \(owners.count - 2) more" : ""
        return "Also bound in \(named)\(remainder) modes."
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
                    IconButton(systemImage: "xmark.circle.fill", label: "Clear this shortcut") { notation = "" }
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 4)
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

        /// Made once and kept, never asked for while drawing. In a debug build on macOS 27 a fresh system font
        /// was now and then a broken object. CoreText raised an exception copying the attributes, which nothing
        /// here can catch, so it took the app down within a few pane switches. With a row per binding, every
        /// redraw of this pane asked.
        private static let promptFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        private static let notationFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

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
                .font: displayed.isEmpty ? Self.promptFont : Self.notationFont,
                .foregroundColor: displayed.isEmpty ? NSColor.placeholderTextColor : NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let inset: CGFloat = 8
            let rect = NSRect(x: inset, y: (bounds.height - size.height) / 2,
                              width: max(0, bounds.width - inset * 2), height: size.height)
            // `draw(with:options:attributes:context:)`, not `draw(in:withAttributes:)`: the latter
            // ignores `paragraph.lineBreakMode` entirely and hard-clips at the rect edge mid-glyph
            // with no ellipsis, so a binding like `alt-shift-leftSquareBracket` sheared off instead
            // of truncating. This overload honours the paragraph style. The 3-arg sibling without
            // `context:` does too, but is in `NSStringDrawingDeprecated`.
            (text as NSString).draw(
                with: rect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: attrs,
                context: nil,
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
