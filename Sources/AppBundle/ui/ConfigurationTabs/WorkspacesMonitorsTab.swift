import AppKit
import Common
import SwiftUI

struct WorkspacesMonitorsTab: View {
    @ObservedObject var viewModel: ConfigurationViewModel
    @State private var selection: ConfigurationViewModel.WorkspaceAssignmentRow.ID?
    /// Keyed on `uuid ?? name`, not the per-load minted `MonitorRow.id`: DisplayLink docks flap on
    /// connect, `liveMonitors` refreshes, and an id-keyed selection would silently drop mid-flow.
    @State private var selectedMonitorToken: String?
    @FocusState private var focusedWorkspaceField: ConfigurationViewModel.WorkspaceAssignmentRow.ID?

    private var selectedMonitor: ConfigurationViewModel.MonitorRow? {
        guard let selectedMonitorToken else { return nil }
        return viewModel.liveMonitors.first { ($0.uuid ?? $0.name) == selectedMonitorToken }
    }

    var body: some View {
        VStack(spacing: 0) {
            monitors
            Divider()
            assignments
            ListActionBar(
                addHelp: "Pin a workspace to a monitor",
                removeHelp: "Remove the selected assignment",
                onAdd: {
                    let id = viewModel.addAssignment()
                    selection = id
                    focusedWorkspaceField = id
                },
                onRemove: selection == nil ? nil : {
                    if let id = selection { viewModel.removeAssignment(id: id) }
                    viewModel.scheduleAutoSave()
                    selection = nil
                },
                hint: "Hardware fingerprints already in your config are preserved — they show up here under the monitor's name. A workspace named here stays available even with no windows on it.",
            )
        }
        .onAppear { autoSelectIfNeeded() }
        // The monitor list loads async after the pane appears, so onAppear alone always sees it
        // empty; re-check when it lands (and when a hotplug changes it).
        .onChange(of: viewModel.liveMonitors.count) { _ in autoSelectIfNeeded() }
    }

    /// Auto-select the main (or only) monitor: the pin menu is reachable in zero clicks on a
    /// laptop, and visible selection is what teaches that the schematic is clickable.
    private func autoSelectIfNeeded() {
        guard selectedMonitorToken == nil,
              let main = viewModel.liveMonitors.first(where: \.isMain) ?? viewModel.liveMonitors.first
        else { return }
        selectedMonitorToken = main.uuid ?? main.name
    }

    // MARK: - Connected monitors

    private var monitors: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader("Connected monitors", "display.2")

            if viewModel.liveMonitors.isEmpty {
                SettingsHint("No monitors reported yet — they appear as soon as macOS reports one, and their UUIDs are what pins a workspace to a physical panel.")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else {
                MonitorArrangementView(
                    monitors: viewModel.liveMonitors,
                    selectedToken: selectedMonitorToken,
                    onSelect: { token in
                        selectedMonitorToken = selectedMonitorToken == token ? nil : token
                        announceSelection()
                    },
                )
                .frame(height: 130)
                .padding(.horizontal, 16)

                detailStrip
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
    }

    @ViewBuilder private var detailStrip: some View {
        if let monitor = selectedMonitor {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "display")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(monitor.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(monitor.resolution)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)

                    if let uuid = monitor.uuid {
                        // Under width pressure the UUID prefix goes first: the copy button is the
                        // part of it that does something.
                        ViewThatFits {
                            HStack(spacing: 4) {
                                Text(String(uuid.prefix(8)) + "…")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("UUID begins \(uuid.prefix(8))")
                                uuidCopyButton(uuid)
                            }
                            uuidCopyButton(uuid)
                        }
                    }

                    Spacer(minLength: 12)
                    pinMenu(monitor)
                }
                chipLine(monitor)
            }
            .frame(minHeight: 44, alignment: .topLeading)
        } else {
            SettingsHint("Select a monitor above to see and change what's pinned to it.")
                .frame(minHeight: 44, alignment: .topLeading)
        }
    }

    private func uuidCopyButton(_ uuid: String) -> some View {
        CopyButton(
            value: uuid,
            help: "Copy monitor UUID\n\(uuid)\nA DisplayLink monitor reports no vendor or serial, so its UUID is the only thing that pins a workspace to that exact panel.",
        )
        .settingsHitTarget()
    }

    private func chipLine(_ monitor: ConfigurationViewModel.MonitorRow) -> some View {
        let pinned = viewModel.assignments(pinnedTo: monitor)
        let visible = pinned.prefix(8)
        return HStack(spacing: 6) {
            if pinned.isEmpty {
                Text("No workspaces pinned here yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Pinned here:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(Array(visible)) { assignment in
                    WorkspaceChip(
                        name: assignment.workspace.isEmpty ? "(unnamed)" : assignment.workspace,
                        help: "Select the assignment for “\(assignment.workspace)” in the table below",
                        action: { selection = assignment.id },
                    )
                    .contextMenu {
                        Button("Unpin from this monitor", role: .destructive) {
                            viewModel.removeAssignment(id: assignment.id)
                            viewModel.scheduleAutoSave()
                        }
                    }
                }
                if pinned.count > visible.count {
                    // A fixed chip budget keeps the strip's height deterministic; the tail stays
                    // one click away instead of wrapping the card taller.
                    Menu("+\(pinned.count - visible.count) more") {
                        ForEach(pinned.dropFirst(visible.count)) { assignment in
                            Button(assignment.workspace.isEmpty ? "(unnamed)" : assignment.workspace) {
                                selection = assignment.id
                            }
                        }
                    }
                    .fixedSize()
                }
            }
        }
    }

    private func pinMenu(_ monitor: ConfigurationViewModel.MonitorRow) -> some View {
        let token = monitor.uuid ?? monitor.name
        let unpinned = viewModel.unpinnedDefinedWorkspaces
        let movable = viewModel.settings.assignments.filter {
            !$0.workspace.isEmpty && viewModel.monitorRow(forToken: $0.monitor)?.id != monitor.id
        }
        return Menu("Pin a workspace here") {
            ForEach(unpinned, id: \.self) { name in
                Button(name) {
                    selection = viewModel.setAssignment(workspace: name, monitorToken: token)
                }
            }
            if !movable.isEmpty {
                if !unpinned.isEmpty { Divider() }
                Section("Pinned elsewhere — move here") {
                    ForEach(movable) { assignment in
                        Button(assignment.workspace) {
                            selection = viewModel.setAssignment(workspace: assignment.workspace, monitorToken: token)
                        }
                    }
                }
            }
            Divider()
            Button("Other…") {
                let id = viewModel.addAssignment(monitorToken: token)
                selection = id
                focusedWorkspaceField = id
                settingsAnnounce("Empty assignment added — type a workspace name")
            }
        }
        .menuStyle(.button)
        .fixedSize()
        .help("Pins to this display; the assignments table can change how it matches.")
    }

    private func announceSelection() {
        guard let monitor = selectedMonitor else { return }
        let pinned = viewModel.assignments(pinnedTo: monitor)
            .map { $0.workspace.isEmpty ? "unnamed" : $0.workspace }
        let detail = pinned.isEmpty
            ? "No workspaces pinned here yet."
            : "Workspaces pinned: \(pinned.joined(separator: ", "))."
        settingsAnnounce("\(monitor.name) selected. \(detail)")
    }

    // MARK: - Workspace assignments

    @ViewBuilder
    private var assignments: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader("Workspace assignments", "arrow.triangle.branch")

            if viewModel.settings.assignments.isEmpty {
                ContentUnavailableViewCompat(
                    icon: "arrow.triangle.branch",
                    title: "No assignments",
                    message: "Workspaces land wherever they were last used. Add an assignment to pin one to a specific monitor.",
                    actionTitle: "Add assignment",
                    action: { viewModel.addAssignment() },
                )
            } else {
                let knownMonitorTokens = knownTokens
                Table(viewModel.settings.assignments, selection: $selection) {
                    // Neither of the two data columns has anywhere for a click to land: both are
                    // filled edge to edge by a control that claims the mouseDown before the Table's
                    // own row-selection handler ever sees it. This column carries no control, so a
                    // click here reaches the Table the same way it does on WindowRulesTab's
                    // plain-Text cells, which have never had this problem. It's decorative, not a
                    // separate affordance, so VoiceOver skips it and lets the Table's native row
                    // accessibility (which already knows the row's real content) speak instead.
                    // Not `line.3.horizontal`: that glyph reads as a drag-to-reorder handle, and
                    // this row can't be reordered.
                    TableColumn("") { row in
                        Image(systemName: "circle")
                            .font(.system(size: 6))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .width(20)

                    TableColumn("Workspace") { row in
                        // Workspace names are a word; an edge-to-edge field reads as a form for
                        // prose. Capped, the slack goes to the monitor column instead.
                        SettingsField("Workspace name", prompt: "web", text: binding(row.id, \.workspace))
                            .focused($focusedWorkspaceField, equals: row.id)
                            .frame(maxWidth: 180, alignment: .leading)
                    }
                    .width(min: 110, ideal: 140, max: 200)

                    TableColumn("Monitor") { row in
                        HStack(spacing: 6) {
                            // A Table column header is not a control label, so without this the
                            // picker is announced as an unnamed pop-up button.
                            //
                            // One monitor, one option: the position number ties each entry to the
                            // schematic above, and the token is uuid-when-available, same as the
                            // pin menu. Main/non-main/position/regex tokens already in the config
                            // stay selectable as the row's own preserved entry below the divider —
                            // nothing loaded is lost, but the menu never manufactures fourteen
                            // ways to say four monitors.
                            Picker("Monitor for workspace \(row.workspace)", selection: binding(row.id, \.monitor)) {
                                ForEach(viewModel.liveMonitors) { m in
                                    Text("\(m.position) · \(m.name)").tag(m.uuid ?? m.name)
                                }
                                let current = row.monitor
                                if !current.isEmpty, !knownMonitorTokens.contains(current) {
                                    Divider()
                                    Text(legacyTokenLabel(current)).tag(current)
                                }
                            }
                            .labelsHidden()
                            // Hug the selected label; a pop-up stretched across the column reads
                            // as a text field and leaves nowhere for a row click to land.
                            .fixedSize()
                            if row.isComplex {
                                Badge(
                                    "complex",
                                    help: "Written with more detail than this editor can show — use Raw TOML to change its fallback list or hardware fingerprint.",
                                )
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .tableStyle(.inset)
                // Kept alongside the handle column above, not replaced by it: this is the path for
                // a row already selected by some other means (VoiceOver rotor, a future keyboard-only
                // flow) to still be deletable without a mouse.
                .onDeleteCommand {
                    if let id = selection {
                        viewModel.removeAssignment(id: id)
                        viewModel.scheduleAutoSave()
                        selection = nil
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The tokens the picker's per-monitor entries write.
    private var knownTokens: Set<String> {
        Set(viewModel.liveMonitors.map { $0.uuid ?? $0.name })
    }

    /// A readable label for a token some earlier config (or Raw TOML) wrote — the picker keeps it
    /// selectable but does not offer its kind for new picks.
    private func legacyTokenLabel(_ token: String) -> String {
        switch token {
            case "main": "Main display"
            case "secondary": "Non-main display"
            default: Int(token).map { "Position \($0)" } ?? token
        }
    }

    private func binding(
        _ id: ConfigurationViewModel.WorkspaceAssignmentRow.ID,
        _ keyPath: WritableKeyPath<ConfigurationViewModel.WorkspaceAssignmentRow, String>,
    ) -> Binding<String> {
        Binding(
            get: { viewModel.settings.assignments.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let i = viewModel.settings.assignments.firstIndex(where: { $0.id == id }) else { return }
                viewModel.settings.assignments[i][keyPath: keyPath] = newValue
                viewModel.scheduleAutoSave()
            },
        )
    }
}

/// A true-to-arrangement schematic, and the pane's monitor selector. Relative origins and sizes
/// come from AppKit, then scale into the available width as one group; this makes "Position 1" and
/// the main display visually concrete without pretending the cards are pixel-perfect previews.
struct MonitorArrangementView: View {
    let monitors: [ConfigurationViewModel.MonitorRow]
    /// `uuid ?? name` of the selected monitor; stable across `liveMonitors` refreshes.
    var selectedToken: String? = nil
    var onSelect: ((String) -> Void)? = nil

    private var bounds: CGRect {
        monitors.reduce(CGRect.null) { $0.union($1.rect) }
    }

    var body: some View {
        GeometryReader { geometry in
            let inset: CGFloat = 12
            let safeBounds = bounds.isNull || bounds.width <= 0 || bounds.height <= 0
                ? CGRect(x: 0, y: 0, width: 1, height: 1)
                : bounds
            let scale = min(
                (geometry.size.width - inset * 2) / safeBounds.width,
                (geometry.size.height - inset * 2) / safeBounds.height,
            )
            // One axis always has slack (the aspect ratios rarely match); split it so the
            // arrangement sits centered rather than pinned to the top-left corner.
            let xOffset = (geometry.size.width - safeBounds.width * scale) / 2
            let yOffset = (geometry.size.height - safeBounds.height * scale) / 2

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)

                ForEach(monitors) { monitor in
                    MonitorBox(
                        monitor: monitor,
                        isSelected: selectedToken != nil && (monitor.uuid ?? monitor.name) == selectedToken,
                        width: max(1, monitor.rect.width * scale),
                        height: max(1, monitor.rect.height * scale),
                        onSelect: onSelect.map { select in { select(monitor.uuid ?? monitor.name) } },
                    )
                    .position(
                        x: xOffset + (monitor.rect.midX - safeBounds.minX) * scale,
                        y: yOffset + (monitor.rect.midY - safeBounds.minY) * scale,
                    )
                    // The linear monitor enumeration a screen reader used to get from the deleted
                    // list; ZStack order is positional, not left-to-right.
                    .accessibilitySortPriority(Double(-monitor.position))
                }
            }
        }
    }
}

private struct MonitorBox: View {
    let monitor: ConfigurationViewModel.MonitorRow
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    let onSelect: (() -> Void)?
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: { onSelect?() }) {
            // A real arrangement scales some panels down to a sliver (an ultrawide above two 4Ks),
            // and `.frame` does not clip: a full three-line label drawn into a 20pt box spills over
            // every neighbour. Degrade the label to what fits, and clip so nothing can escape.
            ViewThatFits {
                VStack(spacing: 2) {
                    positionRow
                    nameText
                    Text(monitor.resolution)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.72))
                        .lineLimit(1)
                }
                VStack(spacing: 2) {
                    positionRow
                    nameText
                }
                positionRow
            }
            .padding(4)
            .frame(width: width, height: height)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor)),
            )
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                        ? Color.accentColor.opacity(0.14)
                        : isHovered ? Color.primary.opacity(0.05) : Color.clear),
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1,
                    )
            }
            // The menu-bar strip along the top edge is the "main" cue that survives panels too
            // small for any text; accent is reserved for selection.
            .overlay(alignment: .top) {
                if monitor.isMain {
                    // Not a Capsule: that shape is reserved for Badge by the chrome rules, and at
                    // 3pt tall a rounded rect is the same pixels anyway.
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: max(10, width * 0.4), height: 3)
                        .padding(.top, 2)
                }
            }
            // Focus ring drawn outside the selection ring in the system focus color, so
            // keyboard focus and selection stay two visibly different things.
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .padding(-4)
                }
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityLabel("Position \(monitor.position), \(monitor.name), \(monitor.resolution)\(monitor.isMain ? ", main display" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var positionRow: some View {
        HStack(spacing: 4) {
            Text("\(monitor.position)")
                .font(.system(.caption2, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary.opacity(0.72))
            if monitor.isMain {
                Text("main")
                    .font(.caption2)
                    .foregroundStyle(.primary.opacity(0.72))
            }
        }
    }

    private var nameText: some View {
        Text(monitor.name)
            .font(.caption2)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
