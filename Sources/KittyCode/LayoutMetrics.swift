import KittyWidgets

struct LayoutMetrics {
    let activityBarWidth: Int
    let sidebarWidth: Int
    let totalSidebarWidth: Int
    let editorStart: Int
    let editorWidth: Int
    let contentStartRow: Int
    let contentRows: Int
    let showTabRibbon: Bool

    @MainActor
    static func editorStart(state: EditorState, columns: Int) -> Int {
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
    init(state: EditorState, columns: Int, rows: Int) {
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
