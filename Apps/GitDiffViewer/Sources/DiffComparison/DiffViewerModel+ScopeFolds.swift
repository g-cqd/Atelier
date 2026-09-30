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

    /// Unfolds every scope, as turning the ribbon off does: with it off, nothing can fold one back.
    func unfoldAllScopes() {
        guard !foldedScopes.isEmpty else { return }
        changeFolds(.unfold(Set(foldedScopes.keys)))
    }

    /// Follows every appearance setting that is not its own SwiftUI binding.
    func followAppearanceSettingsChange() {
        refreshCommitGroups(force: false)
        followSemanticColorSetting()
        followColorSettings()
        if !settings.showsScopeRibbon { unfoldAllScopes() }
    }
}
