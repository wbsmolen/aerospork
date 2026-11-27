/// The events `aerospork subscribe` streams. Their names and fields are a public contract, documented in
/// docs/aerospork-subscribe.adoc.
public enum SubscribeEvent: String, CaseIterable, Equatable, Sendable {
    case focusChanged = "focus-changed"
    case focusedWorkspaceChanged = "focused-workspace-changed"
    case focusedMonitorChanged = "focused-monitor-changed"
    case modeChanged = "mode-changed"
    case windowDetected = "window-detected"
    case workspaceWindowsChanged = "workspace-windows-changed"
}
