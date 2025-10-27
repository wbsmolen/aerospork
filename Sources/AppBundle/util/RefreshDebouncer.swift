import AppKit
import Common

@MainActor
final class RefreshDebouncer {
    private var pendingTask: Task<Void, Never>?
    private var pendingEvent: RefreshSessionEvent?
    private let delay: TimeInterval
    private let adaptiveDebouncer: AdaptiveDebouncer

    init(delay: TimeInterval = 0.05) { // 50ms default delay
        self.delay = delay
        self.adaptiveDebouncer = AdaptiveDebouncer(baseDelay: delay)
    }

    func debounce(
        event: RefreshSessionEvent,
        screenIsDefinitelyUnlocked: Bool,
        optimisticallyPreLayoutWorkspaces: Bool = false,
    ) {
        // HOTFIX: Disable adaptive debouncing to fix slow window movements
        // The adaptive debouncing was causing excessive delays (up to 450ms)
        // when stacking multipliers for pattern-based, health-based, and event-specific adjustments
        // Use fixed delay for all events for now
        debugLog("DEBOUNCE: Using fixed delay \(delay * 1000)ms for event: \(event)")
        debounceWithFixedDelay(
            event: event,
            screenIsDefinitelyUnlocked: screenIsDefinitelyUnlocked,
            optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces,
        )
    }

    private func debounceWithFixedDelay(
        event: RefreshSessionEvent,
        screenIsDefinitelyUnlocked: Bool,
        optimisticallyPreLayoutWorkspaces: Bool = false,
    ) {
        // Cancel any pending refresh
        pendingTask?.cancel()

        // Store the most recent event
        pendingEvent = event

        // Schedule a new refresh after the delay
        pendingTask = Task { @MainActor in
            let taskStartTime = Date()
            debugLog("DEBOUNCE: Task scheduled, will wait \(delay * 1000)ms")

            // Wait for the debounce delay
            try? await Task.sleep(for: .seconds(delay))

            // Check if we weren't cancelled
            guard !Task.isCancelled else {
                debugLog("DEBOUNCE: Task cancelled after \(Date().timeIntervalSince(taskStartTime) * 1000)ms")
                return
            }

            debugLog("DEBOUNCE: Executing refresh after \(Date().timeIntervalSince(taskStartTime) * 1000)ms")

            // Execute the refresh
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
        pendingEvent = nil
        adaptiveDebouncer.cancelPending()
    }

    var hasPendingRefresh: Bool {
        // HOTFIX: Always use fixed delay behavior
        return pendingTask != nil && !pendingTask!.isCancelled
    }

    /// Get statistics about debouncing performance
    func getStatistics() -> DebouncingStatistics {
        // HOTFIX: Always return fixed delay statistics
        return DebouncingStatistics(
            isAdaptive: false,
            baseDelay: delay,
            averageDelay: delay,
            efficiency: 1.0,
            totalOperations: 0,
        )
    }
}

struct DebouncingStatistics: Sendable {
    let isAdaptive: Bool
    let baseDelay: TimeInterval
    let averageDelay: TimeInterval
    let efficiency: Double
    let totalOperations: Int
}
