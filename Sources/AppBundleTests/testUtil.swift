@testable import AppBundle
import Common
import Foundation
import XCTest

/// Three levels above `Sources/AppBundleTests/testUtil.swift`. A walk up to `.git` never ended outside a
/// checkout (a source tarball), because `deleteLastPathComponent()` does not stop at "/".
let projectRoot: URL = {
    let url = URL(filePath: #filePath).absoluteURL
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    check(FileManager.default.fileExists(atPath: url.appending(component: "Package.swift").path))
    return url
}()

/// Points the URL-less config reads and writes at a new temp file holding `text` until `test` ends, so
/// a save can run for real. A save reloads the config, so the loaded config is put back afterwards.
@MainActor func useTemporaryConfig(_ text: String, for test: XCTestCase) throws -> URL {
    let dir = URL(filePath: NSTemporaryDirectory()).appending(path: "aerospork-config-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appending(path: "config.toml")
    try text.write(to: url, atomically: true, encoding: .utf8)
    let (savedConfig, savedUrl, savedFailure, savedWarnings) = (config, configUrl, configLoadFailure, configWarnings)
    testConfigOverride = url
    test.addTeardownBlock { @MainActor in
        testConfigOverride = nil
        (config, configUrl, configLoadFailure, configWarnings) = (savedConfig, savedUrl, savedFailure, savedWarnings)
        try? FileManager.default.removeItem(at: dir)
    }
    return url
}

/// The whole declaration that `declaration` starts, for tests that pin wiring which needs a real
/// `MacApp` and so cannot be driven headlessly. Line comments are stripped, or a comment explaining a
/// fix would satisfy or trip the assertion.
func sourceBody(_ declaration: String, in relativePath: String) throws -> String {
    let source = try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    return try XCTUnwrap(
        declarationBody(declaration, in: source),
        "\(declaration) was renamed, or no line closes it at its indentation; re-point this test rather than deleting it",
    )
}

/// From the line holding `declaration` through the first later line that is that line's indentation
/// followed by `}`, or nil when either is missing. swiftformat enforces the indentation, so a brace in
/// a string or a comment cannot end the body early. A fixed character window was cut short by some
/// bodies and ran into the next declaration for others.
func declarationBody(_ declaration: String, in source: String) -> String? {
    guard let start = source.range(of: declaration) else { return nil }
    let lines = source[source.lineRange(for: start).lowerBound...].split(separator: "\n", omittingEmptySubsequences: false)
    let close = lines[0].prefix { $0 == " " } + "}"
    guard let end = lines.firstIndex(where: { $0 == close }) else { return nil }
    return withoutComments(lines[...end].joined(separator: "\n"))
}

/// The `.swift` files under `relativePath`. Fails when there are none, or a moved directory would
/// leave every check over it passing with nothing to check.
func sourceFiles(in relativePath: String) throws -> [URL] {
    let dir = projectRoot.appending(path: relativePath)
    let files = (FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
        .filter { $0.pathExtension == "swift" }
    _ = try XCTUnwrap(files.first, "no Swift files under \(relativePath)")
    return files
}

func withoutComments(_ text: some StringProtocol) -> String {
    text.split(separator: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
}

@MainActor
func setUpWorkspacesForTests() {
    config = defaultConfig
    configUrl = defaultConfigUrl
    config.enableNormalizationFlattenContainers = false // Make layout tests more predictable
    config.enableNormalizationOppositeOrientationForNestedContainers = false // Make layout tests more predictable
    config.defaultRootContainerOrientation = .horizontal // Make default layout predictable

    // Don't create any bindings and workspaces for tests
    config.modes = [mainModeId: Mode(bindings: [:])]
    config.preservedWorkspaceNames = []
    config.persistentWorkspaces = [] // the bundled default declares 1-9, which would otherwise always exist

    for workspace in Workspace.all {
        for child in workspace.children {
            child.unbindFromParent()
        }
    }
    check(Workspace.get(byName: "setUpWorkspacesForTests").focusWorkspace())
    resetWorkspaceScreensForTests() // or `getStubWorkspace` hands out what an earlier test showed
    gcMonitors() // a multi-monitor test leaves its workspaces visible on monitors that are gone by now
    Workspace.garbageCollectUnusedWorkspaces()
    check(focus.workspace.isEffectivelyEmpty)
    check(focus.workspace === Workspace.all.singleOrNil(), Workspace.all.map(\.description).joined(separator: ", "))
    check(mainMonitor.setActiveWorkspace(focus.workspace))

    TestApp.shared.focusedWindow = nil
    TestApp.shared.windows = []
}

extension ParsedCmd {
    var errorOrNil: String? {
        if case .failure(let e) = self {
            return e
        } else {
            return nil
        }
    }

    var cmdOrDie: T { cmdOrNil ?? dieT() }

    var isHelp: Bool {
        if case .help = self {
            return true
        } else {
            return false
        }
    }
}

func testParseCommandFail(_ command: String, msg expected: String) {
    let parsed = parseCommand(command)
    switch parsed {
        case .cmd(let command): XCTFail("\(command) isn't supposed to be parcelable")
        case .failure(let msg): assertEquals(msg, expected)
        case .help: die()
    }
}

extension WorkspaceCmdArgs {
    init(target: WorkspaceTarget, autoBackAndForth: Bool? = nil, wrapAround: Bool? = nil) {
        self = WorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(target)
        self._autoBackAndForth = autoBackAndForth
        self._wrapAround = wrapAround
    }
}

extension MoveNodeToWorkspaceCmdArgs {
    init(target: WorkspaceTarget, wrapAround: Bool? = nil) {
        self = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(target)
        self._wrapAround = wrapAround
    }

    init(workspace: String) {
        self = MoveNodeToWorkspaceCmdArgs(rawArgs: [])
        self.target = .initialized(.direct(.parse(workspace).getOrDie()))
    }
}

extension HotkeyBinding {
    init(_ modifiers: NSEvent.ModifierFlags, _ keyCode: Key, _ commands: [any Command]) {
        let descriptionWithKeyNotation = modifiers.isEmpty
            ? keyCode.rawValue
            : modifiers.toString() + "-" + keyCode.rawValue
        self.init(modifiers, keyCode, commands, descriptionWithKeyNotation: descriptionWithKeyNotation)
    }
}
