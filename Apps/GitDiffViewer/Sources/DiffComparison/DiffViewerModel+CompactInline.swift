package import DiffRendering

/// The compact inline view's disclosures (book DIFF-04): a marker's click, and the keyboard commands that disclose or
/// fold the current change or every change.
extension DiffViewerModel {
    /// Whether the detail shows the compact inline view: the inline layout with the setting on.
    package var showsCompactInline: Bool {
        settings.mode == .inline && settings.compactsInlineView
    }

    /// The changes shown disclosed.
    package var disclosedChanges: Set<ChangeKey> {
        pipeline.disclosedChanges
    }

    /// Discloses the change `key` when it is folded and folds it when it is disclosed, as a click on its marker does.
    package func toggleChange(_ key: ChangeKey) {
        guard showsCompactInline else { return }
        timer.abandon()
        toggle([key], ofFiles: [key.fileIndex])
    }

    /// Discloses or folds the current change, the one change navigation last moved to, or the first one when none is
    /// current. In the card list, where navigation moves from card to card, every change of the current card together.
    package func toggleCurrentChange() {
        guard showsCompactInline, changeCount > 0 else { return }
        let index = navigator.current(count: changeCount).map { $0 - 1 } ?? 0
        timer.abandon()
        if isShowingCombinedFiles {
            toggle(pipeline.changeKeys(ofFiles: [index]), ofFiles: [index])
        } else {
            toggle([ChangeKey(fileIndex: 0, changeIndex: index)], ofFiles: [0])
        }
    }

    /// Discloses every change shown when any is folded, and folds them all otherwise.
    package func toggleAllChanges() {
        guard showsCompactInline else { return }
        let files = isShowingCombinedFiles ? Array(renderedFiles.indices) : [0]
        timer.abandon()
        toggle(pipeline.changeKeys(ofFiles: files), ofFiles: Set(files))
    }

    /// Folds `keys` when every one of them is disclosed, and discloses them all otherwise, leaving the other changes
    /// of the files at `files` as they are.
    private func toggle(_ keys: [ChangeKey], ofFiles files: Set<Int>) {
        guard !keys.isEmpty else { return }
        let current = pipeline.disclosedChanges.filter { files.contains($0.fileIndex) }
        let target = Set(keys).isSubset(of: current) ? current.subtracting(keys) : current.union(keys)
        pipeline.setDisclosedChanges(target, ofFiles: files)
    }
}
