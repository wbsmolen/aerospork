import Foundation
import os.log

/// Debug logging configuration for j4
/// This module sets up enhanced logging when running in debug mode

private let subsystem = "com.wbs.j4.debug"

// MARK: - Logger Instances

let debugLogger = Logger(subsystem: subsystem, category: "debug")
let layoutLogger = Logger(subsystem: subsystem, category: "layout")
let refreshLogger = Logger(subsystem: subsystem, category: "refresh")
let commandLogger = Logger(subsystem: subsystem, category: "command")
let performanceLogger = Logger(subsystem: subsystem, category: "performance")
let cacheLogger = Logger(subsystem: subsystem, category: "cache")
let configLogger = Logger(subsystem: subsystem, category: "config")

// MARK: - Debug Logging Configuration

/// Initialize debug logging and performance monitoring
@MainActor
func initDebugLogging() {
    guard isDebug else { return }

    debugLogger.info("🔧 Debug logging initialized")
    debugLogger.info("  Subsystem: \(subsystem)")
    debugLogger.info("  Categories: debug, layout, refresh, command, performance, cache, config")

    // Enable performance metrics in debug mode
    if config.performanceConfig.monitoringConfig.enableMetrics == false {
        var newConfig = config
        newConfig.performanceConfig.monitoringConfig.enableMetrics = true
        newConfig.performanceConfig.monitoringConfig.enableDebugLogging = true
        newConfig.performanceConfig.monitoringConfig.metricsInterval = 10.0
        config = newConfig

        performanceLogger.info("✅ Performance metrics enabled (debug mode)")
        performanceLogger.info("  Metrics interval: 10s")
    }

    configLogger.info("📄 Config file: \(configUrl.path)")
    debugLogger.info("🚀 j4 debug mode ready")
}

// MARK: - Command Execution Tracing

/// Wrapper for command execution with timing and logging
@MainActor
func traceCommandExecution<T>(
    commandName: String,
    args: String = "",
    operation: () throws -> T
) rethrows -> T {
    guard isDebug else {
        return try operation()
    }

    let startTime = CFAbsoluteTimeGetCurrent()
    commandLogger.debug("▶️ Executing: \(commandName) \(args)")

    let result = try operation()

    let duration = CFAbsoluteTimeGetCurrent() - startTime
    let durationMs = String(format: "%.2f", duration * 1000)
    commandLogger.debug("✅ Completed: \(commandName) (\(durationMs)ms)")

    return result
}

/// Async wrapper for command execution with timing and logging
@MainActor
func traceCommandExecutionAsync<T>(
    commandName: String,
    args: String = "",
    operation: () async throws -> T
) async rethrows -> T {
    guard isDebug else {
        return try await operation()
    }

    let startTime = CFAbsoluteTimeGetCurrent()
    commandLogger.debug("▶️ Executing: \(commandName) \(args)")

    let result = try await operation()

    let duration = CFAbsoluteTimeGetCurrent() - startTime
    let durationMs = String(format: "%.2f", duration * 1000)
    commandLogger.debug("✅ Completed: \(commandName) (\(durationMs)ms)")

    return result
}

// MARK: - Layout Calculation Tracing

/// Trace layout calculations with timing
@MainActor
func traceLayout(
    operationName: String,
    windowCount: Int,
    operation: () -> Void
) {
    guard isDebug else {
        operation()
        return
    }

    let startTime = CFAbsoluteTimeGetCurrent()
    layoutLogger.debug("🔲 Layout \(operationName) (windows: \(windowCount))")

    operation()

    let duration = CFAbsoluteTimeGetCurrent() - startTime
    let durationMs = String(format: "%.2f", duration * 1000)
    layoutLogger.debug("  ✓ Layout complete (\(durationMs)ms)")
}

// MARK: - Refresh Session Tracing

/// Trace refresh sessions with timing
@MainActor
func traceRefresh(
    reason: String,
    operation: () async throws -> Void
) async rethrows {
    guard isDebug else {
        try await operation()
        return
    }

    let startTime = CFAbsoluteTimeGetCurrent()
    refreshLogger.debug("🔄 Refresh session: \(reason)")

    try await operation()

    let duration = CFAbsoluteTimeGetCurrent() - startTime
    let durationMs = String(format: "%.2f", duration * 1000)
    refreshLogger.debug("  ✓ Refresh complete (\(durationMs)ms)")
}

// MARK: - Helper for Console.app Viewing

/// Print instructions for viewing logs in Console.app
func printLogViewingInstructions() {
    guard isDebug else { return }

    print("""

    📊 Debug Logging Enabled
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    To view detailed logs:
    1. Open Console.app
    2. Filter by:
       • Subsystem: \(subsystem)
       • Process: j4App

    Categories available:
       • debug       - General debug information
       • layout      - Window layout calculations
       • refresh     - Refresh session tracking
       • command     - Command execution with timing
       • performance - Performance metrics
       • cache       - Cache operations
       • config      - Configuration changes

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    """)
}
