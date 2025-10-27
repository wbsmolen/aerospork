import AppKit
import Common

// MARK: - Shared Error Messages

/// Error message when no window is currently focused
let noWindowIsFocused = "No window is focused"

/// Error message for attempting to move unconventional macOS windows
let moveOutMacosUnconventionalWindow = "moving macOS fullscreen, minimized windows and windows of hidden apps isn't yet supported. This behavior is subject to change"

/// Tip message for --fail-if-noop flag
let noopTip = "Tip: use --fail-if-noop to exit with non-zero code"

// MARK: - Command Helper Extensions

extension Command {
    /// Requires a window from the target, returning error if none focused
    @MainActor
    func requireWindow(from target: LiveFocus, _ io: CmdIo) -> Window? {
        guard let window = target.windowOrNil else {
            io.err(noWindowIsFocused)
            return nil
        }
        return window
    }

    /// Handles noop case with consistent messaging
    @MainActor
    func handleNoop(_ message: String, failIfNoop: Bool, io: CmdIo) -> Bool {
        io.err("\(message) \(noopTip)")
        return !failIfNoop
    }

    /// Resolves toggle state (on/off/toggle) for ToggleEnum
    func resolveToggle(_ toggle: ToggleEnum, current: Bool) -> Bool {
        switch toggle {
            case .on: true
            case .off: false
            case .toggle: !current
        }
    }

    /// Resolves toggle state (on/off/toggle) for EnableCmdArgs.State
    func resolveToggle(_ toggle: EnableCmdArgs.State, current: Bool) -> Bool {
        switch toggle {
            case .on: true
            case .off: false
            case .toggle: !current
        }
    }
}

// MARK: - List Command Helpers

extension Command {
    /// Formats list output with support for count-only, JSON, and formatted output
    @MainActor
    func formatListOutput<T>(
        _ items: [T],
        countOnly: Bool,
        json: Bool,
        format: [StringInterToken],
        ignoreRightPadding: Bool,
        mapper: (T) -> AeroObj,
        io: CmdIo
    ) -> Bool {
        if countOnly {
            return io.out("\(items.count)")
        }

        let list = items.map(mapper)

        if json {
            return switch list.formatToJson(format, ignoreRightPaddingVar: ignoreRightPadding) {
                case .success(let json): io.out(json)
                case .failure(let msg): io.err(msg)
            }
        } else {
            return switch list.format(format) {
                case .success(let lines): io.out(lines)
                case .failure(let msg): io.err(msg)
            }
        }
    }
}
