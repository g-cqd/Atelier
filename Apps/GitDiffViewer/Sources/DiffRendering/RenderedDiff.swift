package import AppKit
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

package struct RowMeta: Sendable {
    package let kind: RowKind
    package let oldNumber: Int?
    package let newNumber: Int?
    package var fileIndex = 0
    package var gap: GapMarker?
    /// The line only moved; drawn in a calmer colour than a real change.
    package var isMoved = false
}

/// How much of a file is rendered.
package enum RenderLayout: Sendable, Equatable {
    case full
    /// Only the hunks, with `context` rows around each change and the user's revealed rows.
    case changes(context: Int, expansions: [GapKey: GapExpansion])
}

/// A file's diff and tokens, computed once per selection so re-layouts (gap drags, layout toggles) stay cheap.
package final class PreparedDiff: Sendable {
    package let title: String
    package let model: DiffModel
    package let oldTokens: [[Token]]
    package let newTokens: [[Token]]

    package init(
        _ input: FileDiffInput, granularity: IntralineGranularity, heuristics: DiffHeuristics = DiffHeuristics()
    ) {
        title = input.title
        model = DiffModel(
            oldText: input.oldText, newText: input.newText, granularity: granularity, language: input.language,
            pipeline: DiffPipeline(heuristics: heuristics), tokenizer: SwiftSyntaxTokenRanges())
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
    /// UTF-16 offset of each row's first unit, ascending.
    package let lineStarts: [Int]
    /// Character cells of the longest row, tabs counted as four, for sizing an unwrapped pane.
    package let longestLine: Int
    /// How far the glyphs are raised when drawn, to centre them in a line taller than they need. Everything that
    /// draws with the text, the gutter's line numbers above all, moves by the same amount.
    package let baselineOffset: CGFloat
    /// The height of one row, the font's own line height once the chosen multiple is applied.
    package let lineHeight: CGFloat

    package init(
        side: RenderedSide, palette: DiffPalette, attributed: NSAttributedString, rows: [RowMeta], lineStarts: [Int],
        longestLine: Int, baselineOffset: CGFloat = 0, lineHeight: CGFloat? = nil
    ) {
        self.side = side
        self.palette = palette
        self.attributed = attributed
        self.rows = rows
        self.lineStarts = lineStarts
        self.longestLine = longestLine
        self.baselineOffset = baselineOffset
        self.lineHeight = lineHeight ?? palette.defaultLineHeight
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
