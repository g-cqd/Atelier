/// The file list's fixed tab (book TAB-10).
extension DiffViewerModel {
    /// Shows the tab, or the file list, one `step` away from the one showing, as ⌃Tab and ⌃⇧Tab do.
    package func showTab(_ step: DiffTabs.Step) {
        switch tabs.neighbour(step) {
            case .fileList: showFileList()
            case .tab(let tab): activateTab(tab.id)
            case nil: break
        }
    }
}
