@testable import AppBundle
import Common
import XCTest

/// What an `exec-and-forget` child actually receives.
///
/// The deprecation notice for `exec-on-workspace-change` -- and the guide, and the Sketchybar recipe
/// in goodies -- said to use `on-focused-workspace-changed` with `exec-and-forget` instead. That
/// replacement never received `AEROSPORK_FOCUSED_WORKSPACE`: `exec-and-forget` ignored the command's
/// environment altogether, so every documented variable arrived empty.
@MainActor
final class ExecEnvTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testTheChildIsToldWhichWindowTheCommandTargeted() {
        let env = execAndForgetProcess("true", CmdEnv(windowId: 42, workspaceName: nil, pwd: nil)).environment ?? [:]
        assertEquals(env["AEROSPORK_WINDOW_ID"], "42")
    }

    func testOnFocusedWorkspaceChangedSeesTheSwitchExactlyAsExecOnWorkspaceChangeDoes() {
        var cmdEnv = CmdEnv.defaultEnv
        cmdEnv.workspaceChange = (from: "1", to: "2")

        let env = execAndForgetProcess("true", cmdEnv).environment ?? [:]

        assertEquals(env["AEROSPORK_FOCUSED_WORKSPACE"], "2")
        assertEquals(env["AEROSPORK_PREV_WORKSPACE"], "1")
        assertEquals(env, workspaceChangeEnvVars(config.execConfig.envVariables, from: "1", to: "2"))
    }

    func testOnModeChangedSeesTheModeAndThePreviousOne() {
        let env = execAndForgetProcess("true", CmdEnv.defaultEnv.copy(\.modeChange, (from: "main", to: "resize"))).environment ?? [:]
        assertEquals(env["AEROSPORK_MODE"], "resize")
        assertEquals(env["AEROSPORK_PREV_MODE"], "main")
        assertNil(execAndForgetProcess("true", .defaultEnv).environment?["AEROSPORK_MODE"])
    }

    func testTheConfiguredEnvironmentStillReachesTheChild() {
        config.execConfig = ExecConfig(envVariables: ["PATH": "/opt/bin"])
        assertEquals(execAndForgetProcess("true", .defaultEnv).environment?["PATH"], "/opt/bin")
    }

    /// `checkOnFocusChangedCallbacks` spawns a whole session, which cannot run headlessly, so the one
    /// line that hands the switch to the right callback is checked in the source.
    func testOnlyOnFocusedWorkspaceChangedIsHandedTheSwitch() throws {
        let source = try String(contentsOf: projectRoot.appending(path: "Sources/AppBundle/focus.swift"), encoding: .utf8)
        let handOvers = withoutComments(source).split(separator: "\n").filter { $0.contains(".workspaceChange = ") }
        XCTAssertFalse(handOvers.isEmpty, "no callback is handed the workspace switch")
        for line in handOvers {
            XCTAssertTrue(line.contains("case .onFocusedWorkspaceChanged"), "a callback other than on-focused-workspace-changed gets the switch: \(line)")
        }
    }
}
