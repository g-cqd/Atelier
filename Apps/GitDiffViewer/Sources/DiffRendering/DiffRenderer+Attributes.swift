import AppKit
import DiffCore
import DiffGit
import Foundation

// A row's attributed text, its bands, and the line and kind a side shows; apart from the type's file, to keep it within the limits SwiftLint sets.
extension DiffRenderer {
    /// Applies the palette to the assembled text: font, the text colour, paragraph style, the placeholders of the bidi
    /// controls the rows show, which keep the source's offsets, and bold headers. The text is plain (PERF-09 stage 0):
    /// syntax colour and emphasis are drawn over it once they land, and change no layout (`DiffDecorations`).
    static func attributed(
        _ text: String,
        placeholders: BidiControls.Placeholders,
        metas: [RowMeta],
        lineStarts: [Int],
        options: Options
    ) -> (attributed: NSMutableAttributedString, baselineOffset: CGFloat, lineHeight: CGFloat) {
        let palette = options.palette
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: palette.font]).width
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = []
        paragraphStyle.defaultTabInterval = 4 * spaceWidth
        paragraphStyle.headIndent = 2 * spaceWidth
        // A taller line gets all of its extra space above the glyphs, which leaves the text on the floor of its
        // row. The layout keeps it that way, so heights, hit testing and the baseline TextKit reports all stay
        // consistent, and the panes raise the glyphs by half the extra when they draw them. A baseline offset
        // would be the obvious tool and is the wrong one: it feeds back into the line height it is measured from.
        let multiple = max(options.lineHeightMultiple > 0 ? options.lineHeightMultiple : palette.lineHeightMultiple, 1)
        paragraphStyle.lineHeightMultiple = multiple
        let baselineOffset = (multiple - 1) * palette.defaultLineHeight / 2

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [.font: palette.font, .foregroundColor: palette.textColor, .paragraphStyle: paragraphStyle]
        )
        attributed.beginEditing()
        placeholders.apply(to: attributed, palette: palette)
        let boldFont =
            NSFont(descriptor: palette.font.fontDescriptor.withSymbolicTraits(.bold), size: palette.font.pointSize)
            ?? palette.font
        for (index, meta) in metas.enumerated() where meta.kind == .header {
            let end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : attributed.length
            attributed.addAttribute(
                .font,
                value: boldFont,
                range: NSRange(location: lineStarts[index], length: end - lineStarts[index])
            )
        }
        attributed.endEditing()

        return (attributed, baselineOffset, multiple * palette.defaultLineHeight)
    }

    /// Gives each gap between two rows its empty band (book DIFF-02), as the paragraph spacing of the row above it,
    /// newline and all. The bands above the first row and below the last are the views' to keep: TextKit ignores the
    /// spacing before a text's first paragraph and after its last.
    static func addBands(
        of gaps: [RenderedGap],
        lineStarts: [Int],
        lineHeight: CGFloat,
        to text: NSMutableAttributedString
    ) {
        for gap in gaps where gap.hasBand && gap.boundary > 0 && gap.boundary < lineStarts.count {
            // A row before another ends with its newline, so it has a unit to read its style from.
            let start = lineStarts[gap.boundary - 1]
            guard let style = text.attribute(.paragraphStyle, at: start, effectiveRange: nil) as? NSParagraphStyle,
                let banded = style.mutableCopy() as? NSMutableParagraphStyle
            else { continue }
            banded.paragraphSpacing = RenderedText.gapBandHeight(lineHeight: lineHeight)
            text.addAttribute(
                .paragraphStyle,
                value: banded,
                range: NSRange(location: start, length: lineStarts[gap.boundary] - start)
            )
        }
    }

    /// The source line `row` shows on `side`: a unified row its new line, or its old one when it has no new line.
    static func shownLine(of row: DiffRow, in file: PreparedDiff, side: RenderedSide) -> Substring? {
        let old = row.old.map { file.model.oldLines[$0.index] }
        let new = row.new.map { file.model.newLines[$0.index] }
        switch side {
            case .unified: return new ?? old
            case .old: return old
            case .new: return new
        }
    }

    static func displayedKind(of row: DiffRow, side: RenderedSide, hasLine: Bool) -> RowKind {
        guard hasLine else { return .filler }
        switch (row.kind, side) {
            case (.modified, .old): return .removed
            case (.modified, .new): return .added
            default: return row.kind
        }
    }

    /// Appends `line` to `text` at UTF-16 `offset`, its bidirectional controls shown as placeholders.
    /// - Returns: its length in UTF-16 units and its tab count, which together measure its width.
    static func appendShown(
        _ line: Substring,
        at offset: Int,
        to text: inout String,
        placeholders: inout BidiControls.Placeholders
    ) -> (length: Int, tabs: Int) {
        text.append(contentsOf: placeholders.reveal(line, at: offset))
        var tabs = 0
        for unit in line.utf16 where unit == 9 { tabs += 1 }
        return (line.utf16.count, tabs)
    }

    /// The fold a scope band draws on row `row`, after the rows it hides, with its marker at UTF-16 `offset`.
    static func fold(_ band: ScopeFoldBand, marker: Range<Int>, at offset: Int, row: Int) -> RenderedFold {
        RenderedFold(
            key: band.key,
            lastLine: band.lastLine,
            firstRow: row - 1,
            bandRow: row,
            holdsChange: band.holdsChange,
            marker: (offset + marker.lowerBound) ..< (offset + marker.upperBound)
        )
    }

    /// A diff row's meta: its kind, and its line numbers, one-based; the old side's only when `numbersOld`.
    static func meta(of row: DiffRow, kind: RowKind, numbersOld: Bool, fileIndex: Int) -> RowMeta {
        RowMeta(
            kind: kind,
            oldNumber: numbersOld ? row.old.map { $0.index + 1 } : nil,
            newNumber: row.new.map { $0.index + 1 },
            fileIndex: fileIndex
        )
    }
}
