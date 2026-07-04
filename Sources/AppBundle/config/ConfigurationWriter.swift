import Common
import Foundation
import TOMLKit

/// Resolved path we write the user config to. Uses the existing user config if there is one,
/// otherwise the conventional dotfile in the home directory (which we create on first save).
@MainActor func userConfigTargetUrl() -> URL {
    findCustomConfigUrl().urlOrNil
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
}

/// The text we edit in place. The user config if present, else the shipped default config so a
/// first save produces a full, commented config seeded from the defaults.
@MainActor func configBaseText() -> String {
    let url = findCustomConfigUrl().urlOrNil ?? defaultConfigUrl
    return (try? String(contentsOf: url)) ?? ""
}

/// The one and only config writer.
///
/// It edits the existing config text line-by-line and only rewrites the keys the UI manages, so
/// user comments, key order, and any sections the UI doesn't understand survive untouched. It only
/// emits keys that the canonical `parseConfig` accepts.
@MainActor
enum ConfigurationWriter {
    static func write(from vm: ConfigurationViewModel) throws {
        let target = userConfigTargetUrl()
        let base = configBaseText()
        var lines = base.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // General settings (top-level scalars).
        setScalar(&lines, "start-at-login", bool(vm.startAtLogin))
        setScalar(&lines, "automatically-unhide-macos-hidden-apps", bool(vm.automaticallyUnhideMacosHiddenApps))
        setScalar(&lines, "auto-move-workspaces-on-monitor-connect", bool(vm.autoMoveWorkspacesOnMonitorConnect))
        setScalar(&lines, "enable-normalization-flatten-containers", bool(vm.enableNormalizationFlattenContainers))
        setScalar(&lines, "enable-normalization-opposite-orientation-for-nested-containers", bool(vm.enableNormalizationOppositeOrientation))
        setScalar(&lines, "default-root-container-layout", quoted(vm.defaultRootContainerLayout))
        setScalar(&lines, "default-root-container-orientation", quoted(vm.defaultRootContainerOrientation))
        setScalar(&lines, "accordion-padding", String(vm.accordionPadding))

        replaceGaps(&lines, vm)
        replaceAssignments(&lines, vm)
        applyBindingDiff(&lines, vm, base: base)

        let result = lines.joined(separator: "\n")

        // Best-effort backup before overwriting an existing config.
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(atPath: target.path + ".backup")
            try? FileManager.default.copyItem(atPath: target.path, toPath: target.path + ".backup")
        }
        try result.write(to: target, atomically: true, encoding: .utf8)
    }

    // MARK: - Scalars

    private static func setScalar(_ lines: inout [String], _ key: String, _ value: String) {
        let firstHeader = lines.firstIndex(where: isHeaderLine) ?? lines.count
        for i in 0 ..< firstHeader {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") { continue }
            if t.hasPrefix("\(key) ") || t.hasPrefix("\(key)="), t.contains("=") {
                lines[i] = "\(key) = \(value)"
                return
            }
        }
        lines.insert("\(key) = \(value)", at: firstHeader)
    }

    // MARK: - Gaps

    private static func replaceGaps(_ lines: inout [String], _ vm: ConfigurationViewModel) {
        removeSections(&lines) { $0 == "gaps" || $0.hasPrefix("gaps.") }
        insertAfterPreamble(&lines, [
            "",
            "[gaps]",
            "inner.horizontal = \(vm.innerGapsHorizontal)",
            "inner.vertical = \(vm.innerGapsVertical)",
            "outer.top = \(vm.outerGapsTop)",
            "outer.bottom = \(vm.outerGapsBottom)",
            "outer.left = \(vm.outerGapsLeft)",
            "outer.right = \(vm.outerGapsRight)",
        ])
    }

    // MARK: - Workspace to monitor assignments

    private static func replaceAssignments(_ lines: inout [String], _ vm: ConfigurationViewModel) {
        removeSections(&lines) { $0 == "workspace-to-monitor-force-assignment" }
        let rows = vm.assignments
            .filter { !$0.workspace.trimmingCharacters(in: .whitespaces).isEmpty }
            .filter { !$0.monitor.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rows.isEmpty else { return }
        var block = ["", "[workspace-to-monitor-force-assignment]"]
        for r in rows.sorted(by: { $0.workspace < $1.workspace }) {
            block.append("\(r.workspace.trimmingCharacters(in: .whitespaces)) = \(formatMonitorValue(r.monitor))")
        }
        lines.append(contentsOf: block)
    }

    private static func formatMonitorValue(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespaces)
        if UUID(uuidString: t) != nil { return "{ fingerprint = { uuid = '\(t)' } }" }
        if Int(t) != nil { return t }
        return quoted(t)
    }

    // MARK: - Key bindings (add / remove only)

    private static func applyBindingDiff(_ lines: inout [String], _ vm: ConfigurationViewModel, base: String) {
        var original: [String: Set<String>] = [:]
        if let table = try? TOMLTable(string: base), let modeTable = table["mode"]?.table {
            for (mode, val) in modeTable {
                guard let binding = val.table?["binding"]?.table else { continue }
                var keys = Set<String>()
                for (k, _) in binding { keys.insert(k) }
                original[mode] = keys
            }
        }
        for md in vm.modes {
            let desired = Set(md.bindings.map(\.key))
            let orig = original[md.mode] ?? []
            for key in orig.subtracting(desired) {
                removeBindingLine(&lines, mode: md.mode, key: key)
            }
            for row in md.bindings where !orig.contains(row.key) {
                addBindingLine(&lines, mode: md.mode, key: row.key, command: row.command)
            }
        }
    }

    private static func removeBindingLine(_ lines: inout [String], mode: String, key: String) {
        guard let h = headerIndex(lines, "mode.\(mode).binding") else { return }
        var i = h + 1
        while i < lines.count, !isHeaderLine(lines[i]) {
            if lineKey(lines[i]) == key {
                lines.remove(at: i)
                return
            }
            i += 1
        }
    }

    private static func addBindingLine(_ lines: inout [String], mode: String, key: String, command: String) {
        let line = "\(key) = \(formatCommand(command))"
        if let h = headerIndex(lines, "mode.\(mode).binding") {
            lines.insert(line, at: h + 1)
        } else {
            lines.append(contentsOf: ["", "[mode.\(mode).binding]", line])
        }
    }

    private static func formatCommand(_ command: String) -> String {
        let c = command.trimmingCharacters(in: .whitespaces)
        return c.contains("'") ? "\"\(c.replacingOccurrences(of: "\"", with: ""))\"" : "'\(c)'"
    }

    // MARK: - Line helpers

    private static func bool(_ v: Bool) -> String { v ? "true" : "false" }

    private static func quoted(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: ""))'"
    }

    private static func isHeaderLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
    }

    /// Name of a single-bracket table header (`[gaps]` -> "gaps"). Returns nil for array-of-table
    /// headers (`[[...]]`) and non-header lines, so those are never matched or split.
    private static func sectionHeaderName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("["), t.hasSuffix("]"), !t.hasPrefix("[[") else { return nil }
        return String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    private static func headerIndex(_ lines: [String], _ name: String) -> Int? {
        lines.firstIndex { sectionHeaderName($0) == name }
    }

    private static func lineKey(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("["), let eq = t.firstIndex(of: "=") else { return nil }
        var k = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
        if k.count >= 2, (k.hasPrefix("\"") && k.hasSuffix("\"")) || (k.hasPrefix("'") && k.hasSuffix("'")) {
            k = String(k.dropFirst().dropLast())
        }
        return k
    }

    /// Removes each matching single-bracket section: its header plus following lines up to (but not
    /// including) the next header line.
    private static func removeSections(_ lines: inout [String], where match: (String) -> Bool) {
        var result: [String] = []
        var i = 0
        while i < lines.count {
            if let name = sectionHeaderName(lines[i]), match(name) {
                i += 1
                while i < lines.count, !isHeaderLine(lines[i]) { i += 1 }
            } else {
                result.append(lines[i])
                i += 1
            }
        }
        lines = result
    }

    private static func insertAfterPreamble(_ lines: inout [String], _ block: [String]) {
        let idx = lines.firstIndex(where: isHeaderLine) ?? lines.count
        lines.insert(contentsOf: block, at: idx)
    }
}
