import Common
import os

/// The channel a user's problem can still be diagnosed from *after* it happened.
///
/// `debugLog` is the other channel and it solves a different problem. It writes at os_log level
/// `.debug`, which the unified log does not persist to disk -- a `.debug` record is only visible to
/// a `log stream` that was already running -- and it is gated on `AEROSPORK_DEBUG_LOG`, which no
/// user has set. So with the shipped defaults the app left no trace at all, and "reproduce it, then
/// send me the log" had no answer. `.notice` and `.error` records *are* persisted, so `log show
/// --last 1h` after the fact returns them.
///
/// That difference is the whole design rule: **anything here must be cheap and rare.** `debugLog`
/// is free when the gate is off, so per-refresh and per-command tracing belongs there. These write
/// unconditionally, so they are reserved for events a user would mention in a bug report -- config
/// loaded/rejected, server up/down, a command that failed. Roughly: config reloads and failed
/// commands, not window moves.
///
/// The subsystem is `aeroSporkAppId`, so a debug build logs under `com.wbs.aerospork.debug` and a
/// release build under `com.wbs.aerospork`, and a `log show` predicate can tell the two apart.
/// Hardcoding the release id makes a debug build lie about which binary produced the record --
/// `BrandingTest.testLoggersUseTheBuildsOwnBundleId` rejects the literal.
///
enum AppLog {
    /// Which config file loaded, and why one didn't.
    static let config = Logger(subsystem: aeroSporkAppId, category: "config")
    /// Socket lifecycle and commands that came in over it.
    static let server = Logger(subsystem: aeroSporkAppId, category: "server")
    /// Failures inside detached refresh sessions -- see `runDetached` -- and every focus change the
    /// user did not ask for.
    ///
    /// Focus qualifies under the cheap-and-rare rule because only the *involuntary* changes are
    /// recorded: a window dying under the focused one, a session syncing a focus the user never
    /// moved, the closed-windows-cache restore, and macOS pulling focus onto a workspace that was not
    /// on screen. Focus commands, workspace switches and clicks -- including a click on another
    /// monitor -- stay silent. In a healthy system that is a handful of records a day; in a broken one
    /// it is the whole bug report. Issue #39 was undiagnosable because none of these logged anything.
    static let session = Logger(subsystem: aeroSporkAppId, category: "session")
}
