package import DiffRendering

/// Folded scopes (DIFF-03): the gutter's ribbon and the folding commands fold and unfold them.
extension DiffViewerModel {
    /// The folded scopes, each with its last line on its side.
    package var foldedScopes: [ScopeFoldKey: Int] {
        pipeline.foldedScopes
    }

    /// Folds or unfolds scopes as a click on the ribbon or a folding command asks.
    package func changeFolds(_ request: ScopeFoldRequest) {
        timer.abandon()
        pipeline.changeFolds(request)
    }
}
