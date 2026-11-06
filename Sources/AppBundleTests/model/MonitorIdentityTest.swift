@testable import AppBundle
import AppKit
import Common
import XCTest

/// Covers monitor *identity* one layer above `MonitorFingerprint.matches`: resolving a
/// `MonitorDescription` against the live monitor list, and the reconnect signature that decides
/// whether workspaces get rebalanced. Both used to be untestable — resolution downcast to
/// `LazyMonitor`, which no mocked monitor can ever be — so both were silently broken.
@MainActor
final class MonitorIdentityTest: XCTestCase {
    override func tearDown() async throws {
        testMonitors = [defaultTestMonitor]
        config.workspaceToMonitorForceAssignment = [:]
        // Hand back exactly the state `setUpWorkspacesForTests` assumes. The workspace-to-screen map
        // is keyed by screen POINT and nothing in setUp clears it, so a workspace left visible on a
        // fake second monitor stays "visible" -- and the next test's setUp cannot displace it,
        // because `setFocus` early-returns when the frozen focus already names its target.
        gcMonitors() // rebuild the map for the restored single-monitor world
        _ = mainMonitor.setActiveWorkspace(focus.workspace)
        Workspace.garbageCollectUnusedWorkspaces()
        try await super.tearDown()
    }

    // MARK: - Fingerprint resolution against real monitors

    /// The headline DisplayLink case: two panels with identical name/size/(nil) EDID, side by side.
    /// Each `uuid =` pattern must resolve to its own panel, or two workspaces collapse onto one screen.
    func testFingerprintResolvesTwoIdenticalPanelsByUuid() {
        let uuidLeft = "AAAAAAAA-0000-0000-0000-000000000001"
        let uuidRight = "BBBBBBBB-0000-0000-0000-000000000002"
        testMonitors = [
            panel(id: 1, x: 0, uuid: uuidLeft),
            panel(id: 2, x: 1920, uuid: uuidRight),
        ]

        assertEquals(resolve(.fingerprint(pattern(uuid: uuidLeft)))?.rect.topLeftX, 0)
        assertEquals(resolve(.fingerprint(pattern(uuid: uuidRight)))?.rect.topLeftX, 1920)
        // Name alone cannot pick a side — it matches the first sorted monitor for both workspaces.
        assertEquals(resolve(.fingerprint(pattern(name: "DisplayLink Display")))?.rect.topLeftX, 0)
    }

    func testFingerprintResolvesByVendorModelSerial() {
        testMonitors = [
            panel(id: 1, x: 0, uuid: "AAAAAAAA-0000-0000-0000-000000000001",
                  vendor: 0x10AC, model: 0x4276, serial: "100000001"),
            panel(id: 2, x: 1920, uuid: "BBBBBBBB-0000-0000-0000-000000000002",
                  vendor: 0x10AC, model: 0x4270, serial: "100000002"),
        ]

        // Same vendor, different EDID model/serial: the two-identical-panels docking case. The
        // serials are invented -- a real display serial is personal hardware data, and the test
        // only cares that the values differ.
        assertEquals(resolve(.fingerprint(pattern(vendor: 0x10AC, model: 0x4270)))?.rect.topLeftX, 1920)
        assertEquals(resolve(.fingerprint(pattern(serial: "100000001")))?.rect.topLeftX, 0)
        assertNil(resolve(.fingerprint(pattern(serial: "NOPE"))))
    }

    func testFingerprintDoesNotResolveWhenNothingMatches() {
        testMonitors = [panel(id: 1, x: 0, uuid: "AAAAAAAA-0000-0000-0000-000000000001")]
        assertNil(resolve(.fingerprint(pattern(uuid: "CCCCCCCC-0000-0000-0000-000000000003"))))
    }

    // MARK: - The other MonitorDescription cases, now exercisable with >1 monitor

    func testSequenceNumberResolvesInSortedOrder() {
        testMonitors = [
            panel(id: 1, x: 1920, uuid: "BBBBBBBB-0000-0000-0000-000000000002"),
            panel(id: 2, x: 0, uuid: "AAAAAAAA-0000-0000-0000-000000000001"),
        ]
        // Sequence numbers follow left-to-right geometry, not NSScreen enumeration order.
        assertEquals(resolve(.sequenceNumber(1))?.rect.topLeftX, 0)
        assertEquals(resolve(.sequenceNumber(2))?.rect.topLeftX, 1920)
        assertNil(resolve(.sequenceNumber(3)))
    }

    func testPatternResolvesByName() {
        testMonitors = [
            panel(id: 1, x: 0, uuid: "AAAAAAAA-0000-0000-0000-000000000001", name: "Built-in Retina Display"),
            panel(id: 2, x: 1920, uuid: "BBBBBBBB-0000-0000-0000-000000000002", name: "ACME Display 32"),
        ]
        assertEquals(resolve(MonitorDescription.pattern("Display 32")!)?.rect.topLeftX, 1920)
        assertNil(resolve(MonitorDescription.pattern("Nonexistent")!))
    }

    func testMainAndSecondaryResolution() {
        testMonitors = [
            panel(id: 1, x: 1920, uuid: "BBBBBBBB-0000-0000-0000-000000000002"),
            panel(id: 2, x: 0, uuid: "AAAAAAAA-0000-0000-0000-000000000001"),
        ]
        // `main` is the monitor at the origin regardless of enumeration order.
        assertEquals(resolve(.main)?.rect.topLeftX, 0)
        assertEquals(resolve(.secondary)?.rect.topLeftX, 1920)
    }

    func testSecondaryIsUndefinedWithoutExactlyTwoMonitors() {
        testMonitors = [
            panel(id: 1, x: 0, uuid: "AAAAAAAA-0000-0000-0000-000000000001"),
            panel(id: 2, x: 1920, uuid: "BBBBBBBB-0000-0000-0000-000000000002"),
            panel(id: 3, x: 3840, uuid: "CCCCCCCC-0000-0000-0000-000000000003"),
        ]
        assertNil(resolve(.secondary))
    }

    // MARK: - Reconnect signature (drives the rebalance decision)

    /// A DisplayLink flap can swap which physical panel lands on which rect while `localizedName`
    /// and geometry stay byte-identical. The signature must still change, or no rebalance happens
    /// and workspaces sit on the wrong screens — the exact failure this feature exists to prevent.
    func testSignatureChangesWhenIdenticalPanelsSwapPlaces() {
        let uuidA = "AAAAAAAA-0000-0000-0000-000000000001"
        let uuidB = "BBBBBBBB-0000-0000-0000-000000000002"

        testMonitors = [panel(id: 1, x: 0, uuid: uuidA), panel(id: 2, x: 1920, uuid: uuidB)]
        let before = GlobalObserver.monitorSetSignature()

        // Same names, same rects, panels swapped.
        testMonitors = [panel(id: 1, x: 0, uuid: uuidB), panel(id: 2, x: 1920, uuid: uuidA)]
        assertNotEquals(GlobalObserver.monitorSetSignature(), before)
    }

    func testSignatureIsStableWhenNothingChanged() {
        let panels = [
            panel(id: 1, x: 0, uuid: "AAAAAAAA-0000-0000-0000-000000000001"),
            panel(id: 2, x: 1920, uuid: "BBBBBBBB-0000-0000-0000-000000000002"),
        ]
        testMonitors = panels
        let first = GlobalObserver.monitorSetSignature()
        // Re-enumerated in a different order (NSScreen.screens is not order-stable).
        testMonitors = panels.reversed()
        assertEquals(GlobalObserver.monitorSetSignature(), first)
    }

    // MARK: - Acting on the assignment

    /// `autoMoveWorkspacesToAssignedMonitors` -- what `auto-move-workspaces-on-monitor-connect`
    /// runs on startup and after a monitor reconfiguration -- did nothing at all.
    ///
    /// Its "is it already on its assigned monitor?" test compared `workspace.workspaceMonitor`
    /// against `workspace.forceAssignedMonitor`, and `workspaceMonitor` *answers*
    /// `forceAssignedMonitor` first. So the comparison was the assignment against itself: true for
    /// every workspace whose assignment resolves, and the remaining `guard let ... else { continue }`
    /// caught every workspace whose assignment does not. Every path bailed.
    ///
    /// The scenario below is the real one: workspaces are already placed (config loaded, or panels
    /// reconnected in the other order), and only then does the assignment apply.
    func testAutoMoveActuallyMovesAWorkspaceToItsAssignedMonitor() {
        setUpWorkspacesForTests()
        let uuidRight = "BBBBBBBB-0000-0000-0000-000000000002"
        testMonitors = [
            panel(id: 1, x: 0, uuid: "AAAAAAAA-0000-0000-0000-000000000001"),
            panel(id: 2, x: 1920, uuid: uuidRight),
        ]
        let left = sortedMonitors[0]
        let right = sortedMonitors[1]

        // Placed on the wrong screens first -- while no assignment exists, so nothing rejects it.
        check(left.setActiveWorkspace(Workspace.get(byName: "belongs-right")))
        check(right.setActiveWorkspace(Workspace.get(byName: "belongs-anywhere")))
        config.workspaceToMonitorForceAssignment = ["belongs-right": [.fingerprint(pattern(uuid: uuidRight))]]

        autoMoveWorkspacesToAssignedMonitors()

        assertEquals(right.activeWorkspace.name, "belongs-right")
        // ...and the monitor it vacated is not left showing nothing.
        assertEquals(left.activeWorkspace.name, "belongs-anywhere")
    }

    /// The counter-check: a workspace already on its assigned monitor must not be shuffled, or
    /// every monitor reconfiguration would churn the screens for no reason.
    func testAutoMoveLeavesAnAlreadyCorrectlyPlacedWorkspaceAlone() {
        setUpWorkspacesForTests()
        let uuidRight = "BBBBBBBB-0000-0000-0000-000000000002"
        testMonitors = [
            panel(id: 1, x: 0, uuid: "AAAAAAAA-0000-0000-0000-000000000001"),
            panel(id: 2, x: 1920, uuid: uuidRight),
        ]
        let left = sortedMonitors[0]
        let right = sortedMonitors[1]
        config.workspaceToMonitorForceAssignment = ["belongs-right": [.fingerprint(pattern(uuid: uuidRight))]]
        check(right.setActiveWorkspace(Workspace.get(byName: "belongs-right")))
        check(left.setActiveWorkspace(Workspace.get(byName: "belongs-anywhere")))

        autoMoveWorkspacesToAssignedMonitors()

        assertEquals(right.activeWorkspace.name, "belongs-right")
        assertEquals(left.activeWorkspace.name, "belongs-anywhere")
    }

    // MARK: - Helpers

    private func resolve(_ description: MonitorDescription) -> Monitor? {
        description.resolveMonitor(sortedMonitors: sortedMonitors)
    }

    private func panel(
        id: Int, x: CGFloat, uuid: String, name: String = "DisplayLink Display",
        vendor: UInt32? = nil, model: UInt32? = nil, serial: String? = nil,
    ) -> MonitorImpl {
        let rect = Rect(topLeftX: x, topLeftY: 0, width: 1920, height: 1080)
        return MonitorImpl(
            monitorAppKitNsScreenScreensId: id,
            name: name,
            rect: rect,
            visibleRect: rect,
            fingerprint: MonitorFingerprint(
                vendorID: vendor, modelID: model, serialNumber: serial,
                displayName: name, widthPixels: 1920, heightPixels: 1080, displayUUID: uuid,
            ),
        )
    }

    private func pattern(
        vendor: UInt32? = nil, model: UInt32? = nil, serial: String? = nil,
        name: String? = nil, uuid: String? = nil,
    ) -> MonitorFingerprintPatternData {
        MonitorFingerprintPatternData(
            vendorID: vendor, modelID: model, serialNumber: serial,
            displayNamePattern: name, displayUUID: uuid,
        )
    }
}

/// Which old screen each monitor continues, when the arrangement changes.
final class MatchMonitorsTest: XCTestCase {
    private let left = CGPoint(x: 0, y: 0)
    private let right = CGPoint(x: 1000, y: 0)

    /// Two panels trade places: the workspace follows the panel, not the position.
    func testAPanelIsFollowedByItsUuidAcrossAPositionSwap() {
        let mapping = matchMonitors(
            new: [(point: left, uuid: "R"), (point: right, uuid: "L")],
            oldPoints: [left, right],
            oldUuids: [left: "L", right: "R"],
        )
        assertEquals(mapping[left], right)
        assertEquals(mapping[right], left)
    }

    /// Nearest-first in monitor order let the first monitor take the second's exact match.
    func testAnExactPositionIsNotStolenByANearbyMonitor() {
        let mapping = matchMonitors(
            new: [(point: CGPoint(x: 900, y: 0), uuid: nil), (point: right, uuid: nil)],
            oldPoints: [right, left],
            oldUuids: [:],
        )
        assertEquals(mapping[right], right)
        assertEquals(mapping[CGPoint(x: 900, y: 0)], left)
    }

    func testAMonitorWithNoCounterpartIsLeftOut() {
        let mapping = matchMonitors(new: [(point: left, uuid: nil), (point: right, uuid: nil)], oldPoints: [left], oldUuids: [:])
        assertEquals(mapping[left], left)
        assertNil(mapping[right])
    }

    func testANameDoesNotOverrideTheSizeInAFingerprint() {
        let panel = MonitorFingerprint(vendorID: nil, modelID: nil, serialNumber: nil, displayName: "ACME 32", widthPixels: 3840, heightPixels: 2160, displayUUID: nil)
        let wide = MonitorFingerprintPatternData(displayNamePattern: "ACME", widthPixels: 5120)
        let same = MonitorFingerprintPatternData(displayNamePattern: "ACME", widthPixels: 3840)
        XCTAssertFalse(panel.matches(patternData: wide))
        XCTAssertTrue(panel.matches(patternData: same))
    }
}
