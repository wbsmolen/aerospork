import Common
import Foundation
import SwiftUI

/// One label style, not four.
///
/// The four styles behind the old "Experimental UI Settings" submenu were two plain-text variants
/// that differed only by font, plus two chip variants that differed only by whether *invisible*
/// workspaces were appended at 60% opacity -- which, on a 4-monitor setup, is a menu bar full of
/// grey squares for workspaces you are not looking at. What survives is the one that answers the
/// only question the menu bar can answer at a glance: which workspace is on each monitor, and
/// which of them has focus.
///
/// Chips are drawn, never composed from `N.square.fill` SF Symbols: the symbols only exist for
/// 0...50 and single capital letters, so a config with a workspace named `web` used to get a
/// completely different-looking label than one named `3`.
@MainActor
struct MenuBarLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Plain-text rendering of the same information. Used verbatim on macOS 13, and as the fallback
    /// if rasterization fails.
    let text: String
    /// What VoiceOver reads, on every path: `traySpokenText`.
    let spokenText: String
    let items: [TrayItem]

    private let height = CGFloat(40)
    private let spacing = CGFloat(5)
    private let border = CGFloat(3)

    /// The menu bar is monochrome and follows the *menu bar's* appearance, which is not always the
    /// app's (a light desktop picture under a dark system theme, for one).
    private var ink: Color { colorScheme == .dark ? .white : .black }

    var body: some View {
        if items.isEmpty {
            // Before the first refresh there is nothing to draw, and an empty label is an
            // *invisible* menu bar item -- the app looks like it failed to start.
            Image(systemName: "square.grid.2x2")
        } else if #available(macOS 14, *) { // https://github.com/wbsmolen/aerospork/issues/1122
            // Using scale: 1 results in a blurry image for unknown reasons
            if let cgImage = ImageRenderer(content: chips).cgImage {
                Image(cgImage, scale: 2, label: Text(spokenText))
            } else {
                Text(text).accessibilityLabel(spokenText)
            }
        } else { // macOS 13 and lower
            Text(text).accessibilityLabel(spokenText)
        }
    }

    private var chips: some View {
        HStack(spacing: spacing) {
            ForEach(items) { chip($0) }
        }
        .frame(height: height)
    }

    /// Focused workspace and the active mode read as filled; everything else as an outline. The
    /// mode is a capsule so it can never be mistaken for a workspace -- that is what the old
    /// literal `":"` separator was doing, at the cost of a whole extra glyph of menu bar width.
    @ViewBuilder
    private func chip(_ item: TrayItem) -> some View {
        // Emoji are drawn bare: scaled into a chip they turn into unreadable smudges.
        if item.name.containsEmoji() {
            Text(item.name)
                .font(.system(size: height * 0.8))
                .frame(height: height)
        } else {
            let radius = item.type == .mode ? height / 2 : height / 4
            // 0.62, not 0.72: the chip is rasterized at `height` and then scaled down to the menu
            // bar's ~22pt, where 0.72 lands well above the ~14pt the clock and menu titles use and
            // reads as oversized next to them.
            let label = Text(item.name)
                .font(.system(size: height * 0.62, weight: .semibold, design: .rounded))
                .padding(.horizontal, radius * 0.9)
                .frame(height: height)
            if item.isActive {
                ZStack {
                    label.background { RoundedRectangle(cornerRadius: radius, style: .continuous) }
                    label.blendMode(.destinationOut) // knock the glyphs out of the fill
                }
                .compositingGroup()
                .foregroundStyle(ink)
            } else {
                label
                    .background {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(lineWidth: border)
                    }
                    .foregroundStyle(ink)
                    .opacity(0.75)
            }
        }
    }
}

extension String {
    fileprivate func containsEmoji() -> Bool {
        unicodeScalars.contains { $0.properties.isEmoji && $0.properties.isEmojiPresentation }
    }
}
