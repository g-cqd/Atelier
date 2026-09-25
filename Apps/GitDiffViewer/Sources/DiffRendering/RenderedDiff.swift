package import AppKit
import AtelierSwiftSyntax
package import DiffCore
import DiffGit
package import Foundation

/// Identifies a gap between two hunks of one file in a rendered document.
package struct GapKey: Hashable, Sendable {
    package let fileIndex: Int
    package let gapIndex: Int
}

package struct GapMarker: Sendable, Hashable {
    package let key: GapKey
    package let hiddenRows: Int
    /// No hunk above: only rows before the next hunk can be revealed.
    package let isLeading: Bool
    /// No hunk below: only rows after the previous hunk can be revealed.
    package let isTrailing: Bool
}

/// A gap where a rendered text shows it: on the boundary between the two rows around the rows it hides (book DIFF-02).
package struct RenderedGap: Sendable, Hashable {
    /// The boundary, counted in rows above it: 0 lies above the first row, `rows.count` below the last.
    package let boundary: Int
    package let marker: GapMarker

    /// Whether the gap takes an empty band of its own on its boundary, to hold its handle: one that offers a handle
    /// does, and one hiding a whole file without a change leaves no trace.
    package var hasBand: Bool { !marker.handles.isEmpty }

    /// Whether the gap's band carries a separator, a hairline across its middle from the gutter's leading edge to the
    /// text's trailing one. Only a gap between two changes has one, between its two halves; a gap at the top or the
    /// end of a file shows its one half alone.
    package var hasSeparator: Bool { marker.handles.count == 2 }
}

package struct RowMeta: Sendable {
    package let kind: RowKind
    package let oldNumber: Int?
    package let newNumber: Int?
    package var fileIndex = 0
    /// The line only moved; drawn in a calmer colour than a real change.
    package var isMoved = false
}

/// How much of a file is rendered.
package enum RenderLayout: Sendable, Equatable {
    case full
    /// Only the hunks, with `context` rows around each change and the user's revealed rows. A file without a change
    /// has no hunk, so it shows nothing, unless `wholeWhenUnchanged`: then it shows every row, as `full` does.
    case changes(context: Int, expansions: [GapKey: GapExpansion], wholeWhenUnchanged: Bool = false)
}

/// A file's diff and tokens, computed once per selection so re-layouts (gap drags, layout toggles) stay cheap.
package final class PreparedDiff: Sendable {
    /// Tells this preparation apart from every other, for what is kept per preparation of a side without a blob id.
    package let id = UUID()
    package let title: String
    package let model: DiffModel
    /// Each side's lexical tokens per line, in UTF-16 offsets from the line's start, ready to place on a row.
    package let oldTokens: LineTokens
    package let newTokens: LineTokens
    /// The two sides' texts and their language, which the tiers after the lexer read (PERF-11).
    package let oldText: String
    package let newText: String
    package let language: Language

    package init(
        _ input: FileDiffInput, granularity: IntralineGranularity, heuristics: DiffHeuristics = DiffHeuristics()
    ) {
        title = input.title
        oldText = input.oldText
        newText = input.newText
        language = input.language
        model = DiffModel(
            oldText: input.oldText, newText: input.newText, granularity: granularity, language: input.language,
            pipeline: DiffPipeline(heuristics: heuristics), tokenRanges: SwiftSyntaxTokenRanges())
        oldTokens = DiffRenderer.tokensByLine(text: input.oldText, lines: model.oldLines, language: input.language)
        newTokens = DiffRenderer.tokensByLine(text: input.newText, lines: model.newLines, language: input.language)
    }
}

package struct FileDiffInput: Sendable {
    package let title: String
    package let oldText: String
    package let newText: String
    package let language: Language

    package init(title: String, oldText: String, newText: String, language: Language) {
        self.title = title
        self.oldText = oldText
        self.newText = newText
        self.language = language
    }
}

/// One pane's text with the per-row metadata the layout delegate and the gutter need.
/// Immutable after construction, so it is safe to build off the main actor and hand over.
package final class RenderedText: @unchecked Sendable {
    package let id = UUID()
    package let side: RenderedSide
    package let palette: DiffPalette
    package let attributed: NSAttributedString
    package let rows: [RowMeta]
    /// The gaps between rows, in ascending boundary order.
    package let gaps: [RenderedGap]
    /// UTF-16 offset of each row's first unit, ascending.
    package let lineStarts: [Int]
    /// Character cells of the longest row, tabs counted as four, for sizing an unwrapped pane.
    package let longestLine: Int
    /// How far the glyphs are raised when drawn, to centre them in a line taller than they need. Everything that
    /// draws with the text, the gutter's line numbers above all, moves by the same amount.
    package let baselineOffset: CGFloat
    /// The height of one row, the font's own line height once the chosen multiple is applied.
    package let lineHeight: CGFloat
    /// The bands between two rows, which the text holds as paragraph spacing.
    private let bandsBetweenRows: Int

    package init(
        side: RenderedSide, palette: DiffPalette, attributed: NSAttributedString, rows: [RowMeta],
        gaps: [RenderedGap], lineStarts: [Int], longestLine: Int, baselineOffset: CGFloat = 0,
        lineHeight: CGFloat? = nil
    ) {
        self.side = side
        self.palette = palette
        self.attributed = attributed
        self.rows = rows
        self.gaps = gaps
        self.lineStarts = lineStarts
        self.longestLine = longestLine
        self.baselineOffset = baselineOffset
        self.lineHeight = lineHeight ?? palette.defaultLineHeight
        bandsBetweenRows = gaps.count(where: { $0.hasBand && $0.boundary > 0 && $0.boundary < rows.count })
    }

    /// The height of the empty band a gap takes on its boundary (book DIFF-02): exactly one row, whatever it holds.
    package static func gapBandHeight(lineHeight: CGFloat) -> CGFloat {
        lineHeight
    }

    /// ``gapBandHeight(lineHeight:)`` for this text's rows.
    package var gapBandHeight: CGFloat {
        Self.gapBandHeight(lineHeight: lineHeight)
    }

    /// The band of a gap above the first row. A view keeps it as space above the text: TextKit ignores the spacing
    /// before a text's first paragraph.
    package var bandAbove: CGFloat {
        guard let first = gaps.first, first.boundary == 0, first.hasBand, !rows.isEmpty else { return 0 }
        return gapBandHeight
    }

    /// The band of a gap below the last row. A view keeps it as space below the text: TextKit ignores the spacing
    /// after a text's last paragraph.
    package var bandBelow: CGFloat {
        guard let last = gaps.last, last.boundary == rows.count, last.hasBand, !rows.isEmpty else { return 0 }
        return gapBandHeight
    }

    /// The gap whose band lies between `row` and the next row, which the text holds as `row`'s paragraph spacing.
    /// - Complexity: O(log gaps)
    package func bandedGap(afterRow row: Int) -> RenderedGap? {
        guard row >= 0, row + 1 < rows.count else { return nil }
        return gaps(on: (row + 1) ... (row + 1)).first(where: \.hasBand)
    }

    /// The band between `row` and the next row; zero when no gap with a band lies between them.
    /// - Complexity: O(log gaps)
    package func bandSpacing(afterRow row: Int) -> CGFloat {
        bandedGap(afterRow: row) == nil ? 0 : gapBandHeight
    }

    /// The height TextKit lays the rows out at without wrapping, with the bands between them: one line per row.
    package var unwrappedTextHeight: CGFloat {
        CGFloat(max(rows.count, 1)) * lineHeight + CGFloat(bandsBetweenRows) * gapBandHeight
    }

    /// The largest line number shown, which sizes the gutter; rows can be few while numbers are large.
    package var maximumLineNumber: Int {
        rows.reduce(0) { max($0, $1.oldNumber ?? 0, $1.newNumber ?? 0) }
    }

    /// Width an unwrapped pane needs to show every row in full.
    package var unwrappedWidth: CGFloat {
        CGFloat(longestLine) * ("0" as NSString).size(withAttributes: [.font: palette.font]).width + 2
            * DiffPaneMetrics.lineFragmentPadding
    }

    /// The row a UTF-16 offset falls in, or nil for an empty side, which TextKit still lays out as one fragment.
    package func row(containing offset: Int) -> RowMeta? {
        rows.isEmpty ? nil : rows[rowIndex(containing: offset)]
    }

    /// - Complexity: O(log rows)
    package func rowIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= offset { low = middle + 1 } else { high = middle }
        }
        return max(low - 1, 0)
    }

    /// The gaps on the boundaries in `boundaries`, in order.
    /// - Complexity: O(log gaps)
    package func gaps(on boundaries: ClosedRange<Int>) -> ArraySlice<RenderedGap> {
        var low = 0
        var high = gaps.count
        while low < high {
            let middle = (low + high) / 2
            if gaps[middle].boundary < boundaries.lowerBound { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < gaps.count, gaps[end].boundary <= boundaries.upperBound { end += 1 }
        return gaps[low ..< end]
    }
}

package struct RenderedDiff: Identifiable, Sendable {
    package let id = UUID()
    /// Only the sides the current layout shows are rendered; the others are nil.
    package let unified: RenderedText?
    package let old: RenderedText?
    package let new: RenderedText?
    package let unifiedChangeStarts: [Int]
    package let splitChangeStarts: [Int]
    package let changeCount: Int
    /// Lines added and removed, whatever the layout shows.
    package let addedLines: Int
    package let removedLines: Int
    /// Several files rendered one after another, each introduced by a header row.
    package let isCombined: Bool
    /// Re-renders of the same selection keep the pane where it was.
    package var keepsScrollPosition = false
}
