import AppKit
import Common

/// Coalesces bursts of accessibility events into a single refresh after a short fixed delay.
/// A window manager sees rapid-fire AX notifications (app activate, window move, space change);
/// debouncing at 50ms collapses them so we lay out once instead of per-event.
@MainActor
final class RefreshDebouncer {
    private var pendingTask: Task<Void, Never>?
    private let delay: TimeInterval

    init(delay: TimeInterval = 0.05) { // 50ms
        self.delay = delay
    }

    func debounce(
        event: RefreshSessionEvent,
        screenIsDefinitelyUnlocked: Bool,
        optimisticallyPreLayoutWorkspaces: Bool = false,
    ) {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }

            activeRefreshTask?.cancel()
            activeRefreshTask = Task { @MainActor in
                try checkCancellation()
                try await runRefreshSessionBlocking(event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
            }

            if screenIsDefinitelyUnlocked {
                resetClosedWindowsCache()
            }
        }
    }

    func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
    }
}
