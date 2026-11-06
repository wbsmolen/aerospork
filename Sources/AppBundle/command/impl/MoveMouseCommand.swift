import AppKit
import Common

struct MoveMouseCommand: Command {
    let args: MoveMouseCmdArgs

    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let mouse = mouseLocation
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        // What the commands before this one in a sequence did hasn't been laid out yet, and the window's
        // rect comes from layout. `move left; move-mouse window-lazy-center` went to the old spot.
        if args.mouseTarget.val == .windowLazyCenter || args.mouseTarget.val == .windowForceCenter { try await layoutWorkspaces() }
        switch args.mouseTarget.val {
            case .windowLazyCenter:
                guard let rect = try await windowSubjectRectOrReportError(target, io) else { return false }
                if rect.contains(mouse) {
                    return handleNoop("The mouse already belongs to the window.", failIfNoop: args.failIfNoop, io: io)
                }
                return moveMouse(io, rect.center)
            case .windowForceCenter:
                guard let rect = try await windowSubjectRectOrReportError(target, io) else { return false }
                return moveMouse(io, rect.center)
            case .monitorLazyCenter:
                let rect = target.workspace.workspaceMonitor.rect
                if rect.contains(mouse) {
                    return handleNoop("The mouse already belongs to the monitor.", failIfNoop: args.failIfNoop, io: io)
                }
                return moveMouse(io, rect.center)
            case .monitorForceCenter:
                return moveMouse(io, target.workspace.workspaceMonitor.rect.center)
        }
    }
}

private func moveMouse(_ io: CmdIo, _ point: CGPoint) -> Bool {
    let event = CGEvent(
        mouseEventSource: nil,
        mouseType: CGEventType.mouseMoved,
        mouseCursorPosition: point,
        mouseButton: CGMouseButton.left,
    )
    if let event {
        event.post(tap: CGEventTapLocation.cghidEventTap)
        return true
    } else {
        return io.err("Failed to move mouse")
    }
}

/// The rect a `window-*` target centres on.
///
/// Falls back to the workspace's monitor when there is no focused window. An empty workspace has
/// none, so "centre on the focused window" has no meaning there -- and the old behaviour, erroring
/// out and not moving at all, leaves the pointer on whichever monitor you switched away from. That
/// is the one case where the user most obviously wants it to move: they are now looking at a
/// different screen with nothing on it.
///
/// This is why `on-focused-workspace-changed = ['move-mouse window-lazy-center']` appeared to work
/// except when switching to an empty workspace.
@MainActor
func windowSubjectRectOrReportError(_ target: LiveFocus, _ io: CmdIo) async throws -> Rect? {
    let monitorRect = target.workspace.workspaceMonitor.rect
    guard let window: Window = target.windowOrNil else {
        return monitorRect
    }
    // A rect that is not on the workspace's own monitor is stale, not a position. This command runs
    // from `on-focused-workspace-changed`, which can fire before `layoutWorkspaces()` has applied
    // the new frames -- so `lastAppliedLayoutPhysicalRect` may still describe where the window sat
    // BEFORE the switch. Centring on that leaves the pointer on the monitor the user just left, and
    // `window-lazy-center` then sees the mouse already "inside" and declines to move at all.
    // Measured: 2 of 16 switches stranded the pointer on the previous workspace's monitor.
    // Tested on the rect's centre, because that is the point the mouse would actually be moved to.
    let isOnTargetMonitor = { (rect: Rect) in monitorRect.contains(rect.center) }

    if let rect = window.lastAppliedLayoutPhysicalRect, isOnTargetMonitor(rect) {
        return rect
    }
    if let rect = try await window.getAxRect(), isOnTargetMonitor(rect) {
        return rect
    }
    // Neither rect has caught up with the switch yet. The monitor is still the right answer -- it is
    // where the user is now looking -- and it is strictly better than not moving.
    return monitorRect
}
