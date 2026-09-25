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

/// Identifies a change of one file in a rendered document: its place among the file's changes in the inline layout
/// (book DIFF-04). A reload keeps it for the change at the same place.
package struct ChangeKey: Hashable, Sendable {
    package let fileIndex: Int
    package let changeIndex: Int

    package init(fileIndex: Int, changeIndex: Int) {
        self.fileIndex = fileIndex
        self.changeIndex = changeIndex
    }
}

/// A change where the compact inline view shows it (book DIFF-04): folded into the new file's lines, or disclosed as
/// the inline view shows it, with the gutter marker that switches between the two.
package struct RenderedChange: Sendable, Hashable {
    package enum Kind: Sendable, Hashable {
        /// Adds lines and removes none.
        case added
        /// Removes lines and adds none.
        case removed
        /// Removes lines and adds others.
        case modified
    }

    package let key: ChangeKey
    package let kind: Kind
    /// The rows it takes: its added rows while folded, its removed and added rows while disclosed. A folded removal
    /// takes none, and lies on the boundary above `rows.lowerBound`, which is `rows.count` below the last row.
    package let rows: Range<Int>
    package let isDisclosed: Bool
    package let removedLines: Int
    package let addedLines: Int

    package init(
        key: ChangeKey, kind: Kind, rows: Range<Int>, isDisclosed: Bool, removedLines: Int, addedLines: Int
    ) {
        self.key = key
        self.kind = kind
        self.rows = rows
        self.isDisclosed = isDisclosed
        self.removedLines = removedLines
        self.addedLines = addedLines
    }

    /// What its marker's tooltip says: the change, and what a click does.
    package var help: String {
        func lines(_ count: Int) -> String { "\(count) \(count == 1 ? "line" : "lines")" }
        let change =
            switch kind {
                case .added: "Added: \(lines(addedLines))"
                case .removed: "Removed: \(lines(removedLines))"
                case .modified: "Modified: \(lines(removedLines)) removed, \(addedLines) added"
            }
        return "\(change). Click to \(isDisclosed ? "hide" : "show") the change (⌥⌘↩)"
    }
}

package struct RowMeta: Sendable {
    package let kind: RowKind
    package let oldNumber: Int?
    package let newNumber: Int?
    package var fileIndex = 0
}

/// How much of a file is rendered.
package enum RenderLayout: Sendable, Equatable {
    case full
    /// Only the hunks, with `context` rows around each change and the user's revealed rows. A file without a change
    /// has no hunk, so it shows nothing, unless `wholeWhenUnchanged`: then it shows every row, as `full` does.
    case changes(context: Int, expansions: [GapKey: GapExpansion], wholeWhenUnchanged: Bool = false)
}

/// A file's diff as the first stage leaves it (PERF-09 stage 0): the rows of its two sides and each change's pairs,
/// which is all a text needs to be drawn, computed once per selection so re-layouts (gap drags, layout toggles) stay
/// cheap. Its decorations, the colour of each side and each pair's emphasis and the moved lines, come after the text,
/// from what this keeps (`DiffDecorations`).
package final class PreparedDiff: Sendable {
    /// Tells this preparation apart from every other, for what is kept per preparation of a side without a blob id.
    package let id = UUID()
    package let title: String
    /// The diff's first phase: its structure, rows and pairs, with neither emphasis nor moved lines.
    package let model: DiffModel
    /// The two sides' texts and their language, which the decorating stages read.
    package let oldText: String
    package let newText: String
    package let language: Language
    /// How finely a pair's lines are compared, and the diff's stages, for the emphasis that comes after the text.
    package let granularity: IntralineGranularity
    package let pipeline: DiffPipeline
    /// The syntax granularity's token boundaries, read from the syntax facts store when a side has a revision.
    private let tokenRanges: SwiftSyntaxTokenRanges

    /// - Parameters:
    ///   - input: The two sides, their language and their revisions.
    ///   - granularity: How finely changed lines are compared.
    ///   - heuristics: The diff's heuristics.
    ///   - store: Where a side with a revision finds the facts of a parse another reader made, and leaves its own
    ///     (PERF-11 step 3); nil parses a Swift side for its syntax granularity alone.
    package init(
        _ input: FileDiffInput, granularity: IntralineGranularity, heuristics: DiffHeuristics = DiffHeuristics(),
        store: SyntaxFactsStore? = nil
    ) {
        title = input.title
        oldText = input.oldText
        newText = input.newText
        language = input.language
        self.granularity = granularity
        pipeline = DiffPipeline(heuristics: heuristics)
        model = DiffModel(structureOf: input.oldText, newText: input.newText, pipeline: pipeline)
        tokenRanges = Self.tokenRanges(for: input, store: store)
    }

    /// Where the syntax granularity reads each side's token boundaries.
    package var tokenSource: SyntaxTokenSource {
        SyntaxTokenSource(provider: tokenRanges, language: language, oldText: oldText, newText: newText)
    }

    /// The syntax granularity's provider: one that reads each side's facts from `store` when the side has a revision.
    private static func tokenRanges(for input: FileDiffInput, store: SyntaxFactsStore?) -> SwiftSyntaxTokenRanges {
        guard let store, input.oldRevision != nil || input.newRevision != nil else { return SwiftSyntaxTokenRanges() }
        let old = (text: input.oldText, revision: input.oldRevision)
        let new = (text: input.newText, revision: input.newRevision)
        return SwiftSyntaxTokenRanges(store: store) { text, _ in
            // The diff asks about the very strings it was given, so the comparison finds them equal at once.
            if text == old.text { return old.revision }
            return text == new.text ? new.revision : nil
        }
    }
}

package struct FileDiffInput: Sendable {
    package let title: String
    package let oldText: String
    package let newText: String
    package let language: Language
    /// What each side's content is, when its blob id is known: the key its facts are kept under.
    package let oldRevision: SourceRevision?
    package let newRevision: SourceRevision?

    package init(
        title: String, oldText: String, newText: String, language: Language, oldRevision: SourceRevision? = nil,
        newRevision: SourceRevision? = nil
    ) {
        self.title = title
        self.oldText = oldText
        self.newText = newText
        self.language = language
        self.oldRevision = oldRevision
        self.newRevision = newRevision
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
    /// The changes the compact inline view marks, in row order; none in any other view (book DIFF-04).
    package let changes: [RenderedChange]
    /// The bands between two rows, which the text holds as paragraph spacing.
    private let bandsBetweenRows: Int

    package init(
        side: RenderedSide, palette: DiffPalette, attributed: NSAttributedString, rows: [RowMeta],
        gaps: [RenderedGap], lineStarts: [Int], longestLine: Int, baselineOffset: CGFloat = 0,
        lineHeight: CGFloat? = nil, changes: [RenderedChange] = []
    ) {
        self.changes = changes
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

    /// The changes whose rows, or whose boundary for a folded removal, lie within `boundaries`, in order: a change
    /// over rows `a ..< b` spans the boundaries `a ... b`.
    /// - Complexity: O(log changes + changes returned)
    package func changes(on boundaries: ClosedRange<Int>) -> ArraySlice<RenderedChange> {
        var low = 0
        var high = changes.count
        while low < high {
            let middle = (low + high) / 2
            if changes[middle].rows.upperBound < boundaries.lowerBound { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < changes.count, changes[end].rows.lowerBound <= boundaries.upperBound { end += 1 }
        return changes[low ..< end]
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
