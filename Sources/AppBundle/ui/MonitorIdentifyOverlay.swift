import AppKit
import SwiftUI

/// Displays ▸ Identify for the Monitors pane: the position number, briefly, in the middle of each
/// screen. The schematic is otherwise the only link between a position and a physical panel, and two
/// identical panels, or DisplayLink panels with nothing but a UUID, look the same in it.
///
/// The panels are AeroSpork's own windows, which `MacApp.getOrRegister` never manages. They are
/// borderless, non-activating and click-through, ordered front without becoming key, so they take
/// neither focus nor a click. No animation: they appear, and then they are gone.
@MainActor
enum MonitorIdentifyOverlay {
    struct Entry: Equatable {
        let position: Int
        let name: String
        /// AppKit coordinates (origin at the main screen's bottom left), what a panel frame takes.
        let screenFrame: CGRect
    }

    /// `MonitorRow.rect` has its origin at the main screen's top left with y going down.
    static func entries(for rows: [ConfigurationViewModel.MonitorRow], mainScreenHeight: CGFloat) -> [Entry] {
        rows.map { row in
            Entry(
                position: row.position,
                name: row.name,
                screenFrame: CGRect(x: row.rect.minX, y: mainScreenHeight - row.rect.maxY, width: row.rect.width, height: row.rect.height),
            )
        }
    }

    /// What VoiceOver hears instead of the overlays.
    static func announcement(for rows: [ConfigurationViewModel.MonitorRow]) -> String {
        rows.map { "Position \($0.position): \($0.name)\($0.isMain ? ", main display" : "")." }.joined(separator: " ")
    }

    private static var panels: [NSPanel] = []
    private static var hideTask: Task<Void, Never>?

    /// A second click restarts the overlays rather than stacking a second set.
    static func show(_ rows: [ConfigurationViewModel.MonitorRow]) {
        hide()
        panels = entries(for: rows, mainScreenHeight: mainMonitor.height).map(makePanel)
        for panel in panels { panel.orderFrontRegardless() }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    static func hide() {
        hideTask?.cancel()
        hideTask = nil
        for panel in panels { panel.orderOut(nil) }
        panels = []
    }

    private static let size = CGSize(width: 220, height: 180)

    private static func makePanel(_ entry: Entry) -> NSPanel {
        let frame = CGRect(
            x: entry.screenFrame.midX - size.width / 2,
            y: entry.screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height,
        )
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar // above the tiled windows, which cover the screen
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)

        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true
        let label = NSHostingView(rootView: IdentifyLabel(entry: entry))
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            label.topAnchor.constraint(equalTo: background.topAnchor),
            label.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        panel.contentView = background
        return panel
    }
}

private struct IdentifyLabel: View {
    let entry: MonitorIdentifyOverlay.Entry
    /// `static let`, like every font in this window (architecture.md#fonts-in-drawing-code).
    private static let numberFont = Font.system(size: 96, weight: .semibold)

    var body: some View {
        VStack(spacing: 4) {
            Text("\(entry.position)")
                .font(Self.numberFont)
                .monospacedDigit()
            Text(entry.name)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
