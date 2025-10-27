import Common

extension MonitorDescription {
    func resolveMonitor(sortedMonitors: [Monitor]) -> Monitor? {
        return switch self {
            case .sequenceNumber(let number): sortedMonitors.getOrNil(atIndex: number - 1)
            case .main: mainMonitor
            case .pattern(_, let regex): sortedMonitors.first { monitor in monitor.name.contains(regex.val) }
            case .secondary:
                sortedMonitors.takeIf { $0.count == 2 }?
                    .first { $0.rect.topLeftCorner != mainMonitor.rect.topLeftCorner }
            case .fingerprint(let patternData):
                sortedMonitors.first { monitor in
                    guard let fingerprint = (monitor as? LazyMonitor)?.fingerprint else {
                        print("[DEBUG] Monitor '\(monitor.name)' has no fingerprint data")
                        return false
                    }
                    let matches = fingerprint.matches(patternData: patternData)
                    print("[DEBUG] Comparing monitor '\(monitor.name)' fingerprint with pattern:")
                    print("[DEBUG]   Monitor: \(fingerprint.description)")
                    print("[DEBUG]   Pattern: vendor=\(patternData.vendorID?.description ?? "nil"), model=\(patternData.modelID?.description ?? "nil"), display=\(patternData.displayNamePattern ?? "nil"), res=\(patternData.widthPixels?.description ?? "nil")x\(patternData.heightPixels?.description ?? "nil")")
                    print("[DEBUG]   Matches: \(matches)")
                    return matches
                }
        }
    }
}
