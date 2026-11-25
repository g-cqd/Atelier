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
        guard let row = changeRow(at: index) else { return }
        scrollRequest = ScrollRequest(row: row)
    }

    /// The row the change at `index` starts on in the file shown. A change a folded scope hides starts on the fold's
    /// band: the fold opens, and any fold within it that still hides the change, so the change shows where navigation
    /// lands (DIFF-03).
    private func changeRow(at index: Int) -> Int? {
        // Each fold opened renders the file again at once; a fold nests in fewer scopes than this.
        for _ in 0 ..< Self.foldsOpenedPerMove {
            guard let rendered else { return nil }
            let starts = settings.mode == .inline ? rendered.unifiedChangeStarts : rendered.splitChangeStarts
            guard index < starts.count else { return nil }
            let row = starts[index]
            let text = settings.mode == .inline ? rendered.unified : rendered.new ?? rendered.old
            guard let fold = text?.fold(atRow: row), fold.bandRow == row else { return row }
            changeFolds(.unfold([fold.key]))
        }
        return nil
    }

    /// The most folds one move to a change opens.
    private static let foldsOpenedPerMove = 16
}
