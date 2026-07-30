import Common
import SwiftUI

/// The escape hatch that makes "nothing is unreachable from the GUI" true. Anything the structured
/// tabs can't express — per-monitor gap arrays, hardware fingerprints, custom key-code mappings —
/// is editable here, validated against the same `parseConfig` the app uses at startup.
///
/// Deliberately NOT live-applied: half-typed TOML is invalid most of the time, so this applies
/// explicitly. While this tab has unsaved edits it takes precedence over every other tab.
struct RawTomlTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    private var configPath: String {
        (findCustomConfigUrl().urlOrNil ?? defaultConfigUrl).path(percentEncoded: false)
    }

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            // Not `TextEditor`: it applies macOS text substitutions, and smart quotes turn the `'`
            // in `key = 'focus left'` into `'`, which is not valid TOML.
            CodeEditor(text: $viewModel.rawToml)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            actionBar
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
            Spacer(minLength: 12)
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
                let backups = viewModel.configBackups()
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
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.rawTomlEdited || viewModel.rawTomlError != nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var status: some View {
        if let error = viewModel.rawTomlError {
            StatusLabel(error, kind: .error)
                // Only the error branch wraps: it carries a parser message with a line number,
                // which is the one status here that is worth selecting and pasting.
                .textSelection(.enabled)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        } else if viewModel.rawTomlEdited {
            StatusLabel("Valid — press Apply (⌘S) to write it", kind: .ok)
        } else {
            StatusLabel("Matches the file on disk", kind: .neutral)
        }
    }

    /// `…toml.20260728-163000.backup` -> "28 Jul 2026 at 16:30". Falls back to the raw name rather
    /// than hiding a backup we can't parse -- an unreadable label still restores fine.
    private static func label(for url: URL) -> String {
        let stamp = url.deletingPathExtension().pathExtension // the timestamp component
        let parser = DateFormatter()
        parser.dateFormat = "yyyyMMdd-HHmmss"
        guard let date = parser.date(from: stamp) else { return url.lastPathComponent }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}
