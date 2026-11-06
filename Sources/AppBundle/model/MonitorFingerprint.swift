import AppKit
import IOKit
import Common

struct MonitorFingerprint: Equatable, Hashable, Codable {
    let vendorID: UInt32?
    let modelID: UInt32?
    let serialNumber: String?
    let displayName: String?
    /// Size in **points**, deliberately the same unit as `%{monitor-width}`/`%{monitor-height}` and
    /// `Monitor.rect`. These used to hold backing pixels, so a user could read `1512` from
    /// `monitor-width`, write `width = 1512` into a fingerprint, and silently never match a
    /// fingerprint that said `3024`. The property name is kept to mirror
    /// `MonitorFingerprintPatternData.widthPixels` (public config-facing key `width`).
    let widthPixels: Int?
    let heightPixels: Int?
    /// Stable per-display UUID from CGDisplayCreateUUIDFromDisplayID. Populated even for
    /// DisplayLink panels, which leave vendor/model/serial nil and are otherwise indistinguishable.
    let displayUUID: String?

    init(
        vendorID: UInt32? = nil,
        modelID: UInt32? = nil,
        serialNumber: String? = nil,
        displayName: String? = nil,
        widthPixels: Int? = nil,
        heightPixels: Int? = nil,
        displayUUID: String? = nil,
    ) {
        self.vendorID = vendorID
        self.modelID = modelID
        self.serialNumber = serialNumber
        self.displayName = displayName
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.displayUUID = displayUUID
    }

    static func fromScreen(_ screen: NSScreen) -> MonitorFingerprint? {
        guard let displayID = screen.displayID else { return nil }

        // EDID identity comes from CoreGraphics, not IOKit. The previous implementation walked
        // IOServiceMatching("IODisplayConnect"), a class that does not exist on Apple Silicon
        // (`ioreg -c IODisplayConnect` is empty), so the iterator never yielded anything and
        // vendor/model/serial were nil for *every* display — silently disabling three of the
        // fingerprint match keys. These CG accessors read the same EDID fields, are not
        // deprecated, and work on both architectures.
        let vendorID = realEdidValue(CGDisplayVendorNumber(displayID), unknown: UInt32(kDisplayVendorIDUnknown))
        let modelID = realEdidValue(CGDisplayModelNumber(displayID), unknown: UInt32(kDisplayProductIDGeneric))
        // A DisplayLink / EDID-less panel reports 0 here. Keep it nil rather than "0" so a
        // `serial = "0"` pattern can't collapse every such panel onto one workspace.
        let serialNumber = realEdidValue(CGDisplaySerialNumber(displayID), unknown: 0).map(String.init)

        let displayName = screen.localizedName
        let widthPixels = Int(screen.frame.width)
        let heightPixels = Int(screen.frame.height)

        var displayUUID: String? = nil
        if let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() {
            displayUUID = CFUUIDCreateString(nil, cfUUID) as String?
        }

        return MonitorFingerprint(
            vendorID: vendorID,
            modelID: modelID,
            serialNumber: serialNumber,
            displayName: displayName,
            widthPixels: widthPixels,
            heightPixels: heightPixels,
            displayUUID: displayUUID,
        )
    }

    func matches(patternData: MonitorFingerprintPatternData) -> Bool {
        // UUID is the strongest discriminator: DisplayLink panels share vendor/model/serial
        // (all nil) yet each has a stable CGDisplayCreateUUIDFromDisplayID UUID. Check it first.
        if let patternUUID = patternData.displayUUID {
            guard let displayUUID else { return false }
            return displayUUID.caseInsensitiveCompare(patternUUID) == .orderedSame
        }
        if let patternVendorID = patternData.vendorID, vendorID != patternVendorID {
            return false
        }
        if let patternModelID = patternData.modelID, modelID != patternModelID {
            return false
        }
        if let patternSerial = patternData.serialNumber, serialNumber != patternSerial {
            return false
        }
        if let patternWidth = patternData.widthPixels, widthPixels != patternWidth {
            return false
        }
        if let patternHeight = patternData.heightPixels, heightPixels != patternHeight {
            return false
        }
        if let patternDisplayName = patternData.displayNamePattern {
            guard let displayName else {
                return false
            }
            // First try exact match (case insensitive)
            if displayName.localizedCaseInsensitiveCompare(patternDisplayName) == .orderedSame {
                return true
            }
            // Then try substring contains
            return displayName.localizedCaseInsensitiveContains(patternDisplayName)
        }
        return true
    }

    var description: String {
        var parts: [String] = []
        if let vendorID {
            parts.append("vendor:\(String(format: "0x%04X", vendorID))")
        }
        if let modelID {
            parts.append("model:\(String(format: "0x%04X", modelID))")
        }
        if let serialNumber, !serialNumber.isEmpty {
            parts.append("serial:\(serialNumber)")
        }
        if let displayName {
            parts.append("name:\(displayName)")
        }
        if let widthPixels, let heightPixels {
            parts.append("resolution:\(widthPixels)x\(heightPixels)")
        }
        if let displayUUID {
            parts.append("uuid:\(displayUUID)")
        }
        return parts.joined(separator: " ")
    }
}

/// CoreGraphics substitutes a per-field sentinel when the display exposes no usable EDID (DisplayLink
/// and other virtual panels), and 0xFFFFFFFF for an invalid display ID. Map both to nil so two
/// EDID-less panels never look like the same identified monitor.
private func realEdidValue(_ value: UInt32, unknown: UInt32) -> UInt32? {
    value != unknown && value != UInt32.max ? value : nil
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let displayID = self.deviceDescription[key] as? NSNumber else { return nil }
        return displayID.uint32Value
    }
}
