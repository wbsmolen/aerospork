import AppKit
import Common
import SwiftUI

/// The escape hatch that makes "nothing is unreachable from the GUI" true. Anything the structured
/// panes can't express — per-monitor gap arrays, hardware fingerprints, custom key-code mappings —
/// is editable here, validated against the same `parseConfig` the app uses at startup.
///
/// Deliberately NOT live-applied: half-typed TOML is invalid most of the time, so this applies
/// explicitly. While this pane has unsaved edits it takes precedence over every other pane.
struct RawTomlTab: View {
    struct SectionHeader: Identifiable {
        let line: Int
        let label: String
        var id: Int { line }
    }

    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var validationDiagnostic: ConfigurationWriter.ValidationDiagnostic?
    @State private var validationPending = false
    @State private var cursorLine = 1
    @State private var cursorColumn = 1
    @State private var jumpToLine: Int?
    @State private var configPath = ""
    @State private var backups: [URL] = []
    @State private var sectionHeaders: [SectionHeader] = []

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            // Not `TextEditor`: it applies macOS text substitutions, and smart quotes turn the `'`
            // in `key = 'focus left'` into `'`, which is not valid TOML.
            CodeEditor(
                text: $viewModel.rawToml,
                jumpToLine: jumpToLine,
                errorLine: validationDiagnostic?.line,
            ) { line, column in
                cursorLine = line
                cursorColumn = column
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            actionBar
        }
        // Parsing a full config on every keystroke makes fast typing contend with the main-actor
        // SwiftUI update that produced it. `task(id:)` gives us cancellation for free: only the
        // last buffer in a burst is validated, while Apply remains disabled during the short wait.
        .task(id: viewModel.rawToml) {
            let needsValidation = viewModel.rawTomlEdited
            validationPending = needsValidation
            guard needsValidation else {
                validationDiagnostic = nil
                sectionHeaders = Self.sections(in: viewModel.rawToml)
                return
            }
            validationDiagnostic = nil
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            sectionHeaders = Self.sections(in: viewModel.rawToml)
            validationDiagnostic = ConfigurationWriter.diagnostic(viewModel.rawToml)
            validationPending = false
        }
        .task {
            // Both calls touch the file system. Raw TOML publishes on every keystroke, so leaving
            // them in computed view properties turned typing into repeated directory scans.
            configPath = (findCustomConfigUrl().urlOrNil ?? defaultConfigUrl).path(percentEncoded: false)
            backups = viewModel.configBackups()
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.plaintext").foregroundStyle(.secondary)
            Text(configPath)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            CopyButton(value: configPath, help: "Copy config path")
            Spacer(minLength: 12)
            Text("Ln \(cursorLine), Col \(cursorColumn)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize()
            Menu("Sections…") {
                ForEach(sectionHeaders) { header in
                    Button {
                        jump(to: header.line)
                    } label: {
                        Text(header.label).font(.system(.body, design: .monospaced))
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(sectionHeaders.isEmpty)
            .help("Jump to a TOML section")
            // Both were permanent menu bar rows. They belong next to the text they act on.
            Button("Open in \(getTextEditorToOpenConfig().deletingPathExtension().lastPathComponent)") {
                openConfigInExternalEditor()
            }
            .buttonStyle(.borderless)
            .help("External edits are picked up automatically — the config file is watched")

            // Kept only because the watcher cannot arm on a file that does not exist yet: someone
            // who creates their first config entirely outside the app has no other way in.
            if let token: RunSessionGuard = .isServerEnabled {
                Button("Reload") {
                    runDetached("rawTomlApply") {
                        try await runSession(.menuBarButton, token) { _ = reloadConfig() }
                        viewModel.revertChanges()
                    }
                }
                .buttonStyle(.borderless)
                .help("Only needed for a config file created outside the app — every other edit is picked up on save.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .center, spacing: 12) {
                status
                Spacer(minLength: 12)

                // The only way back to a previous config from inside the app. Loading into the
                // editor rather than writing straight over the file means the user sees what they
                // are restoring, and Apply backs up the current file first.
                Menu("Restore…") {
                    ForEach(backups, id: \.self) { url in
                        Button(Self.label(for: url)) { viewModel.loadBackup(url) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(backups.isEmpty)
                .help("Load a previous version of this config into the editor")

                Button("Revert") { viewModel.revertChanges() }
                    .disabled(!viewModel.rawTomlEdited)
                Button("Apply") {
                    Task {
                        viewModel.rawTomlApplyRequested = true
                        await viewModel.saveConfiguration()
                        backups = viewModel.configBackups()
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.rawTomlEdited || validationPending || validationDiagnostic != nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var status: some View {
        if validationPending {
            StatusLabel("Checking…", kind: .neutral)
        } else if let diagnostic = validationDiagnostic {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StatusLabel(diagnostic.message, kind: .error)
                    // Only the error branch wraps: it carries a parser message with a line number,
                    // which is the one status here that is worth selecting and pasting.
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = diagnostic.line {
                    Button("Go to line \(line)") {
                        jump(to: line)
                    }
                    .buttonStyle(.borderless)
                    .fixedSize()
                }
            }
        } else if viewModel.rawTomlEdited {
            StatusLabel("Valid — press Apply (⌘S) to write it", kind: .ok)
        } else {
            StatusLabel("Matches the file on disk", kind: .neutral)
        }
    }

    /// `…toml.20260728-163000.backup` -> "28 Jul 2026 at 16:30". Falls back to the raw name rather
    /// than hiding a backup we can't parse -- an unreadable label still restores fine.
    private static let backupTimestampParser: DateFormatter = {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyyMMdd-HHmmss"
        return parser
    }()

    private static func label(for url: URL) -> String {
        let stamp = url.deletingPathExtension().pathExtension // the timestamp component
        guard let date = backupTimestampParser.date(from: stamp) else { return url.lastPathComponent }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private func jump(to line: Int) {
        // Clearing first makes repeated clicks on the same destination actionable.
        jumpToLine = nil
        Task { @MainActor in jumpToLine = line }
    }

    static func sections(in text: String) -> [SectionHeader] {
        text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap { offset, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.first == "[" else { return nil }
            guard let end = sectionHeaderEnd(in: line) else { return nil }
            let after = line[end...].trimmingCharacters(in: .whitespaces)
            guard after.isEmpty || after.hasPrefix("#") else { return nil }
            return SectionHeader(line: offset + 1, label: String(line[..<end]))
        }
    }

    /// Finds a table header's closing bracket while respecting quoted TOML keys. A plain
    /// `range(of: "]")` loses valid headers such as `["display]rules"]`, so those sections used to
    /// be absent from the jump menu even though the parser accepted the document.
    private static func sectionHeaderEnd(in line: String) -> String.Index? {
        let arrayHeader = line.hasPrefix("[[")
        var index = line.index(line.startIndex, offsetBy: arrayHeader ? 2 : 1)
        var quote: Character?
        var escaped = false

        while index < line.endIndex {
            let character = line[index]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if activeQuote == "\"", character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                index = line.index(after: index)
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                index = line.index(after: index)
                continue
            }
            if character == "]" {
                let afterFirst = line.index(after: index)
                if !arrayHeader { return afterFirst }
                if afterFirst < line.endIndex, line[afterFirst] == "]" {
                    return line.index(after: afterFirst)
                }
            }
            index = line.index(after: index)
        }
        return nil
    }
}

/// Editable text that is code, not prose: monospaced, and with every macOS "helpful" substitution
/// off. This is not cosmetic -- automatic quote substitution turns the `'` in `key = 'focus left'`
/// into a curly quote, which is not valid TOML, so the raw editor could corrupt what you typed.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var jumpToLine: Int?
    var errorLine: Int?
    var onSelectionChange: ((Int, Int) -> Void)?

    init(
        text: Binding<String>,
        jumpToLine: Int? = nil,
        errorLine: Int? = nil,
        onSelectionChange: ((Int, Int) -> Void)? = nil,
    ) {
        _text = text
        self.jumpToLine = jumpToLine
        self.errorLine = errorLine
        self.onSelectionChange = onSelectionChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isHorizontallyResizable = true
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude,
        )
        textView.string = text
        TomlSyntaxHighlighter.apply(to: textView)

        let ruler = LineNumberRulerView(textView: textView, scrollView: scroll)
        ruler.errorLine = errorLine
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.ruler = ruler
        // Attach last: assigning the initial string can emit a selection notification. Publishing
        // that during `makeNSView` mutates SwiftUI state in the middle of a render pass.
        textView.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSelectionChange = onSelectionChange
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            // Only on an external change (Revert / Restore backup): assigning `string` resets the
            // insertion point, which would fight the user on every keystroke if done unconditionally.
            textView.string = text
            TomlSyntaxHighlighter.apply(to: textView)
            context.coordinator.ruler?.refreshLineStarts()
        }
        context.coordinator.ruler?.errorLine = errorLine
        if context.coordinator.lastJumpToLine != jumpToLine {
            context.coordinator.lastJumpToLine = jumpToLine
            if let jumpToLine {
                // Defer out of the view-update transaction, like publishSelection below: changing
                // the selection and first responder synchronously here re-enters AppKit mid-render.
                Task { @MainActor in Self.select(line: jumpToLine, in: textView) }
            }
        }
    }

    private static func select(line target: Int, in textView: NSTextView) {
        guard target > 0 else { return }
        let string = textView.string as NSString
        var location = 0
        var line = 1
        while line < target, location < string.length {
            location = NSMaxRange(string.lineRange(for: NSRange(location: location, length: 0)))
            line += 1
        }
        guard line == target else { return }
        let range = string.lineRange(for: NSRange(location: min(location, string.length), length: 0))
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.window?.makeFirstResponder(textView)
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onSelectionChange: ((Int, Int) -> Void)?
        fileprivate weak var ruler: LineNumberRulerView?
        var lastJumpToLine: Int?
        private var highlightTask: Task<Void, Never>?

        init(text: Binding<String>, onSelectionChange: ((Int, Int) -> Void)?) {
            self.text = text
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            highlightTask?.cancel()
            highlightTask = Task { @MainActor [weak textView, weak self] in
                // Styling attributes do not need to race the keystroke that produced them. A
                // short cancellable delay collapses a typing burst into one linear pass. The
                // gutter's line-start cache rides the same debounce: rebuilding it is a full
                // document scan, and per keystroke that scan dwarfs the drawing it feeds.
                try? await Task.sleep(for: .milliseconds(45))
                guard !Task.isCancelled, let textView else { return }
                TomlSyntaxHighlighter.apply(to: textView)
                self?.ruler?.refreshLineStarts()
            }
            publishSelection(textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            publishSelection(textView)
        }

        func publishSelection(_ textView: NSTextView) {
            // Runs on every keystroke and arrow key, so it counts newlines in place: no substring
            // copy of everything above the cursor, no per-line allocation. Column is a UTF-16
            // offset like everything else NSTextView reports.
            let string = textView.string as NSString
            let location = min(textView.selectedRange().location, string.length)
            var line = 1
            var lineStart = 0
            while lineStart < location {
                let newline = string.range(of: "\n", range: NSRange(location: lineStart, length: location - lineStart))
                if newline.location == NSNotFound { break }
                line += 1
                lineStart = NSMaxRange(newline)
            }
            let column = location - lineStart + 1
            // AppKit can report a selection synchronously from `updateNSView`; defer the publish so
            // it never mutates SwiftUI state during that view-update transaction.
            Task { @MainActor [weak self] in self?.onSelectionChange?(line, column) }
        }
    }
}

/// A restrained line-number gutter built on AppKit's ruler API. It scrolls with the native text
/// view and adds no SwiftUI rows to a document that can easily contain thousands of lines.
fileprivate final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var lineStarts = [0]
    var errorLine: Int? { didSet { if errorLine != oldValue { needsDisplay = true } } }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 42
        refreshLineStarts()
    }

    required init(coder: NSCoder) { die("LineNumberRulerView is never loaded from a nib") }

    override var isFlipped: Bool { true }

    /// Cache document line starts when text changes, then use binary search while scrolling. The
    /// ruler used to rescan every line above the viewport for every draw, making a scroll near the
    /// end of a long config O(total lines) per frame.
    func refreshLineStarts() {
        guard let textView else { return }
        let string = textView.string as NSString
        var starts = [0]
        var location = 0
        while location < string.length {
            let next = NSMaxRange(string.lineRange(for: NSRange(location: location, length: 0)))
            guard next > location else { break }
            if next < string.length {
                starts.append(next)
            } else if next == string.length, string.length > 0 {
                let last = string.character(at: string.length - 1)
                if last == 10 || last == 13 { starts.append(next) }
            }
            location = next
        }
        lineStarts = starts
        needsDisplay = true
    }

    private func lineIndex(containing character: Int) -> Int {
        var lower = 0
        var upper = lineStarts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= character {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return max(0, lower - 1)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }
        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        let string = textView.string as NSString
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let errorAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.systemRed,
        ]
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        var index = lineIndex(containing: visibleCharacters.location)
        while index < lineStarts.count {
            let location = lineStarts[index]
            let glyph = location < string.length
                ? layoutManager.glyphIndexForCharacter(at: location)
                : layoutManager.numberOfGlyphs
            let lineRect: NSRect = if glyph < layoutManager.numberOfGlyphs {
                layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else {
                layoutManager.extraLineFragmentRect
            }
            let point = convert(
                NSPoint(x: 0, y: lineRect.minY + textView.textContainerOrigin.y),
                from: textView,
            )
            if point.y > rect.maxY { break }
            let value = String(index + 1) as NSString
            let attributes = index + 1 == errorLine ? errorAttributes : normalAttributes
            let size = value.size(withAttributes: attributes)
            if point.y + size.height >= rect.minY, point.y <= rect.maxY {
                value.draw(
                    at: NSPoint(x: ruleThickness - size.width - 8, y: point.y),
                    withAttributes: attributes,
                )
            }
            if index + 1 == errorLine {
                NSColor.systemRed.setFill()
                NSRect(x: 0, y: point.y, width: 3, height: max(size.height, lineRect.height)).fill()
            }

            index += 1
        }

        NSColor.separatorColor.setFill()
        NSRect(x: ruleThickness - 1, y: rect.minY, width: 1, height: rect.height).fill()
    }
}

/// Deliberately restrained TOML highlighting: structure, keys, values, comments. It avoids a
/// rainbow token palette and correctly ignores `#` inside quoted and multiline strings.
@MainActor enum TomlSyntaxHighlighter {
    private static let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let emphasisFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let whole = NSRange(location: 0, length: string.length)
        let base: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        textView.typingAttributes = base
        storage.beginEditing()
        storage.setAttributes(base, range: whole)

        var location = 0
        var multilineQuote: unichar?
        repeat {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            let contentsEnd = lineRange.location + lineRange.length
                - trailingNewlineLength(in: string, range: lineRange)
            let contentsRange = NSRange(
                location: lineRange.location,
                length: max(0, contentsEnd - lineRange.location),
            )
            let scan = scanLine(string, range: contentsRange, multilineQuote: &multilineQuote)

            if scan.startedOutsideMultiline {
                let codeEnd = scan.commentLocation ?? NSMaxRange(contentsRange)
                let codeRange = NSRange(
                    location: contentsRange.location,
                    length: max(0, codeEnd - contentsRange.location),
                )
                let trimmed = trimWhitespace(in: string, range: codeRange)
                if trimmed.length > 1,
                   string.character(at: trimmed.location) == 91,
                   string.character(at: NSMaxRange(trimmed) - 1) == 93
                {
                    storage.addAttributes([
                        .font: emphasisFont,
                        .foregroundColor: NSColor.controlAccentColor,
                    ], range: trimmed)
                } else if let equals = scan.equalsLocation {
                    let key = trimWhitespace(
                        in: string,
                        range: NSRange(
                            location: contentsRange.location,
                            length: max(0, equals - contentsRange.location),
                        ),
                    )
                    if key.length > 0 {
                        storage.addAttributes([
                            .font: emphasisFont,
                            .foregroundColor: NSColor.labelColor,
                        ], range: key)
                    }
                }
            }
            if let comment = scan.commentLocation {
                storage.addAttribute(
                    .foregroundColor,
                    value: NSColor.tertiaryLabelColor,
                    range: NSRange(location: comment, length: max(0, contentsEnd - comment)),
                )
            }

            guard NSMaxRange(lineRange) > location else { break }
            location = NSMaxRange(lineRange)
        } while location < string.length

        storage.endEditing()
    }

    private struct LineScan {
        var commentLocation: Int?
        var equalsLocation: Int?
        var startedOutsideMultiline: Bool
    }

    private static func scanLine(
        _ string: NSString,
        range: NSRange,
        multilineQuote: inout unichar?,
    ) -> LineScan {
        var index = range.location
        let end = NSMaxRange(range)
        let startedOutside = multilineQuote == nil
        var quote: unichar?
        var escaped = false
        var equals: Int?

        while index < end {
            let character = string.character(at: index)
            if let multiline = multilineQuote {
                if character == multiline, hasTriple(character, at: index, before: end, in: string) {
                    multilineQuote = nil
                    index += 3
                } else {
                    index += 1
                }
                continue
            }
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if activeQuote == 34, character == 92 {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                index += 1
                continue
            }
            if character == 34 || character == 39 {
                if hasTriple(character, at: index, before: end, in: string) {
                    multilineQuote = character
                    index += 3
                } else {
                    quote = character
                    index += 1
                }
                continue
            }
            if character == 35 {
                return LineScan(
                    commentLocation: index,
                    equalsLocation: equals,
                    startedOutsideMultiline: startedOutside,
                )
            }
            if character == 61, equals == nil { equals = index }
            index += 1
        }
        return LineScan(
            commentLocation: nil,
            equalsLocation: equals,
            startedOutsideMultiline: startedOutside,
        )
    }

    private static func hasTriple(
        _ character: unichar,
        at index: Int,
        before end: Int,
        in string: NSString,
    ) -> Bool {
        index + 2 < end
            && string.character(at: index + 1) == character
            && string.character(at: index + 2) == character
    }

    private static func trimWhitespace(in string: NSString, range: NSRange) -> NSRange {
        var lower = range.location
        var upper = NSMaxRange(range)
        while lower < upper, isWhitespace(string.character(at: lower)) { lower += 1 }
        while upper > lower, isWhitespace(string.character(at: upper - 1)) { upper -= 1 }
        return NSRange(location: lower, length: upper - lower)
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        character == 9 || character == 10 || character == 13 || character == 32
    }

    private static func trailingNewlineLength(in string: NSString, range: NSRange) -> Int {
        guard range.length > 0 else { return 0 }
        let last = string.character(at: NSMaxRange(range) - 1)
        guard last == 10 || last == 13 else { return 0 }
        if range.length > 1,
           last == 10,
           string.character(at: NSMaxRange(range) - 2) == 13
        {
            return 2
        }
        return 1
    }
}
