package import AtelierDiagnostics

/// The Findings list's navigation: a row opens its finding's file, then the file's render scrolls to the line.
extension DiffViewerModel {
    /// Opens `finding`'s file in a pinned tab, as a Findings row does, and keeps its line for
    /// ``takeFindingReveal()``, which the model reads when the file's render lands (DUI-01, GDV S18).
    package func reveal(_ finding: Finding) {
        let leftPath = counterpartPath(of: finding.file, in: .right)
        diagnostics?.pendingReveal = FindingReveal(leftPath: leftPath, line: finding.line)
        pin(finding.file, from: .right)
    }

    /// The row to scroll to for the finding ``reveal(_:)`` opened, once its file is the one rendered; nil before.
    /// Consumes the reveal, so a later render of the same file keeps the user's own scroll position.
    package func takeFindingReveal() -> Int? {
        guard let diagnostics, let reveal = diagnostics.pendingReveal, selectedPath == reveal.leftPath, let rendered
        else { return nil }
        diagnostics.pendingReveal = nil
        return reveal.row(in: rendered, inline: settings.mode == .inline)
    }
}
