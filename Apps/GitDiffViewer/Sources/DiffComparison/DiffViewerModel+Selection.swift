/// What the user shows: a file or folder picked in an explorer, the file list, or a tab.
extension DiffViewerModel {
    /// A single click: shows the file or folder in the temporary tab. Nil closes every tab and shows the whole list.
    package func select(_ path: String?, from side: Side = .left) {
        timer.begin()
        let leftPath = path.map { side == .left ? $0 : comparison.counterpartPath(of: $0, in: .right) }
        if let leftPath { tabs.open(leftPath) } else { tabs.closeAll() }
        retainScrollPositions()
        applySelection(leftPath, keepingPublished: false)
    }

    /// A double click: shows the file or folder in a pinned tab of its own.
    package func pin(_ path: String, from side: Side = .left) {
        timer.begin()
        let leftPath = side == .left ? path : comparison.counterpartPath(of: path, in: .right)
        tabs.pin(leftPath)
        retainScrollPositions()
        applySelection(leftPath, keepingPublished: false)
    }

    /// Shows every changed file in the file list's fixed tab; every tab stays open, and shows as it was when it is
    /// shown again (book TAB-10).
    package func showFileList() {
        tabs.activateFileList()
        guard selectedPath != nil else { return }
        timer.begin()
        applySelection(nil, keepingPublished: false)
    }

    package func activateTab(_ id: DiffTab.ID) {
        tabs.activate(id)
        guard tabs.activePath != selectedPath else { return }
        timer.begin()
        applySelection(tabs.activePath, keepingPublished: false)
    }

    package func pinTab(_ id: DiffTab.ID) {
        tabs.pin(id)
        guard tabs.activePath != selectedPath else { return }
        timer.begin()
        applySelection(tabs.activePath, keepingPublished: false)
    }

    package func closeTab(_ id: DiffTab.ID) {
        tabs.close(id)
        retainScrollPositions()
        guard tabs.activePath != selectedPath else { return }
        timer.begin()
        applySelection(tabs.activePath, keepingPublished: false)
    }

    /// Shows `leftPath`. A selection the user makes takes what is published away at once and streams the new one in;
    /// one a re-comparison makes, because the selected path went away, keeps what is published until it lands.
    func applySelection(_ leftPath: String?, keepingPublished: Bool) {
        selectedPath = leftPath
        // A request made for what showed before means nothing to what shows next, and a pane made anew would act on it.
        scrollRequest = nil
        navigator.reset()
        folding.reset()
        render(keepingPublished: keepingPublished)
    }
}
