import SwiftUI
import Common

struct GapsSettingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Window Gaps Configuration")
                .font(.headline)
                .padding(.bottom, 10)

            HStack(alignment: .top, spacing: 40) {
                // Left side - Settings
                VStack(alignment: .leading, spacing: 16) {
                    // Inner gaps
                    Section {
                        Text("Inner Gaps")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        HStack {
                            Text("Between windows:")
                            TextField("", value: Binding(
                                get: { viewModel.innerGaps },
                                set: {
                                    viewModel.innerGaps = max(0, $0)
                                    viewModel.markAsModified()
                                },
                            ), format: .number)
                                .frame(width: 60)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Text("pixels")
                        }
                    }

                    Divider()

                    // Outer gaps
                    Section {
                        Text("Outer Gaps")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Top:")
                                    .frame(width: 60, alignment: .trailing)
                                TextField("", value: Binding(
                                    get: { viewModel.outerGapsTop },
                                    set: {
                                        viewModel.outerGapsTop = max(0, $0)
                                        viewModel.markAsModified()
                                    },
                                ), format: .number)
                                    .frame(width: 60)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Text("pixels")
                            }

                            HStack {
                                Text("Bottom:")
                                    .frame(width: 60, alignment: .trailing)
                                TextField("", value: Binding(
                                    get: { viewModel.outerGapsBottom },
                                    set: {
                                        viewModel.outerGapsBottom = max(0, $0)
                                        viewModel.markAsModified()
                                    },
                                ), format: .number)
                                    .frame(width: 60)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Text("pixels")
                            }

                            HStack {
                                Text("Left:")
                                    .frame(width: 60, alignment: .trailing)
                                TextField("", value: Binding(
                                    get: { viewModel.outerGapsLeft },
                                    set: {
                                        viewModel.outerGapsLeft = max(0, $0)
                                        viewModel.markAsModified()
                                    },
                                ), format: .number)
                                    .frame(width: 60)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Text("pixels")
                            }

                            HStack {
                                Text("Right:")
                                    .frame(width: 60, alignment: .trailing)
                                TextField("", value: Binding(
                                    get: { viewModel.outerGapsRight },
                                    set: {
                                        viewModel.outerGapsRight = max(0, $0)
                                        viewModel.markAsModified()
                                    },
                                ), format: .number)
                                    .frame(width: 60)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                Text("pixels")
                            }
                        }
                    }
                }

                // Right side - Visual preview
                VStack {
                    Text("Preview")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    GapsPreview(
                        innerGaps: viewModel.innerGaps,
                        outerGapsTop: viewModel.outerGapsTop,
                        outerGapsBottom: viewModel.outerGapsBottom,
                        outerGapsLeft: viewModel.outerGapsLeft,
                        outerGapsRight: viewModel.outerGapsRight,
                    )
                    .frame(width: 250, height: 200)
                }
            }

            Spacer()

            Text("Note: Per-monitor gap settings can be configured in the config file")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct GapsPreview: View {
    let innerGaps: Int
    let outerGapsTop: Int
    let outerGapsBottom: Int
    let outerGapsLeft: Int
    let outerGapsRight: Int

    var body: some View {
        ZStack {
            // Monitor background
            Rectangle()
                .fill(Color(NSColor.controlBackgroundColor))
                .border(Color.secondary, width: 2)

            // Windows with gaps
            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let totalHeight = geometry.size.height

                // Calculate available space after outer gaps
                let availableWidth = totalWidth - CGFloat(outerGapsLeft + outerGapsRight)
                let availableHeight = totalHeight - CGFloat(outerGapsTop + outerGapsBottom)

                // Two windows side by side
                let windowWidth = (availableWidth - CGFloat(innerGaps)) / 2
                let windowHeight = availableHeight

                // Left window
                Rectangle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: max(0, windowWidth), height: max(0, windowHeight))
                    .position(
                        x: CGFloat(outerGapsLeft) + windowWidth / 2,
                        y: CGFloat(outerGapsTop) + windowHeight / 2,
                    )

                // Right window
                Rectangle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: max(0, windowWidth), height: max(0, windowHeight))
                    .position(
                        x: CGFloat(outerGapsLeft) + windowWidth + CGFloat(innerGaps) + windowWidth / 2,
                        y: CGFloat(outerGapsTop) + windowHeight / 2,
                    )

                // Gap indicators
                Group {
                    // Top gap
                    if outerGapsTop > 0 {
                        Path { path in
                            path.move(to: CGPoint(x: totalWidth / 2 - 20, y: 0))
                            path.addLine(to: CGPoint(x: totalWidth / 2 - 20, y: CGFloat(outerGapsTop)))
                            path.move(to: CGPoint(x: totalWidth / 2 - 25, y: 5))
                            path.addLine(to: CGPoint(x: totalWidth / 2 - 20, y: 0))
                            path.addLine(to: CGPoint(x: totalWidth / 2 - 15, y: 5))
                            path.move(to: CGPoint(x: totalWidth / 2 - 25, y: CGFloat(outerGapsTop) - 5))
                            path.addLine(to: CGPoint(x: totalWidth / 2 - 20, y: CGFloat(outerGapsTop)))
                            path.addLine(to: CGPoint(x: totalWidth / 2 - 15, y: CGFloat(outerGapsTop) - 5))
                        }
                        .stroke(Color.red, lineWidth: 1)

                        Text("\(outerGapsTop)")
                            .font(.caption2)
                            .foregroundColor(.red)
                            .position(x: totalWidth / 2, y: CGFloat(outerGapsTop) / 2)
                    }

                    // Inner gap
                    if innerGaps > 0 {
                        Path { path in
                            let y = totalHeight / 2
                            let x1 = CGFloat(outerGapsLeft) + windowWidth
                            let x2 = x1 + CGFloat(innerGaps)
                            path.move(to: CGPoint(x: x1, y: y))
                            path.addLine(to: CGPoint(x: x2, y: y))
                            path.move(to: CGPoint(x: x1 + 5, y: y - 5))
                            path.addLine(to: CGPoint(x: x1, y: y))
                            path.addLine(to: CGPoint(x: x1 + 5, y: y + 5))
                            path.move(to: CGPoint(x: x2 - 5, y: y - 5))
                            path.addLine(to: CGPoint(x: x2, y: y))
                            path.addLine(to: CGPoint(x: x2 - 5, y: y + 5))
                        }
                        .stroke(Color.orange, lineWidth: 1)

                        Text("\(innerGaps)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .position(x: CGFloat(outerGapsLeft) + windowWidth + CGFloat(innerGaps) / 2, y: totalHeight / 2 + 15)
                    }
                }
            }
        }
    }
}
