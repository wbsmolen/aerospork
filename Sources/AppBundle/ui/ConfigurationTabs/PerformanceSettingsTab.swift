import SwiftUI
import Common

struct PerformanceSettingsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Performance Configuration")
                    .font(.headline)
                    .padding(.bottom, 10)

                Text("Fine-tune j4's performance for your system")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Preset selector
                presetSection

                Divider()

                // Layout Calculation section
                layoutCalculationSection

                Divider()

                // Debouncing section
                debouncingSection

                Divider()

                // Monitoring section (collapsible)
                monitoringSection

                Spacer()
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Preset Section

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Presets")
                .font(.subheadline)
                .fontWeight(.semibold)

            Text("Quick configuration for common scenarios")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("High Performance") {
                    viewModel.applyPerformancePreset(.highPerformance)
                }
                .buttonStyle(.borderedProminent)
                .help("Optimized for speed - uses more memory")

                Button("Balanced") {
                    viewModel.applyPerformancePreset(.balanced)
                }
                .buttonStyle(.bordered)
                .help("Default settings - good balance")

                Button("Memory Efficient") {
                    viewModel.applyPerformancePreset(.memoryEfficient)
                }
                .buttonStyle(.bordered)
                .help("Optimized for low memory usage")

                Button("Debug") {
                    viewModel.applyPerformancePreset(.debug)
                }
                .buttonStyle(.bordered)
                .help("Enable all monitoring for troubleshooting")
            }
        }
    }

    // MARK: - Layout Calculation Section

    private var layoutCalculationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Layout Calculation")
                .font(.subheadline)
                .fontWeight(.semibold)

            Toggle("Use background layout calculation", isOn: Binding(
                get: { viewModel.useBackgroundLayoutCalculation },
                set: {
                    viewModel.useBackgroundLayoutCalculation = $0
                    viewModel.markAsModified()
                }
            ))
            .help("Calculate layouts asynchronously for workspaces with many windows")

            HStack {
                Text("Background layout threshold:")
                    .frame(width: 200, alignment: .trailing)
                TextField("", value: Binding(
                    get: { viewModel.backgroundLayoutThreshold },
                    set: {
                        viewModel.backgroundLayoutThreshold = max(1, min(100, $0))
                        viewModel.markAsModified()
                    }
                ), format: .number)
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("windows")
                    .foregroundColor(.secondary)
            }
            .disabled(!viewModel.useBackgroundLayoutCalculation)

            Text("Layouts calculated in background when workspace has this many windows or more")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            Divider().padding(.vertical, 8)

            Toggle("Use layout memoization", isOn: Binding(
                get: { viewModel.useLayoutMemoization },
                set: {
                    viewModel.useLayoutMemoization = $0
                    viewModel.markAsModified()
                }
            ))
            .help("Cache layout calculations to avoid redundant work")

            HStack {
                Text("Layout cache size:")
                    .frame(width: 200, alignment: .trailing)
                TextField("", value: Binding(
                    get: { viewModel.layoutCacheSize },
                    set: {
                        viewModel.layoutCacheSize = max(10, min(1000, $0))
                        viewModel.markAsModified()
                    }
                ), format: .number)
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("entries")
                    .foregroundColor(.secondary)
            }
            .disabled(!viewModel.useLayoutMemoization)

            HStack {
                Text("Cache timeout:")
                    .frame(width: 200, alignment: .trailing)
                TextField("", value: Binding(
                    get: { viewModel.layoutCacheTimeout },
                    set: {
                        viewModel.layoutCacheTimeout = max(1, min(300, $0))
                        viewModel.markAsModified()
                    }
                ), format: .number)
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("seconds")
                    .foregroundColor(.secondary)
            }
            .disabled(!viewModel.useLayoutMemoization)
        }
    }

    // MARK: - Debouncing Section

    private var debouncingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debouncing")
                .font(.subheadline)
                .fontWeight(.semibold)

            Toggle("Use adaptive debouncing", isOn: Binding(
                get: { viewModel.useAdaptiveDebouncing },
                set: {
                    viewModel.useAdaptiveDebouncing = $0
                    viewModel.markAsModified()
                }
            ))
            .help("Automatically adjust debounce delays based on system load and operation frequency")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Base delay:")
                        .frame(width: 200, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { viewModel.debounceBaseDelay },
                        set: {
                            viewModel.debounceBaseDelay = max(1, min(1000, $0))
                            viewModel.markAsModified()
                        }
                    ), format: .number)
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("ms")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Minimum delay:")
                        .frame(width: 200, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { viewModel.debounceMinDelay },
                        set: {
                            viewModel.debounceMinDelay = max(1, min(1000, $0))
                            viewModel.markAsModified()
                        }
                    ), format: .number)
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("ms")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Maximum delay:")
                        .frame(width: 200, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { viewModel.debounceMaxDelay },
                        set: {
                            viewModel.debounceMaxDelay = max(1, min(2000, $0))
                            viewModel.markAsModified()
                        }
                    ), format: .number)
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("ms")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("CPU load factor:")
                        .frame(width: 200, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { viewModel.debounceCpuLoadFactor },
                        set: {
                            viewModel.debounceCpuLoadFactor = max(0.5, min(5.0, $0))
                            viewModel.markAsModified()
                        }
                    ), format: .number)
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("(0.5 - 5.0)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .disabled(!viewModel.useAdaptiveDebouncing)

                HStack {
                    Text("Frequency factor:")
                        .frame(width: 200, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { viewModel.debounceFrequencyFactor },
                        set: {
                            viewModel.debounceFrequencyFactor = max(0.5, min(5.0, $0))
                            viewModel.markAsModified()
                        }
                    ), format: .number)
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("(0.5 - 5.0)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .disabled(!viewModel.useAdaptiveDebouncing)
            }

            Text("Debouncing delays window refresh operations to reduce CPU usage during rapid changes")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)
        }
    }

    // MARK: - Monitoring Section

    @State private var monitoringExpanded = false

    private var monitoringSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Performance Monitoring")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { monitoringExpanded.toggle() }) {
                    Image(systemName: monitoringExpanded ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(.plain)
            }

            if monitoringExpanded {
                Text("Advanced monitoring and debugging options")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Enable performance metrics", isOn: Binding(
                    get: { viewModel.enablePerformanceMetrics },
                    set: {
                        viewModel.enablePerformanceMetrics = $0
                        viewModel.markAsModified()
                    }
                ))
                .help("Collect performance metrics for analysis")

                Toggle("Enable debug logging", isOn: Binding(
                    get: { viewModel.enablePerformanceDebugLogging },
                    set: {
                        viewModel.enablePerformanceDebugLogging = $0
                        viewModel.markAsModified()
                    }
                ))
                .help("Log detailed performance information (increases log file size)")

                HStack {
                    Text("Metrics interval:")
                        .frame(width: 200, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { viewModel.metricsInterval },
                        set: {
                            viewModel.metricsInterval = max(1, min(600, $0))
                            viewModel.markAsModified()
                        }
                    ), format: .number)
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("seconds")
                        .foregroundColor(.secondary)
                }
                .disabled(!viewModel.enablePerformanceMetrics)

                HStack {
                    Text("Max samples retained:")
                        .frame(width: 200, alignment: .trailing)
                    TextField("", value: Binding(
                        get: { viewModel.maxPerformanceSamples },
                        set: {
                            viewModel.maxPerformanceSamples = max(10, min(10000, $0))
                            viewModel.markAsModified()
                        }
                    ), format: .number)
                        .frame(width: 60)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Text("samples")
                        .foregroundColor(.secondary)
                }
                .disabled(!viewModel.enablePerformanceMetrics)
            }
        }
    }
}
