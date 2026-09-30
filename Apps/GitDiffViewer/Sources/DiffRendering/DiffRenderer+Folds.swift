import AppKit
import DiffCore

/// Folded scopes (DIFF-03, `scope-ribbon-design.md`): the last cut of a file's rows, after the compact view folds its
/// changes and isolated changes cut it into hunks with their gaps. A folded scope keeps its first row; its inner rows
/// and its last row give way to one band row. A fold never changes a gap's key, since gaps are worked out before it,
/// and a fold over a gap only hides it: the gap's revealed lines come back as they were once the scope unfolds.
extension DiffRenderer {
    /// What a folded scope's band shows and tells.
    struct ScopeFoldBand {
        let key: ScopeFoldKey
        let lastLine: Int
        /// The leading whitespace of the scope's first line, which the band starts with.
        let indent: Substring
        /// The scope's last line, less its leading whitespace, on the fold's side; nil when it is out of the file.
        let closing: Substring?
        var holdsChange = false
        /// How many rows it hides, which the rows' change starts step over.
        var hiddenRows = 0

        /// The band's text on `side`, and where its `•••` lies in it, in UTF-16 offsets: the closing line follows it
        /// on the fold's side and inline, and the other side of a split shows the capsule alone.
        func text(on side: RenderedSide) -> (text: String, marker: Range<Int>) {
            let start = indent.utf16.count
            let marker = start ..< start + Self.marker.utf16.count
            let showsClosing =
                switch side {
                    case .unified: true
                    case .old: key.isOld
                    case .new: !key.isOld
                }
            guard showsClosing, let closing else { return (String(indent) + Self.marker, marker) }
            return (String(indent) + Self.marker + " " + closing, marker)
        }

        static let marker = "•••"
    }

    /// `rows`, a file's rows as the compact view and the gaps leave them, with each scope of `folds` in the file at
    /// `fileIndex` folded: the rows after its first row, down to its last line on its side, give way to one band. Any
    /// row among them without a line on that side, a gap, or another fold's first row, goes with them. A fold whose
    /// first row does not show, hidden by a gap or an outer fold, does nothing.
    /// - Complexity: O(rows)
    static func folding(_ rows: [RenderRow], of file: PreparedDiff, fileIndex: Int, folds: [ScopeFoldKey: Int])
        -> [RenderRow]
    {
        let mine = folds.filter { $0.key.fileIndex == fileIndex && $0.value > $0.key.firstLine }
        guard !mine.isEmpty else { return rows }
        var result: [RenderRow] = []
        result.reserveCapacity(rows.count)
        var hiding: (band: ScopeFoldBand, index: Int)?
        func finish() {
            guard let active = hiding else { return }
            result[active.index] = .scopeFold(active.band, fileIndex: fileIndex)
            hiding = nil
        }
        for row in rows {
            if var active = hiding {
                let number = lines(of: row).flatMap { active.band.key.isOld ? $0.old : $0.new }
                if case .header = row {
                    finish()
                } else if let number, number > active.band.lastLine {
                    finish()
                } else {
                    if holdsChange(row) { active.band.holdsChange = true }
                    if lines(of: row) != nil { active.band.hiddenRows += 1 }
                    hiding = active
                    if number == active.band.lastLine { finish() }
                    continue
                }
            }
            result.append(row)
            guard let shown = lines(of: row), let band = band(startingAt: shown, in: file, fileIndex, mine) else {
                continue
            }
            result.append(.scopeFold(band, fileIndex: fileIndex))
            hiding = (band, result.count - 1)
        }
        finish()
        return result
    }

    /// The band of the fold of `mine` whose first line `shown` shows, the new side's first; nil when none starts there.
    private static func band(
        startingAt shown: (old: Int?, new: Int?), in file: PreparedDiff, _ fileIndex: Int, _ mine: [ScopeFoldKey: Int]
    ) -> ScopeFoldBand? {
        for (line, isOld) in [(shown.new, false), (shown.old, true)] {
            guard let line else { continue }
            let key = ScopeFoldKey(fileIndex: fileIndex, isOld: isOld, firstLine: line)
            guard let last = mine[key] else { continue }
            let lines = isOld ? file.model.oldLines : file.model.newLines
            let first = lines.indices.contains(line) ? lines[line] : ""
            let closing = lines.indices.contains(last) ? lines[last].drop { $0 == " " || $0 == "\t" } : nil
            return ScopeFoldBand(
                key: key, lastLine: last, indent: first.prefix { $0 == " " || $0 == "\t" }, closing: closing)
        }
        return nil
    }

    /// `starts`, the change starts of rows before any scope folds, in the rows `rows` leaves: a change a fold hides
    /// starts on the fold's band, so every change keeps its place in the count, and navigation can open its fold.
    /// - Complexity: O(rows)
    static func foldedStarts(_ starts: [Int], through rows: [RenderRow]) -> [Int] {
        guard rows.contains(where: { if case .scopeFold = $0 { true } else { false } }) else { return starts }
        var position: [Int] = []
        var row = 0
        for entry in rows {
            switch entry {
                case .diff, .folded, .header:
                    position.append(row)
                    row += 1
                case .scopeFold(let band, _):
                    position += repeatElement(row, count: band.hiddenRows)
                    row += 1
                case .gap, .change:
                    continue
            }
        }
        return starts.map { position.indices.contains($0) ? position[$0] : row }
    }

    /// The source lines, from zero, a row shows on each side; nil for a row that shows none.
    private static func lines(of row: RenderRow) -> (old: Int?, new: Int?)? {
        switch row {
            case .diff(let diff, _, _), .folded(let diff, _, _): (diff.old?.index, diff.new?.index)
            case .change, .gap, .header, .scopeFold: nil
        }
    }

    /// Whether a hidden row is, or marks, a change.
    private static func holdsChange(_ row: RenderRow) -> Bool {
        switch row {
            case .diff(let diff, _, _): diff.kind != .context
            case .folded, .change: true
            case .scopeFold(let band, _): band.holdsChange
            case .gap, .header: false
        }
    }
}

extension DiffRenderer {
    /// Draws each fold's `•••` as a gray capsule: the gutter's number colour over a faint wash of the text colour.
    static func styleFoldMarkers(_ folds: [RenderedFold], palette: DiffPalette, in text: NSMutableAttributedString) {
        for fold in folds where fold.marker.upperBound <= text.length {
            let range = NSRange(location: fold.marker.lowerBound, length: fold.marker.count)
            text.addAttributes(
                [.foregroundColor: palette.gutterText, .backgroundColor: palette.textColor.withAlphaComponent(0.08)],
                range: range)
        }
    }
}
