package import DiffRendering

/// Where the Findings list takes the window for a finding (DUI-01): its file, then the row showing its line once that
/// file is on screen. The row is looked up in the render, since the line can sit in a gap the isolated layout hides.
package struct FindingReveal: Equatable, Sendable {
    /// The file's path on the left side, which is how the window selects it.
    package let leftPath: String
    /// The finding's 1-based line in the file on its own side.
    package let line: Int
    /// The side the finding was found on, whose line numbers ``line`` counts in.
    package let side: DiagnosticsSide

    package init(leftPath: String, line: Int, side: DiagnosticsSide = .right) {
        self.leftPath = leftPath
        self.line = line
        self.side = side
    }

    /// The row that shows ``line`` in the text a scroll request addresses: the unified text inline, the split text
    /// otherwise, whose two panes share their rows, read by the side's own line numbers. A line hidden in a gap lands
    /// on the last row shown before it, and one before every shown line on the first row; nil when the text has no
    /// row at all.
    package func row(in rendered: RenderedDiff, inline: Bool) -> Int? {
        let text = inline ? rendered.unified : (side == .right ? rendered.new : rendered.old)
        guard let text, !text.rows.isEmpty else { return nil }
        var best = 0
        for (index, meta) in text.rows.enumerated() {
            guard let number = side == .right ? meta.newNumber : meta.oldNumber else { continue }
            if number == line { return index }
            if number > line { break }
            best = index
        }
        return best
    }
}
