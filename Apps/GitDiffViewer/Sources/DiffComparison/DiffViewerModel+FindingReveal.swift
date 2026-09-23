package import AtelierDiagnostics

/// The Findings list's navigation: a row opens its finding's file, then the file's render scrolls to the line.
extension DiffViewerModel {
    /// Opens `finding`'s file in a pinned tab, as a Findings row does, and keeps its line for
    /// ``takeFindingReveal()``, which the model reads when the file's render lands (DUI-01, GDV S18). `side` is the
    /// side the finding was found on, whose path and line numbers it carries.
    package func reveal(_ finding: Finding, on side: DiagnosticsSide = .right) {
        let leftPath = side == .right ? counterpartPath(of: finding.file, in: .right) : finding.file
        diagnostics?.pendingReveal = FindingReveal(leftPath: leftPath, line: finding.line, side: side)
        pin(leftPath, from: .left)
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
