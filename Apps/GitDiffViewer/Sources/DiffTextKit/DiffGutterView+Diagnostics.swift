import AppKit
package import AtelierDiagnostics
import DiffRendering

// MARK: Diagnostics

extension DiffGutterView {
    /// The row whose decorated line number sits under `point`, with its diagnostics and the number's frame.
    func diagnosticHit(at point: NSPoint) -> (
        rowIndex: Int, diagnostics: DiagnosticOverlay.RowDiagnostics, rect: NSRect
    )? {
        guard overlay?.isEmpty == false, point.x >= 0, point.x < bounds.width else { return nil }
        var found: (Int, DiagnosticOverlay.RowDiagnostics, NSRect)?
        forEachFragment(in: Self.row(at: point)) { fragment, _, rowIndex, y in
            // The row's own height: the band of a gap after it holds no line number.
            let height = fragment.layoutFragmentFrame.height - (rendered?.bandSpacing(afterRow: rowIndex) ?? 0)
            guard point.y >= y, point.y < y + height, let diagnostics = overlay?.row(rowIndex) else { return }
            found = (rowIndex, diagnostics, NSRect(x: 0, y: y, width: bounds.width, height: height))
        }
        return found
    }

    /// Opens `findings` of `rowIndex` as a click on the row's decorated line number opens the row's own, anchored on
    /// that line number.
    /// - Returns: False when nothing takes the click or the row is not laid out, true otherwise.
    @discardableResult
    package func showFindings(_ findings: [Finding], ofRow rowIndex: Int) -> Bool {
        guard let onDiagnosticClick, let rect = lineNumberRect(ofRow: rowIndex) else { return false }
        onDiagnosticClick(rowIndex, findings, rect, self)
        return true
    }

    /// `rowIndex`'s line number in this view, as ``diagnosticHit(at:)`` measures it: the row's fragment, less the band
    /// of a gap after it. A targeted, content-addressed lookup, right wherever `rowIndex` lies, near or far from
    /// anywhere else already found: see ``DiffGutterView/changeMarker(at:)``, which shares it for the same reason.
    func lineNumberRect(ofRow rowIndex: Int) -> NSRect? {
        guard let source, let rendered, rendered.lineStarts.indices.contains(rowIndex),
            let layoutManager = source.gutterLayoutManager, let contentManager = layoutManager.textContentManager,
            let location = contentManager.location(
                layoutManager.documentRange.location, offsetBy: rendered.lineStarts[rowIndex])
        else { return nil }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        let y = fragment.layoutFragmentFrame.minY + source.gutterInset - (clipView?.bounds.origin.y ?? 0)
        let height = fragment.layoutFragmentFrame.height - rendered.bandSpacing(afterRow: rowIndex)
        return NSRect(x: 0, y: y, width: bounds.width, height: height)
    }
}

// MARK: Line numbers

extension DiffGutterView {
    /// The top of the line number of the row `fragment` lays out, whose top is `y` in this view.
    ///
    /// Numbers sit on the same baseline as the row's first line of text, whatever the line height is, so they follow
    /// the text up when a taller line centres it: TextKit reports the baseline it laid out, which is not where a
    /// baseline offset then drew the glyphs.
    func numberTop(of fragment: NSTextLayoutFragment, at y: CGFloat) -> CGFloat {
        let firstBaseline =
            fragment.textLineFragments.first.map { $0.typographicBounds.minY + $0.glyphOrigin.y }
            ?? fragment.layoutFragmentFrame.height * 0.75
        return y + firstBaseline - (rendered?.baselineOffset ?? 0) - metrics.font.ascender
    }

    /// Where the gutter draws the line number of each row intersecting `rect` of this view: across the gutter, from
    /// the number's ascender down to its descender, on its row's baseline (book DIFF-06).
    /// - Complexity: O(rows in `rect`), plus a lookup of the first fragment.
    func lineNumberFrames(in rect: NSRect) -> [Int: NSRect] {
        let font = metrics.font
        var frames: [Int: NSRect] = [:]
        forEachFragment(in: rect) { fragment, _, rowIndex, y in
            frames[rowIndex] = NSRect(
                x: 0, y: numberTop(of: fragment, at: y), width: bounds.width, height: font.ascender - font.descender)
        }
        return frames
    }
}
