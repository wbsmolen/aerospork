import AppKit
import Common

struct ListWindowsCommand: Command {
    let args: ListWindowsCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let focus = focus
        var windows: [Window] = []

        if args.filteringOptions.focused {
            if let window = focus.windowOrNil {
                windows = [window]
            } else {
                return io.err(noWindowIsFocused)
            }
        } else {
            var workspaces: Set<Workspace> = args.filteringOptions.workspaces.isEmpty
                ? Workspace.all.toSet()
                : args.filteringOptions.workspaces
                    .flatMap { filter in
                        switch filter {
                            case .focused: [focus.workspace]
                            case .visible: Workspace.all.filter(\.isVisible)
                            // A query never creates a workspace: an unknown name lists nothing.
                            case .name(let name): Workspace.existing(byName: name.raw).map { [$0] } ?? []
                        }
                    }
                    .toSet()
            if !args.filteringOptions.monitors.isEmpty {
                let monitors: Set<CGPoint> = args.filteringOptions.monitors.resolveMonitors(io)
                if monitors.isEmpty { return false }
                workspaces = workspaces.filter { monitors.contains($0.workspaceMonitor.rect.topLeftCorner) }
            }
            windows = workspaces.flatMap(\.allLeafWindowsRecursive)
            if let pid = args.filteringOptions.pidFilter {
                windows = windows.filter { $0.app.pid == pid }
            }
            if let appId = args.filteringOptions.appIdFilter {
                windows = windows.filter { $0.app.bundleId == appId }
            }
        }

        if args.outputOnlyCount {
            return io.out("\(windows.count)")
        } else {
            let bound = windows.filter(\.isBound)
            // Before any AX read, so a bad variable costs no round trip to an app. Only when there is a
            // window to format: an empty list never reported one, and its output stays the same.
            if !bound.isEmpty, let error = validateFormat(args.format, for: .window, json: args.json) {
                return io.err(error)
            }
            let titles = try await fetchTitles(bound)
            // Rebuilt in the original order, not the order the reads finished: the sort below keys only on
            // app name and title, so same-titled windows (several terminals titled `zsh`) would swap places
            // between two polls.
            let windowList = bound
                .compactMap { window in window.isBound ? titles[window.windowId].map { (window: window, title: $0) } : nil }
                .sortedBy([{ (w: (window: Window, title: String)) -> String in w.window.app.name ?? "" }, \.title])

            return formatListOutput(
                windowList,
                countOnly: false, // already handled above
                json: args.json,
                format: args.format,
                ignoreRightPadding: args._format.isEmpty,
                mapper: { AeroObj.window(window: $0.window, title: $0.title) },
                io: io,
            )
        }
    }
}

/// The apps at once: each read is a round trip to the app's thread, and status bars poll this command.
@MainActor
private func fetchTitles(_ windows: [Window]) async throws -> [UInt32: String] {
    try await readEachAppInOrder(windows) { try await $0.title }
}
