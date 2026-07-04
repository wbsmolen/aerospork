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
                // UUID makes fingerprints unique, so first-match is unambiguous even for
                // identical DisplayLink panels.
                sortedMonitors.first { monitor in
                    (monitor as? LazyMonitor)?.fingerprint?.matches(patternData: patternData) ?? false
                }
        }
    }
}
