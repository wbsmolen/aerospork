import Common
import SwiftUI

struct GapsSettingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var innerLinked = false
    @State private var outerLinked = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // Six numbers with no picture is the worst kind of settings page: you change one,
                // tab away to look at a window, come back, change it again. The preview is driven
                // by the same values that are about to be written, so the loop closes here.
                Section {
                    GapsPreview(
                        innerHorizontal: viewModel.settings.gaps.innerHorizontal,
                        innerVertical: viewModel.settings.gaps.innerVertical,
                        outerTop: viewModel.settings.gaps.outerTop,
                        outerBottom: viewModel.settings.gaps.outerBottom,
                        outerLeft: viewModel.settings.gaps.outerLeft,
                        outerRight: viewModel.settings.gaps.outerRight,
                    )
                    .frame(height: 156)
                    .padding(.vertical, 4)
                    // Purely visual Shape view: without this VoiceOver finds nothing here at all.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Gaps preview")
                    .accessibilityValue(
                        "Inner gaps \(viewModel.settings.gaps.innerHorizontal) horizontal, \(viewModel.settings.gaps.innerVertical) vertical. "
                            + "Outer gaps \(viewModel.settings.gaps.outerTop) top, \(viewModel.settings.gaps.outerBottom) bottom, "
                            + "\(viewModel.settings.gaps.outerLeft) left, \(viewModel.settings.gaps.outerRight) right.",
                    )
                } header: {
                    SectionLabel("Preview", "eye")
                } footer: {
                    if viewModel.gapsHavePerMonitorOverrides {
                        StatusLabel(
                            "Some gaps have per-monitor rules in Raw TOML. Editing any value below replaces the whole section with flat numbers.",
                            kind: .neutral,
                        )
                    }
                }

                Section {
                    Toggle("Same value for both", isOn: Binding(
                        get: { innerLinked },
                        set: { linked in
                            innerLinked = linked
                            if linked { viewModel.setInnerGaps(viewModel.settings.gaps.innerHorizontal) }
                        },
                    ))
                    if innerLinked {
                        NumberField("Horizontal & vertical", value: Binding(
                            get: { viewModel.settings.gaps.innerHorizontal },
                            set: { viewModel.setInnerGaps($0) },
                        ))
                    } else {
                        NumberField("Horizontal", value: viewModel.binding(\.settings.gaps.innerHorizontal))
                        NumberField("Vertical", value: viewModel.binding(\.settings.gaps.innerVertical))
                    }
                } header: {
                    SectionLabel("Between windows", "rectangle.split.2x1")
                }

                Section {
                    Toggle("Same on all sides", isOn: Binding(
                        get: { outerLinked },
                        set: { linked in
                            outerLinked = linked
                            if linked { viewModel.setOuterGaps(viewModel.settings.gaps.outerTop) }
                        },
                    ))
                    if outerLinked {
                        NumberField("All sides", value: Binding(
                            get: { viewModel.settings.gaps.outerTop },
                            set: { viewModel.setOuterGaps($0) },
                        ))
                    } else {
                        NumberField("Top", value: viewModel.binding(\.settings.gaps.outerTop))
                        NumberField("Bottom", value: viewModel.binding(\.settings.gaps.outerBottom))
                        NumberField("Left", value: viewModel.binding(\.settings.gaps.outerLeft))
                        NumberField("Right", value: viewModel.binding(\.settings.gaps.outerRight))
                    }
                } header: {
                    SectionLabel("Around the screen", "rectangle.inset.filled")
                } footer: {
                    Text("The top gap is measured below the menu bar, so 0 is flush with the usable area.")
                }
            }
            .formStyle(.grouped)

            // Plain prose, no backticks: a markdown code span containing brackets makes SwiftUI's
            // parser fail and fall back to the literal string, backticks included.
            SettingsFooter(
                // Reworded so the config key fits in a code span. SwiftUI's markdown parser reads the
                // `[` of an array inside backticks as the start of a link, fails, and falls back to
                // the literal text -- backticks and all -- so the previous wording had to spell the
                // array out in body font, which is the face this window reserves for prose.
                "Per-monitor gaps, such as a list of values under `outer.top`, survive untouched until you change one of these — editing any gap rewrites the whole gaps section. Use Raw TOML for per-monitor rules.",
            )
        }
        .task(id: viewModel.loadGeneration) {
            guard viewModel.loadGeneration > 0 else { return }
            innerLinked = viewModel.settings.gaps.innerHorizontal == viewModel.settings.gaps.innerVertical
            outerLinked = viewModel.settings.gaps.outerTop == viewModel.settings.gaps.outerBottom
                && viewModel.settings.gaps.outerTop == viewModel.settings.gaps.outerLeft
                && viewModel.settings.gaps.outerTop == viewModel.settings.gaps.outerRight
        }
    }
}

/// A screen with three tiles in it. Deliberately schematic: it shows the *relationship* between the
/// six numbers, not a to-scale rendering of any particular display.
private struct GapsPreview: View {
    let innerHorizontal: Int
    let innerVertical: Int
    let outerTop: Int
    let outerBottom: Int
    let outerLeft: Int
    let outerRight: Int

    /// Nominal screen the preview stands in for; gaps are drawn at the same ratio to it that they
    /// would have on a real 1600pt-wide display.
    private let nominalWidth = CGFloat(1600)

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / nominalWidth
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1)

                HStack(spacing: CGFloat(innerHorizontal) * scale) {
                    tile
                    VStack(spacing: CGFloat(innerVertical) * scale) {
                        tile
                        tile
                    }
                }
                .padding(EdgeInsets(
                    top: CGFloat(outerTop) * scale,
                    leading: CGFloat(outerLeft) * scale,
                    bottom: CGFloat(outerBottom) * scale,
                    trailing: CGFloat(outerRight) * scale,
                ))
            }
        }
    }

    private var tile: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.accentColor.opacity(0.28))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
    }
}
