@testable import AppBundle
import Common
import XCTest

/// Guards DisplayLink support: DisplayLink panels report nil vendor/model/serial and are otherwise
/// indistinguishable, so aerospork pins workspaces to them by the stable per-display UUID
/// (CGDisplayCreateUUIDFromDisplayID). These tests exercise the pure `matches(patternData:)` logic
/// that backs `[workspace-to-monitor-force-assignment]` fingerprint resolution.
@MainActor
final class MonitorFingerprintTest: XCTestCase {
    // MARK: - UUID matching (the DisplayLink discriminator)

    func testUuidMatchesCaseInsensitively() {
        let fp = MonitorFingerprint(displayUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        assertTrue(fp.matches(patternData: pattern(uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230")))
        assertTrue(fp.matches(patternData: pattern(uuid: "37d8832a-2d66-02ca-b9f7-8f30a301b230")))
    }

    func testUuidMismatchDoesNotMatch() {
        let fp = MonitorFingerprint(displayUUID: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        assertFalse(fp.matches(patternData: pattern(uuid: "00000000-0000-0000-0000-000000000000")))
    }

    func testUuidPatternRequiresMonitorUuid() {
        // A monitor with no UUID must never match a UUID-specified pattern.
        let fp = MonitorFingerprint(displayName: "Some Display", displayUUID: nil)
        assertFalse(fp.matches(patternData: pattern(uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230")))
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

    // MARK: - Helper

    private func pattern(
        vendor: UInt32? = nil, model: UInt32? = nil, serial: String? = nil,
        name: String? = nil, width: Int? = nil, height: Int? = nil, uuid: String? = nil
    ) -> MonitorFingerprintPatternData {
        MonitorFingerprintPatternData(
            vendorID: vendor, modelID: model, serialNumber: serial,
            displayNamePattern: name, widthPixels: width, heightPixels: height, displayUUID: uuid,
        )
    }
}
