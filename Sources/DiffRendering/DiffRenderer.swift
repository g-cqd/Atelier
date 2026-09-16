import AppKit
package import DiffCore
import DiffGit
package import Foundation

package enum DiffRenderer {
    package struct Options: Sendable {
        package var granularity: IntralineGranularity = .word
        package var palette: DiffPalette = .system
        package var lineHeightMultiple: Double = 0
        /// Sides to render; the inline layout needs only `.unified`, the split layouts only `.old` and `.new`.
        package var sides: Set<RenderedSide> = [.unified, .old, .new]

        package init(
            granularity: IntralineGranularity = .word, palette: DiffPalette = .system, lineHeightMultiple: Double = 0,
            sides: Set<RenderedSide> = [.unified, .old, .new]
        ) {
            self.granularity = granularity
            self.palette = palette
            self.lineHeightMultiple = lineHeightMultiple
            self.sides = sides
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
            FileDiffInput(title: "", oldText: oldText, newText: newText, language: language), granularity: granularity)
        return render(prepared: [prepared], options: options, layout: layout, withHeaders: false)
    }

    /// Renders prepared files one after another; with headers each file is introduced by a row with its title.
    /// Gap keys count files from `firstFileIndex`, so files rendered separately keep distinct keys.
    package static func render(
        prepared: [PreparedDiff], options: Options, layout: RenderLayout, withHeaders: Bool, firstFileIndex: Int = 0
    ) -> RenderedDiff {
        var unifiedRows: [RenderRow] = []
        var splitRows: [RenderRow] = []
        var changeCount = 0
        var addedLines = 0
        var removedLines = 0
        for (offset, file) in prepared.enumerated() {
            let index = firstFileIndex + offset
            let header = withHeaders ? file.title : nil
            unifiedRows += rows(of: file, fileIndex: index, layout: layout, header: header, split: false)
            splitRows += rows(of: file, fileIndex: index, layout: layout, header: header, split: true)
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
            unifiedChangeStarts: changeStarts(in: unifiedRows),
            splitChangeStarts: changeStarts(in: splitRows),
            changeCount: changeCount,
            addedLines: addedLines,
            removedLines: removedLines,
            isCombined: withHeaders
        )
    }

    /// Convenience for tests and callers holding raw inputs.
    package static func renderCombined(
        files: [FileDiffInput], options: Options = Options(), context: Int, expansions: [GapKey: GapExpansion]
    ) -> RenderedDiff {
        let prepared = files.map { PreparedDiff($0, granularity: options.granularity) }
        return render(
            prepared: prepared, options: options, layout: .changes(context: context, expansions: expansions),
            withHeaders: true)
    }

    // MARK: Row selection

    private enum RenderRow {
        case diff(DiffRow, fileIndex: Int, file: PreparedDiff)
        case gap(GapMarker)
        case header(String, fileIndex: Int)
    }

    /// The rows of a file for a layout: everything, or hunks separated by gap rows. Gap `i` precedes hunk `i`.
    private static func rows(of file: PreparedDiff, fileIndex: Int, layout: RenderLayout, header: String?, split: Bool)
        -> [RenderRow]
    {
        var rows: [RenderRow] = []
        if let header { rows.append(.header(header, fileIndex: fileIndex)) }
        let all = split ? file.model.splitRows : file.model.unifiedRows
        switch layout {
            case .full:
                rows += all.map { .diff($0, fileIndex: fileIndex, file: file) }
            case .changes(let context, let expansions):
                let fileExpansions = Dictionary(
                    uniqueKeysWithValues: expansions.filter { $0.key.fileIndex == fileIndex }
                        .map { ($0.key.gapIndex, $0.value) })
                let changeRanges = split ? file.model.splitChangeRanges : file.model.unifiedChangeRanges
                let layout = HunkLayout.layout(
                    changeRanges: changeRanges, rowCount: all.count, context: context, expansions: fileExpansions)
                var cursor = 0
                // Gap keys follow the base hunks, so a gap keeps its key when an expansion merges hunks around it.
                for hunk in layout.hunks {
                    if hunk.rows.lowerBound > cursor {
                        rows.append(
                            .gap(
                                GapMarker(
                                    key: GapKey(fileIndex: fileIndex, gapIndex: hunk.firstBase),
                                    hiddenRows: hunk.rows.lowerBound - cursor,
                                    isLeading: hunk.firstBase == 0, isTrailing: false
                                )))
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
                                isLeading: layout.hunks.isEmpty, isTrailing: true
                            )))
                }
        }
        return rows
    }

    /// Output indices of the first row of each run of changed rows.
    private static func changeStarts(in rows: [RenderRow]) -> [Int] {
        var starts: [Int] = []
        var inChange = false
        for (index, row) in rows.enumerated() {
            let isChange = if case .diff(let diff, _, _) = row { diff.kind != .context } else { false }
            if isChange, !inChange { starts.append(index) }
            inChange = isChange
        }
        return starts
    }

    // MARK: Attributed text

    package static func tokensByLine(text: String, lines: [Substring], language: Language) -> [[Token]] {
        var lineStarts: [Int] = []
        lineStarts.reserveCapacity(lines.count)
        var offset = 0
        for line in lines {
            lineStarts.append(offset)
            offset += line.utf16.count + 1
        }
        let tokens = SyntaxHighlighter.tokens(in: text, language: language)
        return SyntaxHighlighter.tokensByLine(tokens, lineStarts: lineStarts, textLength: text.utf16.count)
    }

    private static func render(rows: [RenderRow], side: RenderedSide, options: Options) -> RenderedText {
        var text = ""
        var metas: [RowMeta] = []
        var lineStarts: [Int] = []
        var spans = RenderSpans()
        metas.reserveCapacity(rows.count)
        lineStarts.reserveCapacity(rows.count)

        var offset = 0
        var longestLine = 0
        for row in rows {
            var length = 0
            switch row {
                case .diff(let diffRow, let fileIndex, let file):
                    let shown = shownLine(of: diffRow, in: file, side: side)
                    let kind = displayedKind(of: diffRow, side: side, hasLine: shown != nil)
                    if let shown {
                        text.append(contentsOf: shown.line)
                        length = shown.line.utf16.count
                        for token in shown.tokens {
                            spans.tokens.append(
                                (
                                    NSRange(location: offset + token.range.lowerBound, length: token.range.count),
                                    token.kind
                                ))
                        }
                        for range in shown.ref.emphasis {
                            spans.emphasis.append(
                                (NSRange(location: offset + range.lowerBound, length: range.count), kind))
                        }
                    }
                    metas.append(
                        RowMeta(
                            kind: kind, oldNumber: diffRow.old.map { $0.index + 1 },
                            newNumber: diffRow.new.map { $0.index + 1 }, fileIndex: fileIndex, isMoved: diffRow.isMoved)
                    )
                case .gap(let marker):
                    let label = "⋯ \(marker.hiddenRows) hidden \(marker.hiddenRows == 1 ? "line" : "lines")"
                    text.append(label)
                    length = label.utf16.count
                    spans.secondary.append(NSRange(location: offset, length: length))
                    metas.append(
                        RowMeta(
                            kind: .gap, oldNumber: nil, newNumber: nil, fileIndex: marker.key.fileIndex, gap: marker))
                case .header(let title, let fileIndex):
                    text.append(title)
                    length = title.utf16.count
                    metas.append(RowMeta(kind: .header, oldNumber: nil, newNumber: nil, fileIndex: fileIndex))
            }
            text.append("\n")
            lineStarts.append(offset)
            longestLine = max(
                longestLine,
                length + 3
                    * text.utf16[text.utf16.index(text.utf16.endIndex, offsetBy: -(length + 1))...].filter { $0 == 9 }
                    .count)
            offset += length + 1
        }
        if text.hasSuffix("\n") {
            text.removeLast()
        }

        let styled = attributed(text, spans: spans, metas: metas, lineStarts: lineStarts, side: side, options: options)
        return RenderedText(
            side: side, palette: options.palette, attributed: styled.attributed, rows: metas, lineStarts: lineStarts,
            longestLine: longestLine, baselineOffset: styled.baselineOffset, lineHeight: styled.lineHeight
        )
    }

    /// Applies the palette to the assembled text: font, paragraph style, token colours, emphasis, dimmed gap
    /// labels and bold headers.
    /// The coloured stretches of an assembled text, in UTF-16 ranges over the whole text.
    private struct RenderSpans {
        var tokens: [(NSRange, TokenKind)] = []
        var emphasis: [(NSRange, RowKind)] = []
        var secondary: [NSRange] = []
    }

    private static func attributed(
        _ text: String, spans: RenderSpans, metas: [RowMeta], lineStarts: [Int], side: RenderedSide, options: Options
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
        for (range, kind) in spans.tokens {
            attributed.addAttribute(.foregroundColor, value: palette.color(for: kind), range: range)
        }
        for (range, kind) in spans.emphasis {
            attributed.addAttribute(.diffEmphasis, value: palette.emphasis(for: kind, side: side), range: range)
        }
        for range in spans.secondary {
            attributed.addAttribute(.foregroundColor, value: palette.textColor.withAlphaComponent(0.5), range: range)
        }
        let boldFont =
            NSFont(descriptor: palette.font.fontDescriptor.withSymbolicTraits(.bold), size: palette.font.pointSize)
            ?? palette.font
        for (index, meta) in metas.enumerated() where meta.kind == .header {
            let end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : attributed.length
            attributed.addAttribute(
                .font, value: boldFont, range: NSRange(location: lineStarts[index], length: end - lineStarts[index]))
        }
        attributed.endEditing()

        return (attributed, baselineOffset, multiple * palette.defaultLineHeight)
    }

    private struct ShownLine {
        let ref: DiffLineRef
        let line: Substring
        let tokens: [Token]
    }

    private static func shownLine(of row: DiffRow, in file: PreparedDiff, side: RenderedSide) -> ShownLine? {
        func old(_ ref: DiffLineRef) -> ShownLine {
            ShownLine(ref: ref, line: file.model.oldLines[ref.index], tokens: file.oldTokens[ref.index])
        }
        func new(_ ref: DiffLineRef) -> ShownLine {
            ShownLine(ref: ref, line: file.model.newLines[ref.index], tokens: file.newTokens[ref.index])
        }
        switch side {
            case .unified: return row.new.map(new) ?? row.old.map(old)
            case .old: return row.old.map(old)
            case .new: return row.new.map(new)
        }
    }

    private static func displayedKind(of row: DiffRow, side: RenderedSide, hasLine: Bool) -> RowKind {
        guard hasLine else { return .filler }
        switch (row.kind, side) {
            case (.modified, .old): return .removed
            case (.modified, .new): return .added
            default: return row.kind
        }
    }
}

extension NSAttributedString.Key {
    /// The colour behind an intraline change. Not `backgroundColor`: TextKit draws that around the glyphs alone,
    /// which leaves the extra space of a larger line height uncovered, so the layout fragment draws this itself.
    package static let diffEmphasis = NSAttributedString.Key("GitDiffViewer.diffEmphasis")
}
