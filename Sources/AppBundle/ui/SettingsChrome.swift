import AppKit
import Common
import SwiftUI

// The seven panes used to be seven unrelated layouts: one put its caveat in a `Section`, one in a
// `safeAreaInset`, one inline next to a button; three of them invented their own +/- row. These are
// the shared pieces that make them read as one window. Nothing here holds state or touches the
// config -- it is presentation only.

/// Numeric entry you can *type into*. Every number in this window used to be a bare `Stepper` with
/// a 0...500 range, i.e. 500 clicks to reach the top of the range.
struct NumberField: View {
    let title: String
    var unit = "pt"
    var range: ClosedRange<Int> = 0 ... 500
    @Binding var value: Int

    init(_ title: String, unit: String = "pt", range: ClosedRange<Int> = 0 ... 500, value: Binding<Int>) {
        self.title = title
        self.unit = unit
        self.range = range
        _value = value
    }

    /// Clamped, because the text field can produce anything and an out-of-range value would only
    /// surface much later as a config validation error under a control that looks fine.
    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                // Both controls in this row are separately focusable, and `LabeledContent` names
                // the row rather than either of them. An explicit `accessibilityLabel` on each,
                // rather than relying on a hidden title surviving `labelsHidden()`.
                TextField("", value: clamped, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
                    .labelsHidden()
                    .accessibilityLabel(title)
                Text(unit)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Stepper(title, value: clamped, in: range)
                    .labelsHidden()
                    .accessibilityLabel(title)
            }
        }
    }
}

/// Text entry in a settings row. Use this rather than a bare `TextField`.
///
/// `TextField("com.apple.finder", text:)` reads like it takes a placeholder and does not: that
/// argument is the field's *label*, and SwiftUI renders it. Inside a `Form` -- and worse, inside
/// `LabeledContent`, which supplies a label of its own -- the row then drew its label, squeezed the
/// field to near-zero width to make room for the second one, and spilled the intended placeholder
/// out beside it, hyphenated across three lines: `com.ap-ple.find-er`. Every text field in the
/// window had it, because the mistake reads as correct.
///
/// `prompt:` is the placeholder. `labelsHidden()` keeps the label for VoiceOver while stopping it
/// competing with the row's own.
struct SettingsField: View {
    let label: String
    let prompt: String
    /// Monospaced by default: these fields hold app ids, commands, key notation and workspace
    /// names, all of which are things the user could type into the config file. Pass `code: false`
    /// for a field that holds prose, like a filter box.
    var code = true
    @Binding var text: String

    init(_ label: String, prompt: String, code: Bool = true, text: Binding<String>) {
        self.label = label
        self.prompt = prompt
        self.code = code
        _text = text
    }

    var body: some View {
        TextField(label, text: $text, prompt: Text(prompt))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .font(code ? .system(.body, design: .monospaced) : .body)
            // As the trailing half of a `LabeledContent`, a field inherits that row's trailing
            // alignment and puts the caret against the right edge -- so an app id typed left to
            // right appears to grow backwards out of the corner.
            .multilineTextAlignment(.leading)
    }
}

/// A symbol-only action with one accessibility contract everywhere it appears.
///
/// `help` and the accessibility label deliberately share one string: an unlabeled icon button is
/// otherwise announced as only “button”, and locally invented variants were the main source of
/// inconsistent hover targets and destructive styling in the settings panes.
struct IconButton: View {
    let systemImage: String
    let label: String
    var role: ButtonRole?
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The standard inset title used above a list or split-view pane.
struct PanelHeader: View {
    let title: String
    let icon: String

    init(_ title: String, _ icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        // 16/14/8 is the padding for every non-Form panel header (dev-docs/decisions/0005);
        // hand-rolled variants drifted, which is why this component exists.
        SectionLabel(title, icon)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }
}

/// The one hint style in this window. Markdown-aware, so `code` spans render as code without every
/// call site building an AttributedString.
struct SettingsHint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.callout)
            .foregroundStyle(.secondary)
            // Stated, not assumed: a grouped form's section footer right-aligns its text otherwise, which
            // only shows in a real settings window, and reads badly over several lines.
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A hint pinned to the bottom of a tab that has no action bar of its own to hang it off.
struct SettingsFooter: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            SettingsHint(text)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
        .background(.bar)
    }
}

/// The macOS "table with a +/- strip glued to its bottom edge" idiom, once instead of three times.
///
/// The caveat text lives in here rather than in a separate `SettingsFooter` below it, because two
/// stacked `.bar` strips with two dividers is more chrome than the content it explains.
struct ListActionBar: View {
    let addHelp: String
    let removeHelp: String
    let onAdd: () -> Void
    /// `nil` means nothing is selected, so Remove is disabled.
    let onRemove: (() -> Void)?
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                // Icon-only buttons carry no title, so the help text has to double as the label or
                // VoiceOver reads them as "button".
                Button(action: onAdd) { Image(systemName: "plus") }
                    .help(addHelp)
                    .accessibilityLabel(addHelp)
                Button { onRemove?() } label: { Image(systemName: "minus") }
                    .disabled(onRemove == nil)
                    .help(removeHelp)
                    .accessibilityLabel(removeHelp)
                Spacer(minLength: 12)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 12)
            .padding(.top, 7)
            .padding(.bottom, hint == nil ? 7 : 3)

            if let hint {
                // Two lines is the ceiling for pinned chrome: an uncapped hint grew to 60-75pt at
                // 780pt and pushed list content off-screen. The full text lives in the tooltip.
                SettingsHint(hint)
                    .lineLimit(2)
                    .help(hint)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 9)
            }
        }
        .background(.bar)
    }
}

/// A clickable workspace pill: Badge's shape, a Button's behavior. `help` is mandatory and doubles
/// as the accessibility label — the visible text is a workspace name like "3", which is meaningless
/// announced alone. Text keeps Badge's measured `.primary` blend: accent-on-accent-wash reads
/// on-brand but measures ~3.3:1 in light mode, under the 4.5:1 floor for caption text.
struct WorkspaceChip: View {
    let name: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary.opacity(0.72))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .settingsHitTarget()
        .help(help)
        .accessibilityLabel(help)
    }
}

extension View {
    /// 24×24 is the WCAG 2.5.8 floor; caption-size pills and 14pt icon buttons are visually right
    /// but physically too small, so the hit shape grows without moving a pixel.
    func settingsHitTarget() -> some View {
        frame(minWidth: 24, minHeight: 24).contentShape(Rectangle())
    }
}

/// Posts a VoiceOver announcement for state that changes without a focus move — the detail strip
/// swapping when a monitor is selected would otherwise be silent.
@MainActor func settingsAnnounce(_ message: String) {
    NSAccessibility.post(
        element: NSApp as Any,
        notification: .announcementRequested,
        userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ],
    )
}

/// `ContentUnavailableView` is macOS 14+; this app supports 13.
struct ContentUnavailableViewCompat: View {
    let icon: String
    let title: String
    let message: String
    /// `message` is rendered as markdown so a static one can carry `code` spans. Pass `false` when
    /// it interpolates anything the user typed: a filter query of `*foo*` would otherwise come back
    /// italicised instead of as the literal text they are looking for.
    var messageIsMarkdown = true
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 2)
            Text(title).font(.headline)
            // Markdown, so `code` spans in an empty-state message don't read as literal backticks.
            (messageIsMarkdown ? Text(LocalizedStringKey(message)) : Text(verbatim: message))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action).padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A section header that carries an icon, so scanning down a long grouped Form gives you shape as
/// well as text. `Section("…")` alone is a wall of identical grey labels.
struct SectionLabel: View {
    let title: String
    let icon: String

    init(_ title: String, _ icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
    }
}

/// Marks where a row came from, when that is not visible from the row itself.
///
/// There used to be two of these, invented independently in two tabs, at two different paddings
/// (6/2 and 5/1) and only one of which set a foreground colour or an accessibility label. A badge
/// is a *label*, so the help text is mandatory: on its own the word "generated" explains nothing.
struct Badge: View {
    enum Tone {
        case standard, muted

        /// `.muted` is a grey wash rather than an ink wash, so a badge that qualifies a row
        /// (`startup`) sits back from one that explains why a row is read-only (`generated`).
        var fill: Color {
            switch self {
                case .standard: Color.primary.opacity(0.08)
                case .muted: Color.secondary.opacity(0.2)
            }
        }
    }

    let text: String
    var tone: Tone = .standard
    let help: String

    init(_ text: String, tone: Tone = .standard, help: String) {
        self.text = text
        self.tone = tone
        self.help = help
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            // Not `.secondary`: measured over the light-appearance fill that lands at 3.9:1,
            // under the 4.5:1 WCAG 1.4.3 floor for caption-size text. This blend measures ~8:1
            // light and ~7:1 dark.
            .foregroundStyle(.primary.opacity(0.72))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tone.fill))
            .help(help)
            .accessibilityLabel(help)
    }
}

/// Inline validity readout: a tinted symbol plus one line of text, next to the action it describes.
///
/// Colour carries the meaning, so the symbol has to differ too -- red and green are the single most
/// common confusable pair, and this is the readout that tells you whether your config parsed.
struct StatusLabel: View {
    enum Kind {
        case ok, warning, error, neutral

        var icon: String {
            switch self {
                case .ok: "checkmark.circle"
                case .warning, .error: "exclamationmark.triangle.fill"
                case .neutral: "equal.circle"
            }
        }

        var tint: Color {
            switch self {
                case .ok: .green
                case .warning: .orange
                case .error: .red
                case .neutral: .secondary
            }
        }
    }

    let text: String
    let kind: Kind

    init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    var body: some View {
        Label(text, systemImage: kind.icon)
            .font(.callout)
            .foregroundStyle(kind.tint)
    }
}

/// A condition the user must know about for as long as it lasts, pinned above the content.
///
/// Not a notification: AeroSpork has no transient surface at all, on purpose. This is the only
/// thing standing between "my config failed to parse" and an app that looks completely normal
/// while running a keymap the user never wrote, so it is persistent and not dismissible.
struct Banner: View {
    enum Kind {
        case error, warning

        var icon: String {
            switch self {
                case .error: "exclamationmark.octagon.fill"
                case .warning: "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
                case .error: .red
                case .warning: .orange
            }
        }
    }

    let text: String
    let kind: Kind

    init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.tint)
                .font(.title3)
            Text(text)
                .font(.callout)
                // Selectable because the useful half of this text is a parser message someone is
                // about to paste into a bug report.
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(kind.tint.opacity(0.13))
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The editor macOS would use for the config file. Blacklists Xcode: it is too heavy to open plain
/// text files, and it is a common default for `.toml`.
///
/// Memoized. This is used in a SwiftUI *button label*, so it was re-running a LaunchServices
/// `urlForApplication` query -- which touches the on-disk app database -- on every body evaluation
/// of the Raw TOML pane. The answer cannot usefully change while the settings window is open, and
/// the label is cosmetic. It also made the pane the one view that could not be render-tested
/// headlessly, since the test would have been exercising LaunchServices rather than the view.
@MainActor private var cachedTextEditor: URL? = nil

@MainActor func getTextEditorToOpenConfig() -> URL {
    if let cachedTextEditor { return cachedTextEditor }
    let editor = NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" }
        ?? URL(filePath: "/System/Applications/TextEdit.app")
    cachedTextEditor = editor
    return editor
}

/// Opens the user's config in that editor, creating it from the bundled default if it is missing.
@MainActor func openConfigInExternalEditor() {
    let editor = getTextEditorToOpenConfig()
    let fallbackConfig = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
    switch findCustomConfigUrl() {
        case .file(let url):
            url.open(with: editor)
        case .noCustomConfigExists:
            _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
            // `ConfigFileWatcher.start()` bails when there is no user config to watch, and it ran at
            // launch. Without re-arming here, the file we just created is not watched, so the edit
            // the user is about to make in that editor would never be picked up.
            ConfigFileWatcher.start()
            fallbackConfig.open(with: editor)
        case .ambiguousConfigError:
            fallbackConfig.open(with: editor)
    }
}

/// Small borderless "copy this string" button. Two tabs need it and they had two different ones.
struct CopyButton: View {
    let value: String
    var help: String = "Copy to clipboard"
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.4)); copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .frame(width: 14)
                // The colour change is the entire confirmation -- there is no toast anywhere in
                // this app -- so the checkmark has to read as "done" and not just as a third icon.
                .foregroundStyle(copied ? StatusLabel.Kind.ok.tint : Color.secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(copied ? "Copied" : help)
    }
}
