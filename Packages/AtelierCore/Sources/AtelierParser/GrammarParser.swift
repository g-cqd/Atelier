public import AtelierGrammar

/// Wraps ``GLRParser`` with the per-language tables fixed at construction.
///
/// Every ``parse(_:externalScanner:)`` runs a full GLR pass over the whole source; no previous tree is reused.
public final class GrammarParser: Sendable {
    private let parser: GLRParser

    public init(parseTable: ParseTable, lexTable: LexTable, productions: [ProductionRule]) {
        self.parser = GLRParser(
            parseTable: parseTable, lexTable: lexTable, productions: productions)
    }

    /// Parse `source` and return the resulting ``SyntaxTree``.
    public func parse(
        _ source: String,
        externalScanner: (any GrammarExternalScanner)? = nil
    ) throws(ParseError) -> SyntaxTree {
        try parser.parse(source, externalScanner: externalScanner)
    }
}

// MARK: - Tree Edit Operations

extension SyntaxTree {
    /// The tree with `edit` applied to its node ranges: nodes after the edit shift, nodes overlapping it are
    /// adjusted. The source text is left as it was.
    /// - Complexity: O(n) in the nodes that do not end before the edit, in a loop whatever the tree's depth.
    public func applying(edit: TextEdit) -> SyntaxTree {
        let newRoot = root.rewritten { applyEdit(to: &$0, edit: edit) }
        return SyntaxTree(root: newRoot, source: source, errorByteCount: errorByteCount)
    }

    /// Applies `edit` to the ranges of `n` alone, and returns whether the nodes below it need it too: they do unless
    /// `n` ends before the edit.
    private func applyEdit(to n: inout SyntaxNode, edit: TextEdit) -> Bool {
        // If node is entirely before the edit, leave unchanged
        if n.byteRange.upperBound <= edit.startByte {
            return false
        }

        // If node is entirely after the edit, shift offsets
        if n.byteRange.lowerBound >= edit.oldEndByte {
            let delta = edit.newEndByte - edit.oldEndByte
            n.byteRange = (n.byteRange.lowerBound + delta) ..< (n.byteRange.upperBound + delta)
            n.pointRange = shift(n.pointRange, by: edit)
            return true
        }

        // Node overlaps with edit — adjust this node's range
        if n.byteRange.upperBound > edit.startByte {
            let newEnd: Int
            if n.byteRange.upperBound <= edit.oldEndByte {
                newEnd = edit.newEndByte
            } else {
                let delta = edit.newEndByte - edit.oldEndByte
                newEnd = n.byteRange.upperBound + delta
            }
            n.byteRange = n.byteRange.lowerBound ..< max(n.byteRange.lowerBound, newEnd)
        }

        if n.pointRange.upperBound > edit.startPoint {
            let newEnd: Point
            if n.pointRange.upperBound <= edit.oldEndPoint {
                newEnd = edit.newEndPoint
            } else {
                newEnd = shift(n.pointRange.upperBound, by: edit)
            }
            n.pointRange = n.pointRange.lowerBound ..< max(n.pointRange.lowerBound, newEnd)
        }

        return true
    }

    private func shift(_ range: Range<Point>, by edit: TextEdit) -> Range<Point> {
        shift(range.lowerBound, by: edit) ..< shift(range.upperBound, by: edit)
    }

    private func shift(_ point: Point, by edit: TextEdit) -> Point {
        let rowDelta = edit.newEndPoint.row - edit.oldEndPoint.row

        if point.row == edit.oldEndPoint.row {
            if rowDelta == 0 {
                let columnDelta = edit.newEndPoint.column - edit.oldEndPoint.column
                return Point(row: point.row, column: point.column + columnDelta)
            }

            let column = edit.newEndPoint.column + (point.column - edit.oldEndPoint.column)
            return Point(row: point.row + rowDelta, column: column)
        }

        return Point(row: point.row + rowDelta, column: point.column)
    }
}
