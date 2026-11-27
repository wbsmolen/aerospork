@testable import AppBundle
import Common
import XCTest

@MainActor
final class ListWindowsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseCommand("list-windows --pid 1").errorOrNil, "Mandatory option is not specified (--focused|--all|--monitor|--workspace)")
        assertNil(parseCommand("list-windows --workspace M --pid 1").errorOrNil)
        assertEquals(parseCommand("list-windows --pid 1 --focused").errorOrNil, "--focused conflicts with other \"filtering\" flags")
        assertEquals(parseCommand("list-windows --pid 1 --all").errorOrNil, "--all conflicts with \"filtering\" flags. Please use '--monitor all' instead of '--all' alias")
        assertNil(parseCommand("list-windows --all").errorOrNil)
        assertEquals(parseCommand("list-windows --all --workspace M").errorOrNil, "ERROR: Conflicting options: --all, --workspace")
        assertEquals(parseCommand("list-windows --all --focused").errorOrNil, "ERROR: Conflicting options: --all, --focused")
        assertEquals(parseCommand("list-windows --all --count --format %{window-title}").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse").errorOrNil,
            "ERROR: Conflicting options: --all, --focused")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --focused, --workspace")
        assertEquals(
            parseCommand("list-windows --all --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --workspace")
        assertNil(parseCommand("list-windows --monitor mouse").errorOrNil)

        // --json
        assertEquals(parseCommand("list-windows --all --count --json").errorOrNil, "ERROR: Conflicting options: --count, --json")
        assertEquals(parseCommand("list-windows --all --format '%{right-padding}' --json").errorOrNil, "%{right-padding} interpolation variable is not allowed when --json is used")
        assertEquals(parseCommand("list-windows --all --format '%{window-title} |' --json").errorOrNil, "Only interpolation variables and spaces are allowed in \'--format\' when \'--json\' is used")
        assertNil(parseCommand("list-windows --all --format '%{window-title}' --json").errorOrNil)
    }

    func testInterpolationVariablesConsistency() {
        for kind in AeroObjKind.allCases {
            switch kind {
                case .window:
                    assertTrue(FormatVar.WindowFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "window-") })
                case .app:
                    assertTrue(FormatVar.AppFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "app-") })
                case .workspace:
                    assertTrue(FormatVar.WorkspaceFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "workspace") })
                case .monitor:
                    assertTrue(FormatVar.MonitorFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "monitor-") })
            }
        }
    }

    /// Values spelled the way the `layout` command takes them, and empty where they do not apply.
    func testLayoutFloatingAndOrientationVariables() throws {
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer // h tiles
        let tiled = TestWindow.new(id: 1, parent: root)
        let column = TilingContainer(parent: root, adaptiveWeight: 1, .v, .accordion, index: INDEX_BIND_LAST)
        let stacked = TestWindow.new(id: 2, parent: column)
        let floating = TestWindow.new(id: 3, parent: workspace)
        let minimized = TestWindow.new(id: 4, parent: macosMinimizedWindowsContainer)
        defer { _ = minimized.unbindFromParent() }
        let format: [StringInterToken] = [
            .interVar("window-layout"), .literal(","), .interVar("window-orientation"), .literal(","), .interVar("window-is-floating"),
        ]
        let objs = [tiled, stacked, floating, minimized].map { AeroObj.window(window: $0, title: "") }
        assertEquals(objs.format(format), .success([
            "tiles,horizontal,false",
            "accordion,vertical,false",
            "floating,,true",
            ",,false",
        ]))
        let json = try XCTUnwrap([objs[0]].formatToJson([.interVar("window-is-floating"), .interVar("window-layout")], ignoreRightPaddingVar: false).getOrNil())
        assertEquals(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: AnyHashable]], [["window-is-floating": false, "window-layout": "tiles"]])
    }

    func testFormat() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(window: TestWindow.new(id: 2, parent: $0), title: "non-empty"),
                AeroObj.window(window: TestWindow.new(id: 1, parent: $0), title: ""),
            ]
            assertEquals(windows.format([.interVar("window-title")]), .success(["non-empty", ""]))
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(window: TestWindow.new(id: 2, parent: $0), title: "non-empty"),
                AeroObj.window(window: TestWindow.new(id: 10, parent: $0), title: ""),
            ]
            assertEquals(windows.format([.interVar("window-id"), .interVar("right-padding"), .interVar("window-title")]), .success(["2 non-empty", "10"]))
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(window: TestWindow.new(id: 2, parent: $0), title: "title1"),
                AeroObj.window(window: TestWindow.new(id: 10, parent: $0), title: "title2"),
            ]
            assertEquals(windows.format([.interVar("window-id"), .interVar("right-padding"), .literal(" | "), .interVar("window-title")]), .success(["2  | title1", "10 | title2"]))
        }
    }

    func testAnUnknownWorkspaceListsNothingAndCreatesNone() async throws {
        let before = Workspace.all.map(\.name)
        let result = try await parseCommand("list-windows --workspace nope").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode, 0)
        assertEquals(result.stdout, [])
        assertEquals(Workspace.all.map(\.name), before)
    }

    /// A bad variable is reported before any title is read, in the words the formatter itself uses.
    func testABadFormatReadsNoTitle() async throws {
        let window = CountingWindow(id: 1, parent: Workspace.get(byName: "W").rootTilingContainer, title: "zsh")
        for json in [false, true] {
            let format: [StringInterToken] = [.interVar("window-title"), .interVar("nope"), .interVar("nada")]
            let result = try await parseCommand("list-windows --workspace W --format '%{window-title} %{nope} %{nada}'" + (json ? " --json" : ""))
                .cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode, 1)
            let objs = [AeroObj.window(window: window, title: "")]
            let expected = json
                ? objs.formatToJson(format, ignoreRightPaddingVar: false).failureOrNil
                : objs.format(format).failureOrNil
            assertEquals(result.stderr, [try XCTUnwrap(expected)])
        }
        assertEquals(window.reads, 0)
    }

    /// The titles are read concurrently. The window that answers first must not list first: with the same app
    /// and the same title, only the tree order tells them apart, and it must not change between two polls.
    func testSameTitledWindowsKeepTheirOrder() async throws {
        let root = Workspace.get(byName: "W").rootTilingContainer
        let slow = CountingWindow(id: 1, parent: root, title: "zsh", yields: 20)
        let fast = CountingWindow(id: 2, parent: root, title: "zsh")
        let app = TestApp.shared.name ?? ""
        for _ in 1 ... 20 {
            let result = try await parseCommand("list-windows --workspace W").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.stdout, ["1 | \(app) | zsh", "2 | \(app) | zsh"])
        }
        assertEquals(slow.reads, 20)
        assertEquals(fast.reads, 20)
    }
}

/// A window whose title read can be counted and delayed.
private final class CountingWindow: Window {
    private let fixedTitle: String
    private let yields: Int
    @MainActor var reads = 0

    @MainActor
    init(id: UInt32, parent: NonLeafTreeNodeObject, title: String, yields: Int = 0) {
        fixedTitle = title
        self.yields = yields
        super.init(id: id, TestApp.shared, lastFloatingSize: nil, parent: parent, adaptiveWeight: 1, index: INDEX_BIND_LAST)
    }

    @MainActor
    override var title: String {
        get async throws {
            reads += 1
            for _ in 0 ..< yields { await Task.yield() }
            return fixedTitle
        }
    }
}
