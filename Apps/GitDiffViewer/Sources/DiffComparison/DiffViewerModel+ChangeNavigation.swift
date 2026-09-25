import DiffRendering

/// Moving from one change to the next, in a file or through the cards of a file list.
extension DiffViewerModel {
    package func goToNextChange() {
        navigator.next(count: changeCount)
        requestScrollToCurrentChange()
    }

    package func goToPreviousChange() {
        navigator.previous(count: changeCount)
        requestScrollToCurrentChange()
    }

    /// In a file the request names a row; in a file list it names the file card to bring into view.
    func requestScrollToCurrentChange() {
        guard let index = navigator.current(count: changeCount).map({ $0 - 1 }) else { return }
        if isShowingCombinedFiles {
            scrollRequest = ScrollRequest(row: index)
            return
        }
        guard let rendered else { return }
        let starts = settings.mode == .inline ? rendered.unifiedChangeStarts : rendered.splitChangeStarts
        guard index < starts.count else { return }
        scrollRequest = ScrollRequest(row: starts[index])
    }
}
