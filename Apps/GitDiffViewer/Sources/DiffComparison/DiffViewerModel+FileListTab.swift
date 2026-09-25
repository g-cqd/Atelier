import DiffRendering

/// The file list's fixed tab and the scroll positions of the tabs it leaves open (book TAB-10).
extension DiffViewerModel {
    /// The key of the file on show on its own, which its panes keep their scroll position under: its left-side path,
    /// or its selection key under a commit group, so the same file under two commits scrolls apart; nil while cards
    /// or nothing show.
    package var renderedPath: String? {
        guard case .file(let pair) = pipeline.target else { return nil }
        if let scope = commitScope, scope.isSingleFile, scope.file(atPath: pair.path) != nil { return scope.key }
        return pair.path
    }

    /// Shows the tab, or the file list, one `step` away from the one showing, as ⌃Tab and ⌃⇧Tab do.
    package func showTab(_ step: DiffTabs.Step) {
        switch tabs.neighbour(step) {
            case .fileList: showFileList()
            case .tab(let tab): activateTab(tab.id)
            case nil: break
        }
    }

    /// Keeps the scroll positions of the files open in tabs, and forgets the others.
    func retainScrollPositions() {
        scrollMemory.retain(paths: Set(tabs.tabs.map(\.path)))
    }

    /// Whether the file on show is a tab shown again, whose panes go back where they were rather than to its first
    /// change.
    var returnsToRememberedPosition: Bool {
        guard let selectedPath else { return false }
        let panes: [PaneScrollMemory.Pane] = settings.mode == .inline ? [.unified] : [.old, .new]
        return scrollMemory.remembers(selectedPath, panes: panes)
    }
}
