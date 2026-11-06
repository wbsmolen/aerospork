@testable import AppBundle
import AppKit
import Common
import XCTest

/// Guards DisplayLink support: DisplayLink panels report nil vendor/model/serial and are otherwise
/// indistinguishable, so AeroSpork pins workspaces to them by the stable per-display UUID
/// (CGDisplayCreateUUIDFromDisplayID). These tests exercise the pure `matches(patternData:)` logic
/// that backs `[workspace-to-monitor-force-assignment]` fingerprint resolution.
@MainActor
final class MonitorFingerprintTest: XCTestCase {
    // MARK: - UUID matching (the DisplayLink discriminator)

    func testUuidMatchesCaseInsensitively() {
        let fp = MonitorFingerprint(displayUUID: "BBBBBBBB-0000-4000-8000-000000000002")
        assertTrue(fp.matches(patternData: pattern(uuid: "BBBBBBBB-0000-4000-8000-000000000002")))
        assertTrue(fp.matches(patternData: pattern(uuid: "BBBBBBBB-0000-4000-8000-000000000002")))
    }

    func testUuidMismatchDoesNotMatch() {
        let fp = MonitorFingerprint(displayUUID: "BBBBBBBB-0000-4000-8000-000000000002")
        assertFalse(fp.matches(patternData: pattern(uuid: "00000000-0000-0000-0000-000000000000")))
    }

    func testUuidPatternRequiresMonitorUuid() {
        // A monitor with no UUID must never match a UUID-specified pattern.
        let fp = MonitorFingerprint(displayName: "Some Display", displayUUID: nil)
        assertFalse(fp.matches(patternData: pattern(uuid: "BBBBBBBB-0000-4000-8000-000000000002")))
    }

    /// The core DisplayLink case: two panels from the same dock report identical (nil) vendor/model/
    /// serial and the same name + resolution. Only the UUID tells them apart — each `uuid=` pattern
    /// must match exactly one panel, so two workspaces don't collapse onto the same monitor.
    func testTwoIdenticalDisplayLinkPanelsDisambiguatedByUuid() {
        let uuidA = "AAAAAAAA-0000-0000-0000-000000000001"
        let uuidB = "BBBBBBBB-0000-0000-0000-000000000002"
        let panelA = MonitorFingerprint(vendorID: nil, modelID: nil, serialNumber: nil,
                                        displayName: "DisplayLink Display", widthPixels: 1920, heightPixels: 1080, displayUUID: uuidA)
        let panelB = MonitorFingerprint(vendorID: nil, modelID: nil, serialNumber: nil,
                                        displayName: "DisplayLink Display", widthPixels: 1920, heightPixels: 1080, displayUUID: uuidB)

        assertTrue(panelA.matches(patternData: pattern(uuid: uuidA)))
        assertFalse(panelA.matches(patternData: pattern(uuid: uuidB)))
        assertTrue(panelB.matches(patternData: pattern(uuid: uuidB)))
        assertFalse(panelB.matches(patternData: pattern(uuid: uuidA)))

        // Name+resolution alone cannot disambiguate them (both match) — which is exactly why UUID exists.
        assertTrue(panelA.matches(patternData: pattern(name: "DisplayLink Display")))
        assertTrue(panelB.matches(patternData: pattern(name: "DisplayLink Display")))
    }

    // MARK: - Backward compatibility (the pre-UUID matching that already worked)

    /// `list-monitors --format '%{monitor-fingerprint}'` is documented as what to paste into `[monitors]`.
    func testAFingerprintPastesIntoTheConfig() {
        let fp = MonitorFingerprint(
            vendorID: 0x10AC, modelID: 0xD0C1, serialNumber: "AB1", displayName: "ACME \"32\"",
            widthPixels: 3840, heightPixels: 2160, displayUUID: "BBBBBBBB-0000-4000-8000-000000000002",
        )
        guard case .success(let parsed) = parseConfig("[monitors]\n1 = \(fp.description)\n"),
              case .fingerprint(let pattern)? = parsed.workspaceToMonitorForceAssignment["1"]?.first
        else {
            return XCTFail("not read back as a fingerprint: \(fp.description)")
        }
        assertTrue(fp.matches(patternData: pattern))
        assertEquals(pattern.vendorID, 0x10AC)
        assertEquals(pattern.heightPixels, 2160)
    }

    func testNameExactAndSubstringMatch() {
        let fp = MonitorFingerprint(displayName: "Built-in Retina Display")
        assertTrue(fp.matches(patternData: pattern(name: "Built-in Retina Display"))) // exact, case-insensitive
        assertTrue(fp.matches(patternData: pattern(name: "built-in retina display")))
        assertTrue(fp.matches(patternData: pattern(name: "Retina"))) // substring
        assertFalse(fp.matches(patternData: pattern(name: "External")))
    }

    func testVendorModelSerialMatch() {
        let fp = MonitorFingerprint(vendorID: 0x1234, modelID: 0x5678, serialNumber: "ABC123", displayName: "Dell")
        assertTrue(fp.matches(patternData: pattern(vendor: 0x1234, model: 0x5678, serial: "ABC123")))
        assertFalse(fp.matches(patternData: pattern(vendor: 0x9999)))
        assertFalse(fp.matches(patternData: pattern(serial: "WRONG")))
    }

    func testWidthHeightMatch() {
        let fp = MonitorFingerprint(displayName: "X", widthPixels: 3840, heightPixels: 2160)
        assertTrue(fp.matches(patternData: pattern(width: 3840, height: 2160)))
        assertFalse(fp.matches(patternData: pattern(width: 1920)))
    }

    func testEmptyPatternMatchesAnything() {
        // A pattern that constrains nothing matches every monitor (no fields to disqualify).
        assertTrue(MonitorFingerprint(displayName: "Anything").matches(patternData: pattern()))
    }

    // MARK: - fromScreen (the layer that was actually broken)

    /// Every built-in Apple panel exposes EDID. The old implementation read it by walking
    /// `IOServiceMatching("IODisplayConnect")`, a class that does not exist on Apple Silicon
    /// (`ioreg -c IODisplayConnect` returns nothing), so vendor/model/serial came back nil for every
    /// display and three of the fingerprint match keys could never match anything.
    func testBuiltInDisplayReportsEdidIdentity() throws {
        let screen = try builtInScreen()
        let fp = try XCTUnwrap(MonitorFingerprint.fromScreen(screen))
        assertNotNil(fp.vendorID)
        assertNotNil(fp.modelID)
        assertNotNil(fp.serialNumber)
        assertNotNil(fp.displayUUID)
    }

    /// `width`/`height` in a fingerprint must be readable from `%{monitor-width}`/`%{monitor-height}`.
    /// They used to be backing pixels, so on any Retina panel the two disagreed by the scale factor
    /// and a hand-written `width = <monitor-width>` silently never matched.
    func testFingerprintSizeUsesSameUnitAsMonitorWidth() throws {
        let screen = try builtInScreen()
        let fp = try XCTUnwrap(MonitorFingerprint.fromScreen(screen))
        assertEquals(fp.widthPixels, Int(screen.frame.width))
        assertEquals(fp.heightPixels, Int(screen.frame.height))
    }

    private func builtInScreen() throws -> NSScreen {
        // Headless CI has no display, and these assertions only mean something with real hardware.
        guard let screen = NSScreen.screens.first(where: { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } == true }) else {
            throw XCTSkip("No built-in display attached")
        }
        return screen
    }

    // MARK: - Helper

    private func pattern(
        vendor: UInt32? = nil, model: UInt32? = nil, serial: String? = nil,
        name: String? = nil, width: Int? = nil, height: Int? = nil, uuid: String? = nil,
    ) -> MonitorFingerprintPatternData {
        MonitorFingerprintPatternData(
            vendorID: vendor, modelID: model, serialNumber: serial,
            displayNamePattern: name, widthPixels: width, heightPixels: height, displayUUID: uuid,
        )
    }
}
