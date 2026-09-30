import Foundation

/// A folded scope (DIFF-03): the file it lies in, the side whose scope it is, and its first line on that side, from
/// zero. A reload of the same file keeps it, as it keeps a gap's revealed lines.
package struct ScopeFoldKey: Hashable, Sendable {
    package let fileIndex: Int
    package let isOld: Bool
    package let firstLine: Int

    package init(fileIndex: Int, isOld: Bool, firstLine: Int) {
        self.fileIndex = fileIndex
        self.isOld = isOld
        self.firstLine = firstLine
    }
}

/// What the ribbon or a folding command asks for: scopes to fold, each with its last line, or folds to undo.
package enum ScopeFoldRequest: Sendable, Equatable {
    case fold([ScopeFoldKey: Int])
    case unfold(Set<ScopeFoldKey>)
}

/// A folded scope where a rendered text shows it: its first row stays, and one band row takes the place of the rows
/// it hides, holding a `•••` capsule and the scope's closing line.
package struct RenderedFold: Sendable, Hashable {
    package let key: ScopeFoldKey
    /// The scope's last line on its side, from zero.
    package let lastLine: Int
    /// The row of the scope's first line.
    package let firstRow: Int
    /// The band's row, right after ``firstRow``.
    package let bandRow: Int
    /// Whether a change lies among the rows it hides: the band then shows a dotted change bar.
    package let holdsChange: Bool
    /// Where the band's `•••` lies in the text, in UTF-16 offsets.
    package let marker: Range<Int>

    package init(
        key: ScopeFoldKey, lastLine: Int, firstRow: Int, bandRow: Int, holdsChange: Bool, marker: Range<Int>
    ) {
        self.key = key
        self.lastLine = lastLine
        self.firstRow = firstRow
        self.bandRow = bandRow
        self.holdsChange = holdsChange
        self.marker = marker
    }
}

extension RenderedText {
    /// The fold whose first row or band is `row`; nil when none is.
    /// - Complexity: O(folds)
    package func fold(atRow row: Int) -> RenderedFold? {
        folds.first { $0.firstRow == row || $0.bandRow == row }
    }
}
