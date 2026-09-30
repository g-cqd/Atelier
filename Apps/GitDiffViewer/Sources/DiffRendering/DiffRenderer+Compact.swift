import DiffCore
import Foundation

/// The compact inline view (book DIFF-04): the inline side as the new file reads, each change folded into it but for
/// those disclosed, which show as the inline view shows them.
extension DiffRenderer {
    /// A change of a compact inline side, before its rows are placed: what its marker needs.
    struct PendingChange {
        let key: ChangeKey
        let kind: RenderedChange.Kind
        let isDisclosed: Bool
        /// The rows that follow it and are its own.
        let rowCount: Int
        let removedLines: Int
        let addedLines: Int

        /// The change once placed, its first row at `start`.
        func rendered(from start: Int) -> RenderedChange {
            RenderedChange(
                key: key, kind: kind, rows: start ..< start + rowCount, isDisclosed: isDisclosed,
                removedLines: removedLines, addedLines: addedLines)
        }
    }

    /// A file's inline rows with each change folded or disclosed, and where each change lies among them.
    private struct CompactFile {
        var rows: [RenderRow] = []
        var changes: [(rows: Range<Int>, change: PendingChange)] = []
    }

    /// The inline rows of `file` for the compact view, laid out as `layout` asks: everything, or hunks between gaps.
    ///
    /// The hunks are worked out on the compact rows, so a folded change counts only its added rows, and a folded
    /// removal counts as its boundary, its context around it. Disclosing a change grows it in place, which moves no
    /// unchanged row, so the gaps keep their keys, the rows they hide and the rows revealed around them. With no
    /// context, a folded removal keeps the row after it, or before it at the end of the file, and its marker with it.
    static func compactRows(
        of file: PreparedDiff, fileIndex: Int, layout: RenderLayout, header: String?, disclosed: Set<ChangeKey>
    ) -> [RenderRow] {
        var compact = compacted(file, fileIndex: fileIndex, disclosed: disclosed)
        // A file with no new line, a deleted one, would show nothing: its changes show whole.
        if compact.rows.isEmpty, !compact.changes.isEmpty {
            let every = Set(compact.changes.map { $0.change.key })
            compact = compacted(file, fileIndex: fileIndex, disclosed: every)
        }
        var rows: [RenderRow] = []
        if let header { rows.append(.header(header, fileIndex: fileIndex)) }
        var next = 0
        /// Appends the compact rows of `slice`, each change before its first row, or before the row after it.
        func emit(_ slice: Range<Int>) {
            for index in slice {
                while next < compact.changes.count, compact.changes[next].rows.lowerBound <= index {
                    rows.append(.change(compact.changes[next].change))
                    next += 1
                }
                rows.append(compact.rows[index])
            }
            while next < compact.changes.count, compact.changes[next].rows.lowerBound <= slice.upperBound,
                compact.changes[next].rows.isEmpty
            {
                rows.append(.change(compact.changes[next].change))
                next += 1
            }
        }
        let count = compact.rows.count
        switch layout {
            case .full:
                emit(0 ..< count)
            case .changes(let context, let expansions, let wholeWhenUnchanged):
                if wholeWhenUnchanged, compact.changes.isEmpty {
                    emit(0 ..< count)
                    return rows
                }
                let fileExpansions = Dictionary(
                    uniqueKeysWithValues: expansions.filter { $0.key.fileIndex == fileIndex }
                        .map { ($0.key.gapIndex, $0.value) })
                // A folded removal's context lies around its boundary, as it lies around its rows once disclosed. With
                // no context it would have no row at all: it keeps the row after it, or before it at the end.
                let changeRanges = compact.changes.map { change -> Range<Int> in
                    let range = change.rows
                    guard range.isEmpty, context == 0 else { return range }
                    if range.lowerBound < count { return range.lowerBound ..< range.lowerBound + 1 }
                    return max(range.lowerBound - 1, 0) ..< range.lowerBound
                }
                let layout = HunkLayout.layout(
                    changeRanges: changeRanges, rowCount: count, context: context, expansions: fileExpansions)
                var cursor = 0
                // Gap keys follow the base hunks, as in the other views.
                for hunk in layout.hunks {
                    if hunk.rows.lowerBound > cursor {
                        rows.append(
                            .gap(
                                GapMarker(
                                    key: GapKey(fileIndex: fileIndex, gapIndex: hunk.firstBase),
                                    hiddenRows: hunk.rows.lowerBound - cursor, isLeading: hunk.firstBase == 0,
                                    isTrailing: false)))
                    }
                    emit(hunk.rows)
                    cursor = hunk.rows.upperBound
                }
                if cursor < count {
                    rows.append(
                        .gap(
                            GapMarker(
                                key: GapKey(fileIndex: fileIndex, gapIndex: layout.baseCount),
                                hiddenRows: count - cursor, isLeading: layout.hunks.isEmpty, isTrailing: true)))
                }
        }
        return rows
    }

    /// `file`'s inline rows with every change but those in `disclosed` folded: its removed rows dropped and its added
    /// rows shown as the new file reads.
    /// - Complexity: O(rows)
    private static func compacted(_ file: PreparedDiff, fileIndex: Int, disclosed: Set<ChangeKey>) -> CompactFile {
        let all = file.model.unifiedRows
        var compact = CompactFile()
        compact.rows.reserveCapacity(all.count)
        var cursor = 0
        for (changeIndex, range) in file.model.unifiedChangeRanges.enumerated() {
            for row in all[cursor ..< range.lowerBound] {
                compact.rows.append(.diff(row, fileIndex: fileIndex, file: file))
            }
            let key = ChangeKey(fileIndex: fileIndex, changeIndex: changeIndex)
            let changed = all[range]
            let removed = changed.count { $0.kind == .removed }
            let added = changed.count - removed
            let isDisclosed = disclosed.contains(key)
            let start = compact.rows.count
            for row in changed {
                if isDisclosed {
                    compact.rows.append(.diff(row, fileIndex: fileIndex, file: file))
                } else if row.kind != .removed {
                    compact.rows.append(.folded(row, fileIndex: fileIndex, file: file))
                }
            }
            let kind: RenderedChange.Kind = removed == 0 ? .added : added == 0 ? .removed : .modified
            let change = PendingChange(
                key: key, kind: kind, isDisclosed: isDisclosed, rowCount: compact.rows.count - start,
                removedLines: removed, addedLines: added)
            compact.changes.append((start ..< compact.rows.count, change))
            cursor = range.upperBound
        }
        for row in all[cursor...] { compact.rows.append(.diff(row, fileIndex: fileIndex, file: file)) }
        return compact
    }

    /// Where each change of compact inline rows starts: its first row, the row after a folded removal, or the last row
    /// for a folded removal below it.
    static func compactChangeStarts(in rows: [RenderRow]) -> [Int] {
        var starts: [Int] = []
        var index = 0
        for row in rows {
            switch row {
                case .change: starts.append(index)
                case .gap: continue
                case .diff, .folded, .header, .scopeFold: index += 1
            }
        }
        return starts.map { min($0, max(index - 1, 0)) }
    }
}
