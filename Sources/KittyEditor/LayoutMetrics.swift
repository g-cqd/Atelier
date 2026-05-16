import KittyWidgets

public struct LayoutMetrics {
    public let activityBarWidth: Int
    public let sidebarWidth: Int
    public let totalSidebarWidth: Int
    public let editorStart: Int
    public let editorWidth: Int
    public let contentStartRow: Int
    public let contentRows: Int
    public let showTabRibbon: Bool

    @MainActor
    public static func editorStart(state: EditorState, columns: Int) -> Int {
        let showAB = state.config.activityBar.show && !state.sidebarCollapsed
        let abWidth = showAB ? ActivityBar.width : 0
        let sidebarWidth: Int
        if state.sidebarCollapsed {
            sidebarWidth = 0
        } else {
            sidebarWidth = min(state.treePanelWidth, columns / 2)
        }
        let separatorWidth = sidebarWidth > 0 ? 1 : 0
        return abWidth + sidebarWidth + separatorWidth
    }

    @MainActor
    public init(state: EditorState, columns: Int, rows: Int) {
        let showAB = state.config.activityBar.show && !state.sidebarCollapsed
        self.activityBarWidth = showAB ? ActivityBar.width : 0
        self.showTabRibbon =
            state.config.tabRibbon.position == .top && state.bufferManager.count > 0
        let tabRows = showTabRibbon ? 1 : 0
        self.contentStartRow = tabRows
        self.contentRows = max(0, rows - 1 - tabRows)

        if state.sidebarCollapsed {
            self.sidebarWidth = 0
        } else {
            self.sidebarWidth = min(state.treePanelWidth, columns / 2)
        }
        self.totalSidebarWidth = activityBarWidth + sidebarWidth
        let separatorWidth = sidebarWidth > 0 ? 1 : 0
        self.editorStart = totalSidebarWidth + separatorWidth
        self.editorWidth = max(0, columns - self.editorStart)
    }
}
