import AppKit
import Common
import Foundation
import os

let signposter = OSSignposter(subsystem: aeroSporkAppId, category: .pointsOfInterest)

let lockScreenAppBundleId = "com.apple.loginwindow"
// The `exec-and-forget` env var names live next to their only consumer, in `command/CmdEnv.swift`.
// The upstream-branded aliases that used to be exported alongside them are gone, matching what
// `workspaceChangeEnvVars` already did: a script reading the old names now sees an empty variable.

func interceptTermination(_ _signal: Int32) {
    signal(_signal, { signal in
        check(Thread.current.isMainThread)
        Task {
            // `exit` runs either way -- a signal handler that declines to exit is worse than one
            // whose cleanup failed -- but the failure is reported rather than discarded.
            defer { exit(signal) }
            do { try await terminationHandler.beforeTermination() } catch {
                printStderr("Termination handler threw while handling signal \(signal): \(error)")
            }
        }
    } as sig_t)
}

@MainActor
func initTerminationHandler() {
    terminationHandler = AppServerTerminationHandler()
}

private struct AppServerTerminationHandler: TerminationHandler {
    func beforeTermination() async throws {
        // BEFORE the cleanup, which moves every window -- and frozen, so the refresh those moves
        // trigger cannot overwrite this snapshot with the dumped positions.
        WorkspaceMemory.freezeAndSave()
        try await makeAllWindowsVisibleAndRestoreSize()
        if isDebug {
            sendCommandToReleaseServer(args: ["enable", "on"])
        }
    }
}

/// Top-left corner for a window centred on `monitorVisibleRect`, in the GLOBAL coordinate space.
///
/// The monitor's own origin is the whole point. `visibleRect` is global -- `Rect.monitorFrameNormalized`
/// keeps `minX` as `topLeftX` -- and `kAXPositionAttribute` is global too. Centring with only the
/// monitor's width and height, as this did, lands every window near the origin of that space, which
/// is the main monitor, whatever monitor the window was actually on.
///
/// On one display the two are identical, which is why it survived: the bug is invisible until there
/// is a second monitor with a non-zero origin. On a multi-monitor setup it collapsed every display
/// onto one at quit, and since the next launch binds a window by where it physically sits, everything
/// came back on the main monitor's startup workspace.
func centredOnMonitor(_ monitorVisibleRect: Rect, _ windowSize: CGSize) -> CGPoint {
    monitorVisibleRect.topLeftCorner + CGPoint(
        x: (monitorVisibleRect.width - windowSize.width) / 2,
        y: (monitorVisibleRect.height - windowSize.height) / 2,
    )
}

@MainActor
private func makeAllWindowsVisibleAndRestoreSize() async throws {
    // Make all windows fullscreen before Quit
    for (_, window) in MacWindow.allWindowsMap {
        // makeAllWindowsVisibleAndRestoreSize may be invoked when something went wrong (e.g. some windows are unbound)
        // that's why it's not allowed to use `.parent` call in here
        let monitor = try await window.getCenter()?.monitorApproximation ?? mainMonitor
        let monitorVisibleRect = monitor.visibleRect
        let windowSize = window.lastFloatingSize ?? CGSize(width: monitorVisibleRect.width, height: monitorVisibleRect.height)
        try await window.setAxFrameBlocking(centredOnMonitor(monitorVisibleRect, windowSize), windowSize)
    }
}

@MainActor
func terminateApp() -> Never {
    NSApplication.shared.terminate(nil)
    die("Unreachable code")
}

func - (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x - b.x, y: a.y - b.y)
}

func + (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x + b.x, y: a.y + b.y)
}

extension CGPoint: ConvenienceCopyable {}

extension CGPoint {
    /// Distance to ``Rect`` outline frame
    func distanceToRectFrame(to rect: Rect) -> CGFloat {
        let list: [CGFloat] = (rect.minY.until(excl: rect.maxY)?.contains(y) == true ? [abs(rect.minX - x), abs(rect.maxX - x)] : []) +
            (rect.minX.until(excl: rect.maxX)?.contains(x) == true ? [abs(rect.minY - y), abs(rect.maxY - y)] : []) +
            [
                distance(to: rect.topLeftCorner),
                distance(to: rect.bottomRightCorner),
                distance(to: rect.topRightCorner),
                distance(to: rect.bottomLeftCorner),
            ]
        return list.minOrDie()
    }

    func coerceIn(rect: Rect) -> CGPoint? {
        guard let xRange = rect.minX.until(incl: rect.maxX - 1) else { return nil }
        guard let yRange = rect.minY.until(incl: rect.maxY - 1) else { return nil }
        return CGPoint(x: x.coerceIn(xRange), y: y.coerceIn(yRange))
    }

    func addingXOffset(_ offset: CGFloat) -> CGPoint { CGPoint(x: x + offset, y: y) }
    func addingYOffset(_ offset: CGFloat) -> CGPoint { CGPoint(x: x, y: y + offset) }
    func addingOffset(_ orientation: Orientation, _ offset: CGFloat) -> CGPoint { orientation == .h ? addingXOffset(offset) : addingYOffset(offset) }

    func getProjection(_ orientation: Orientation) -> Double { orientation == .h ? x : y }

    var vectorLength: CGFloat { sqrt(x * x + y * y) }

    func distance(to point: CGPoint) -> Double {
        sqrt((x - point.x).squared + (y - point.y).squared)
    }

    var monitorApproximation: Monitor {
        let monitors = monitors
        return monitors.first(where: { $0.rect.contains(self) })
            ?? monitors.minByOrDie { distanceToRectFrame(to: $0.rect) }
    }
}

extension CGFloat {
    func div(_ denominator: Int) -> CGFloat? {
        denominator == 0 ? nil : self / CGFloat(denominator)
    }

    func coerceIn(_ range: ClosedRange<CGFloat>) -> CGFloat {
        switch () {
            case _ where self > range.upperBound: range.upperBound
            case _ where self < range.lowerBound: range.lowerBound
            default: self
        }
    }
}

extension CGSize {
    func copy(width: Double? = nil, height: Double? = nil) -> CGSize {
        CGSize(width: width ?? self.width, height: height ?? self.height)
    }
}

// `@retroactive`: CGPoint is Apple's type and this conformance is ours, so an SDK that adds
// `Hashable` to CGPoint turns this into a redeclaration error at build time -- loud, not silent.
// The fix if that day comes is to delete these six lines, not to write our own Point type.
extension CGPoint: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}

#if DEBUG
    let isDebug = true
#else
    let isDebug = false
#endif

@inlinable
public func checkCancellation() throws(CancellationError) {
    if Task.isCancelled {
        throw CancellationError()
    }
}
