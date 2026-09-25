package import AtelierHighlighting
import AtelierSwiftSyntax
package import DiffCore
import Foundation

/// What is drawn over one rendered file's plain text once the stages after the text land (PERF-09 stages 1 and 2):
/// each side's syntax colour, in layers, each side's intraline emphasis, and the lines that only moved. Everything is
/// kept by source line, so a file rendered again, relaid out or with a gap revealed, keeps it.
///
/// A pane draws it without laying anything out again: colour through TextKit's rendering attributes, emphasis and the
/// moved rows' background when a row's fragment draws (`DecorationStore`). What has not landed stays plain.
package struct DiffDecorations: Sendable {
    /// One side's decorations.
    package struct Side: Sendable {
        /// The colour layers of each source line, in UTF-16 offsets from the line's start; nil until a tier lands.
        package var colors: LayeredLineTokens?
        /// The emphasis of each compared source line, in UTF-16 offsets from the line's start.
        package var emphasis: [Int: [Range<Int>]] = [:]

        package init(colors: LayeredLineTokens? = nil, emphasis: [Int: [Range<Int>]] = [:]) {
            self.colors = colors
            self.emphasis = emphasis
        }
    }

    package var old = Side()
    package var new = Side()
    /// The lines that only moved; nil until the moved blocks are found, or when the diff does not look for them.
    package var moved: MovedLines?
    /// Changes whenever either side's colour changes, so a pane knows at once whether to colour its rows again.
    package var colorVersion = 0
    /// Changes whenever the emphasis or the moved lines change, so a pane knows whether to redraw its rows.
    package var markVersion = 0

    package init(
        old: Side = Side(), new: Side = Side(), moved: MovedLines? = nil, colorVersion: Int = 0, markVersion: Int = 0
    ) {
        self.old = old
        self.new = new
        self.moved = moved
        self.colorVersion = colorVersion
        self.markVersion = markVersion
    }

    /// The source line `row` shows on a pane of `side`, and which side's it is; nil for a row that shows no source line.
    /// A unified row shows its new line, or its old one when it has no new line.
    private func line(of row: RowMeta, on side: RenderedSide) -> (side: Side, index: Int)? {
        guard row.kind != .filler, row.kind != .header else { return nil }
        let number: (isOld: Bool, number: Int?) =
            switch side {
                case .old: (true, row.oldNumber)
                case .new: (false, row.newNumber)
                case .unified: row.newNumber != nil ? (false, row.newNumber) : (true, row.oldNumber)
            }
        return number.number.map { (number.isOld ? old : new, $0 - 1) }
    }

    /// The colour tokens of the source line `row` shows on a pane of `side`; nil for a row that shows no source line, or
    /// one no tier has reached, which stays plain.
    /// - Complexity: O(the line's tokens), the per-line merge.
    package func tokens(of row: RowMeta, on side: RenderedSide) -> [LineToken]? {
        guard let line = line(of: row, on: side) else { return nil }
        return line.side.colors?.merged(line: line.index)
    }

    /// The emphasis of the changed line `row` shows on a pane of `side`: the old line's on a removed row, the new line's
    /// on an added one; none on any other row.
    package func emphasis(of row: RowMeta, on side: RenderedSide) -> [Range<Int>] {
        guard row.kind == .removed || row.kind == .added else { return [] }
        let index: Int? =
            switch side {
                case .old: row.oldNumber
                case .new: row.newNumber
                case .unified: row.kind == .removed ? row.oldNumber : row.newNumber
            }
        guard let index else { return [] }
        return ((side == .old || side == .unified && row.kind == .removed) ? old : new).emphasis[index - 1] ?? []
    }

    /// Whether `row` shows a change that only moved. A row that pairs two lines, as a split row of a modified pair does,
    /// is moved only when both are: otherwise it reads as a change.
    package func isMoved(_ row: RowMeta) -> Bool {
        guard let moved, row.kind != .context, row.kind != .filler, row.kind != .header else { return false }
        let old = row.oldNumber.map { $0 - 1 }.map { moved.old.indices.contains($0) && moved.old[$0] }
        let new = row.newNumber.map { $0 - 1 }.map { moved.new.indices.contains($0) && moved.new[$0] }
        switch (old, new) {
            case (.some(let old), .some(let new)): return old && new
            case (.some(let old), nil): return old
            case (nil, .some(let new)): return new
            case (nil, nil): return false
        }
    }
}

extension DiffDecorations {
    /// The tiers that colour a displayed side (PERF-11): the lexer, tier 0, on every language it knows, and swift-syntax
    /// on Swift sides (D33), reading and filling `store` when given one, so a side the intraline diff or hover parsed is
    /// not parsed again.
    package static func tiers(store: SyntaxFactsStore? = nil) -> [any AtelierHighlighting.HighlightTier] {
        [LexicalTier(), SwiftSyntaxTier(store: store)]
    }
}
