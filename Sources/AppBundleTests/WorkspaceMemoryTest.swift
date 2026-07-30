@testable import AppBundle
import Common
import Foundation
import XCTest

/// The whole risk surface of remembering window→workspace across a restart.
///
/// The design deliberately has no fuzzy matching: an exact `CGWindowID`, from this boot, whose app
/// still matches. So there are only three questions worth asking, and they are all about *refusing*
/// to restore. A wrong restore moves a window somewhere the user never put it and there is no way
/// for them to tell it apart from a correct one; a refusal just leaves today's behaviour.
@MainActor
final class WorkspaceMemoryTest: XCTestCase {
    private var stateUrl: URL { URL(filePath: "/tmp/\(aeroSporkAppId)-\(unixUserName).state.json") }

    override func setUp() { try? FileManager.default.removeItem(at: stateUrl) }
    override func tearDown() { try? FileManager.default.removeItem(at: stateUrl) }

    private func writeState(bootTime: Double, windows: [String: (workspace: String, bundleId: String?)]) {
        let entries = windows.mapValues { w in
            w.bundleId.map { ["workspace": w.workspace, "bundleId": $0] } ?? ["workspace": w.workspace]
        }
        let json: [String: Any] = ["bootTime": bootTime, "windows": entries]
        let data = try! JSONSerialization.data(withJSONObject: json)
        try! data.write(to: stateUrl)
    }

    private var currentBootTime: Double {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
        return Double(tv.tv_sec)
    }

    /// The case the guard exists for. `CGWindowID` is documented as unique only *within a user
    /// session*, so ids are recycled across boots -- and a recycled id matching a stale entry is the
    /// one way this design could produce a wrong answer instead of no answer.
    func testStateFromAPreviousBootRestoresNothing() {
        writeState(bootTime: currentBootTime - 10000, windows: ["42": ("A", "com.apple.finder")])
        WorkspaceMemory.load()

        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), nil)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: stateUrl.path),
            "a file from a previous boot describes ids that mean nothing now; it should be deleted, not kept",
        )
    }

    func testStateFromThisBootRestores() {
        writeState(bootTime: currentBootTime, windows: ["42": ("A", "com.apple.finder")])
        WorkspaceMemory.load()

        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), "A")
    }

    /// Only ids that are actually present are answered for. A window that has gone falls through to
    /// today's location-based binding.
    func testAnUnknownWindowIdIsNotAnswered() {
        writeState(bootTime: currentBootTime, windows: ["42": ("A", "com.apple.finder")])
        WorkspaceMemory.load()

        assertEquals(WorkspaceMemory.workspace(forWindowId: 99, bundleId: "com.apple.finder"), nil)
    }

    /// The residual risk the boot guard cannot remove: an id reused *within* one session by a
    /// different application. One comparison turns it into a no-op.
    func testAnIdNowOwnedByADifferentAppIsNotAnswered() {
        writeState(bootTime: currentBootTime, windows: ["42": ("A", "com.apple.finder")])
        WorkspaceMemory.load()

        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.googlecode.iterm2"), nil)
    }

    /// Unknown is not the same as equal. A window whose bundle id we cannot read must not match an
    /// entry, in either direction.
    func testAMissingBundleIdIsNeverAMatch() {
        writeState(bootTime: currentBootTime, windows: ["42": ("A", "com.apple.finder"), "43": ("B", nil)])
        WorkspaceMemory.load()

        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: nil), nil)
        assertEquals(WorkspaceMemory.workspace(forWindowId: 43, bundleId: "com.apple.finder"), nil)
        assertEquals(WorkspaceMemory.workspace(forWindowId: 43, bundleId: nil), nil)
    }

    /// No file, or an unreadable one, is simply "no memory" -- the state every first run is in.
    func testNoFileAndCorruptFileBothRestoreNothing() {
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), nil)

        try! Data("not json".utf8).write(to: stateUrl)
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), nil)
    }

    /// `load()` is called once at startup; a second call must not leave the previous run's entries
    /// answering, or a config reload would resurrect stale placement.
    func testLoadingAgainAfterTheFileIsGoneClearsWhatWasRestored() {
        writeState(bootTime: currentBootTime, windows: ["42": ("A", "com.apple.finder")])
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), "A")

        try? FileManager.default.removeItem(at: stateUrl)
        WorkspaceMemory.load()
        assertEquals(WorkspaceMemory.workspace(forWindowId: 42, bundleId: "com.apple.finder"), nil)
    }
}
