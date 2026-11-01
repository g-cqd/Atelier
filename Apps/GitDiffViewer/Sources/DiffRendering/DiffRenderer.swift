import AppKit
package import DiffCore
import DiffGit
import Foundation

package enum DiffRenderer {
    package struct Options: Sendable {
        package var granularity: IntralineGranularity = .word
        package var palette: DiffPalette = .system
        package var lineHeightMultiple: Double = 0
        /// Sides to render; the inline layout needs only `.unified`, the split layouts only `.old` and `.new`.
        package var sides: Set<RenderedSide> = [.unified, .old, .new]
        /// Whether the inline side shows the new file with each change folded into it, but for the changes in
        /// ``disclosedChanges`` (book DIFF-04).
        package var compactsInline = false
        /// The changes a compact inline side shows whole.
        package var disclosedChanges: Set<ChangeKey> = []
        /// The folded scopes, each with its last line on its side (DIFF-03): folded after the compact view and the gaps.
        package var foldedScopes: [ScopeFoldKey: Int] = [:]

        package init(
            granularity: IntralineGranularity = .word,
            palette: DiffPalette = .system,
            lineHeightMultiple: Double = 0,
            sides: Set<RenderedSide> = [.unified, .old, .new],
            compactsInline: Bool = false,
            disclosedChanges: Set<ChangeKey> = [],
            foldedScopes: [ScopeFoldKey: Int] = [:]
        ) {
            self.foldedScopes = foldedScopes
            self.granularity = granularity
            self.palette = palette
            self.lineHeightMultiple = lineHeightMultiple
            self.sides = sides
            self.compactsInline = compactsInline
            self.disclosedChanges = disclosedChanges
        }
    }

    package static func render(
        oldText: String,
        newText: String,
        language: Language,
        granularity: IntralineGranularity = .word,
        palette: DiffPalette = .system,
        lineHeightMultiple: Double = 0,
        layout: RenderLayout = .full
    ) -> RenderedDiff {
        let options = Options(granularity: granularity, palette: palette, lineHeightMultiple: lineHeightMultiple)
        let prepared = PreparedDiff(
            FileDiffInput(title: "", oldText: oldText, newText: newText, language: language),
            granularity: granularity
        )
        return render(prepared: [prepared], options: options, layout: layout, withHeaders: false)
    }

    /// Renders prepared files one after another; with headers each file is introduced by a row with its title.
    /// Gap keys count files from `firstFileIndex`, so files rendered separately keep distinct keys.
    package static func render(
        prepared: [PreparedDiff],
        options: Options,
        layout: RenderLayout,
        withHeaders: Bool,
        firstFileIndex: Int = 0
    ) -> RenderedDiff {
        var unifiedRows: [RenderRow] = []
        var splitRows: [RenderRow] = []
        // The rows before scopes fold, which the change starts are counted on.
        var unifiedOpen: [RenderRow] = []
        var splitOpen: [RenderRow] = []
        var changeCount = 0
        var addedLines = 0
        var removedLines = 0
        for (offset, file) in prepared.enumerated() {
            let index = firstFileIndex + offset
            let header = withHeaders ? file.title : nil
            // The compact view folds its changes, the layout cuts hunks and gaps, and folded scopes hide what they cover.
            let unified =
                options.compactsInline
                ? compactRows(
                    of: file,
                    fileIndex: index,
                    layout: layout,
                    header: header,
                    disclosed: options.disclosedChanges
                )
                : rows(of: file, fileIndex: index, layout: layout, header: header, split: false)
            let split = rows(of: file, fileIndex: index, layout: layout, header: header, split: true)
            unifiedOpen += unified
            splitOpen += split
            unifiedRows += folding(unified, of: file, fileIndex: index, folds: options.foldedScopes)
            splitRows += folding(split, of: file, fileIndex: index, folds: options.foldedScopes)
            changeCount += file.model.unifiedChangeStarts.count
            for row in file.model.unifiedRows {
                if row.kind == .added { addedLines += 1 }
                if row.kind == .removed { removedLines += 1 }
            }
        }
        return RenderedDiff(
            unified: options.sides.contains(.unified)
                ? render(rows: unifiedRows, side: .unified, options: options) : nil,
            old: options.sides.contains(.old) ? render(rows: splitRows, side: .old, options: options) : nil,
            new: options.sides.contains(.new) ? render(rows: splitRows, side: .new, options: options) : nil,
            unifiedChangeStarts: foldedStarts(changeStarts(in: unifiedOpen), through: unifiedRows),
            splitChangeStarts: foldedStarts(changeStarts(in: splitOpen), through: splitRows),
            changeCount: changeCount,
            addedLines: addedLines,
            removedLines: removedLines,
            isCombined: withHeaders
        )
    }

    /// Convenience for tests and callers holding raw inputs.
    package static func renderCombined(
        files: [FileDiffInput],
        options: Options = Options(),
        context: Int,
        expansions: [GapKey: GapExpansion]
    ) -> RenderedDiff {
        let prepared = files.map { PreparedDiff($0, granularity: options.granularity) }
        return render(
            prepared: prepared,
            options: options,
            layout: .changes(context: context, expansions: expansions),
            withHeaders: true
        )
    }

    // MARK: Row selection

    enum RenderRow {
        case diff(DiffRow, fileIndex: Int, file: PreparedDiff)
        /// An added line of a folded change, shown as the new file reads (book DIFF-04).
        case folded(DiffRow, fileIndex: Int, file: PreparedDiff)
        /// A change of a compact inline side, which takes no row: the rows after it are its own.
        case change(PendingChange)
        case gap(GapMarker)
        case header(String, fileIndex: Int)
        /// A folded scope's band, in place of the rows it hides (DIFF-03).
        case scopeFold(ScopeFoldBand, fileIndex: Int)
    }

    /// The rows of a file for a layout: everything, or hunks separated by gaps. Gap `i` precedes hunk `i`.
    private static func rows(of file: PreparedDiff, fileIndex: Int, layout: RenderLayout, header: String?, split: Bool)
        -> [RenderRow]
    {
        var rows: [RenderRow] = []
        if let header { rows.append(.header(header, fileIndex: fileIndex)) }
        let all = split ? file.model.splitRows : file.model.unifiedRows
        switch layout {
            case .full:
                rows += all.map { .diff($0, fileIndex: fileIndex, file: file) }
            case .changes(let context, let expansions, let wholeWhenUnchanged):
                let changeRanges = split ? file.model.splitChangeRanges : file.model.unifiedChangeRanges
                if wholeWhenUnchanged, changeRanges.isEmpty {
                    rows += all.map { .diff($0, fileIndex: fileIndex, file: file) }
                    return rows
                }
                let fileExpansions = Dictionary(
                    uniqueKeysWithValues: expansions.filter { $0.key.fileIndex == fileIndex }
                        .map { ($0.key.gapIndex, $0.value) }
                )
                let layout = HunkLayout.layout(
                    changeRanges: changeRanges,
                    rowCount: all.count,
                    context: context,
                    expansions: fileExpansions
                )
                var cursor = 0
                // Gap keys follow the base hunks, so a gap keeps its key when an expansion merges hunks around it.
                for hunk in layout.hunks {
                    if hunk.rows.lowerBound > cursor {
                        rows.append(
                            .gap(
                                GapMarker(
                                    key: GapKey(fileIndex: fileIndex, gapIndex: hunk.firstBase),
                                    hiddenRows: hunk.rows.lowerBound - cursor,
                                    isLeading: hunk.firstBase == 0,
                                    isTrailing: false
                                )
                            )
                        )
                    }
                    rows += all[hunk.rows].map { .diff($0, fileIndex: fileIndex, file: file) }
                    cursor = hunk.rows.upperBound
                }
                if cursor < all.count {
                    rows.append(
                        .gap(
                            GapMarker(
                                key: GapKey(fileIndex: fileIndex, gapIndex: layout.baseCount),
                                hiddenRows: all.count - cursor,
                                isLeading: layout.hunks.isEmpty,
                                isTrailing: true
                            )
                        )
                    )
                }
        }
        return rows
    }

    // MARK: Attributed text

    private static func render(rows: [RenderRow], side: RenderedSide, options: Options) -> RenderedText {
        var text = ""
        var metas: [RowMeta] = []
        var gaps: [RenderedGap] = []
        var changes: [RenderedChange] = []
        var folds: [RenderedFold] = []
        var lineStarts: [Int] = []
        var placeholders = BidiControls.Placeholders()
        metas.reserveCapacity(rows.count)
        lineStarts.reserveCapacity(rows.count)

        var offset = 0
        var longestLine = 0
        for row in rows {
            var length = 0
            var tabs = 0
            switch row {
                case .change(let change):
                    changes.append(change.rendered(from: metas.count))
                    continue
                case .folded(let diffRow, let fileIndex, let file):
                    // The line as the new file reads: no tint and no emphasis, numbered on the new side alone.
                    if let line = shownLine(of: diffRow, in: file, side: side) {
                        (length, tabs) = appendShown(line, at: offset, to: &text, placeholders: &placeholders)
                    }
                    metas.append(meta(of: diffRow, kind: .context, numbersOld: false, fileIndex: fileIndex))
                case .diff(let diffRow, let fileIndex, let file):
                    let line = shownLine(of: diffRow, in: file, side: side)
                    if let line {
                        (length, tabs) = appendShown(line, at: offset, to: &text, placeholders: &placeholders)
                    }
                    let kind = displayedKind(of: diffRow, side: side, hasLine: line != nil)
                    metas.append(meta(of: diffRow, kind: kind, numbersOld: true, fileIndex: fileIndex))
                case .gap(let marker):
                    // The rows it hides take none of their own: the gap lies on the boundary between the rows
                    // around them (book DIFF-02).
                    gaps.append(RenderedGap(boundary: metas.count, marker: marker))
                    continue
                case .header(let title, let fileIndex):
                    (length, tabs) = appendShown(Substring(title), at: offset, to: &text, placeholders: &placeholders)
                    metas.append(RowMeta(kind: .header, oldNumber: nil, newNumber: nil, fileIndex: fileIndex))
                case .scopeFold(let band, let fileIndex):
                    let shown = band.text(on: side)
                    (length, tabs) = appendShown(
                        Substring(shown.text),
                        at: offset,
                        to: &text,
                        placeholders: &placeholders
                    )
                    folds.append(fold(band, marker: shown.marker, at: offset, row: metas.count))
                    metas.append(RowMeta(kind: .context, oldNumber: nil, newNumber: nil, fileIndex: fileIndex))
            }
            text.append("\n")
            lineStarts.append(offset)
            // Counted on the row as it was appended: re-slicing the accumulated text was quadratic once it held a
            // non-ASCII character.
            longestLine = max(longestLine, length + 3 * tabs)
            offset += length + 1
        }
        if text.hasSuffix("\n") {
            text.removeLast()
        }

        let styled = attributed(
            text,
            placeholders: placeholders,
            metas: metas,
            lineStarts: lineStarts,
            options: options
        )
        styleFoldMarkers(folds, palette: options.palette, in: styled.attributed)
        addBands(of: gaps, lineStarts: lineStarts, lineHeight: styled.lineHeight, to: styled.attributed)
        return RenderedText(
            side: side,
            palette: options.palette,
            attributed: styled.attributed,
            rows: metas,
            gaps: gaps,
            lineStarts: lineStarts,
            longestLine: longestLine,
            baselineOffset: styled.baselineOffset,
            lineHeight: styled.lineHeight,
            changes: changes,
            folds: folds
        )
    }
}

extension DiffRenderer {
    /// Output indices of the first row of each run of changed rows. A compact inline side's changes start where they
    /// lie, a folded removal at the row after it, or at the last row below the last.
    private static func changeStarts(in rows: [RenderRow]) -> [Int] {
        let isCompact = rows.contains { row in
            if case .change = row { true } else { false }
        }
        if isCompact { return compactChangeStarts(in: rows) }
        var starts: [Int] = []
        var inChange = false
        var index = 0
        for row in rows {
            let isChange: Bool
            switch row {
                case .diff(let diff, _, _): isChange = diff.kind != .context
                case .header, .folded, .change, .scopeFold: isChange = false
                case .gap:
                    // A gap takes no row, but the changes on either side of it are still two.
                    inChange = false
                    continue
            }
            if isChange, !inChange { starts.append(index) }
            inChange = isChange
            index += 1
        }
        return starts
    }
}

extension DiffRenderer {
    /// Where each of `lines` lies in `text`, in UTF-8 bytes, without its line break.
    ///
    /// Each line starts where it sits in the text. A CRLF line's `\r` is in the text but not in the line, so the walk
    /// steps over it; a sum of the lines' lengths alone would put every later line one byte early. A line ends where its
    /// own text does: a token that runs into the `\r` or the newline after it, such as a comment or an unterminated
    /// string, stops at the line's last character.
    /// - Parameters:
    ///   - text: One side of the diff.
    ///   - lines: `text`'s lines in order, as `DiffModel.lines(of:)` cuts them.
    /// - Returns: One range per line, ascending and disjoint.
    /// - Complexity: O(lines)
    package static func lineRanges(of text: String, lines: [Substring]) -> [Range<Int>] {
        let utf8 = text.utf8Span
        let bytes = utf8.span
        var lineRanges: [Range<Int>] = []
        lineRanges.reserveCapacity(lines.count)
        var start = 0
        for line in lines {
            let end = start + line.utf8.count
            lineRanges.append(start ..< end)
            start = end
            if start < bytes.count, bytes[start] == UInt8(ascii: "\r") { start += 1 }
            start += 1
        }
        return lineRanges
    }
}
