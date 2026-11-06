struct FrozenWorld {
    let workspaces: [FrozenWorkspace]
    let monitors: [FrozenMonitor]
    let windowIds: Set<UInt32>

    init(workspaces: [FrozenWorkspace], monitors: [FrozenMonitor]) {
        self.workspaces = workspaces
        self.monitors = monitors
        self.windowIds = workspaces.flatMap { collectAllWindowIds(workspace: $0) }.toSet()
    }
}

private func collectAllWindowIds(workspace: FrozenWorkspace) -> [UInt32] {
    workspace.floatingWindows.map { $0.id } +
        workspace.macosUnconventionalWindows.map { $0.id } +
        workspace.rootTilingNode.allWindowIds
}
