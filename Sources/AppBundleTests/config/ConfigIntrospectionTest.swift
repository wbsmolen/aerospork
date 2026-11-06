@testable import AppBundle
import Common
import XCTest

/// `config --get` used to expose only `mode.*`, so 18 of the 20 live top-level keys were
/// uninspectable at runtime — and the error read "No value at key token 'gaps'", which sounds like
/// the key does not exist rather than "introspection is not implemented". That made it impossible
/// to confirm a hot-reload had taken effect, or to debug why an assignment was not applying.
@MainActor
final class ConfigIntrospectionTest: XCTestCase {
    private func get(_ path: String) -> String? {
        switch buildConfigMap().find(keyPath: path.split(separator: ".").map(String.init)) {
            case .success(let value): return value.scalarDescription ?? "<non-scalar>"
            case .failure: return nil
        }
    }

    func testTopLevelScalarsAreInspectable() {
        for key in [
            "accordion-padding",
            "start-at-login",
            "automatically-unhide-macos-hidden-apps",
            "auto-move-workspaces-on-monitor-connect",
            "enable-normalization-flatten-containers",
            "enable-normalization-opposite-orientation-for-nested-containers",
            "default-root-container-layout",
            "default-root-container-orientation",
        ] {
            XCTAssertNotNil(get(key), "'\(key)' is not reachable via config --get")
        }
    }

    func testNestedAndCallbackKeysAreInspectable() {
        for key in ["gaps.inner.horizontal", "gaps.outer.top", "mode"] {
            XCTAssertNotNil(
                buildConfigMap().find(keyPath: key.split(separator: ".").map(String.init)).getOrNil(),
                "'\(key)' is not reachable",
            )
        }
        for key in ["after-startup-command", "on-focus-changed", "on-focused-workspace-changed", "on-focused-monitor-changed"] {
            XCTAssertNotNil(
                buildConfigMap().find(keyPath: [key]).getOrNil(),
                "callback '\(key)' is not reachable",
            )
        }
    }

    /// The default Swift `describe` dumps every nil field, which is worse than useless in a
    /// debugging command.
    func testFingerprintRendersOnlyWhatWasSpecified() {
        let description = MonitorDescription.fingerprint(MonitorFingerprintPatternData(
            vendorID: nil, modelID: nil, serialNumber: nil,
            displayNamePattern: "ACME Display 32 (1)",
            widthPixels: 3840, heightPixels: 2160,
            displayUUID: nil,
        ))
        let rendered = description.humanDescription
        assertEquals(rendered, "fingerprint(name 'ACME Display 32 (1)', 3840x2160)")
        XCTAssertFalse(rendered.contains("nil"), "nil fields leaked into output: \(rendered)")
    }

    func testSimpleMonitorDescriptionsRender() {
        assertEquals(MonitorDescription.main.humanDescription, "main")
        assertEquals(MonitorDescription.secondary.humanDescription, "secondary")
        assertEquals(MonitorDescription.sequenceNumber(2).humanDescription, "monitor #2")
    }
}
