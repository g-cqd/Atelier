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
    public func applying(edit: TextEdit) -> SyntaxTree {
        let newRoot = applyEdit(to: root, edit: edit)
        return SyntaxTree(root: newRoot, source: source, errorByteCount: errorByteCount)
    }

    private func applyEdit(to node: SyntaxNode, edit: TextEdit) -> SyntaxNode {
        var n = node

        // If node is entirely before the edit, leave unchanged
        if n.byteRange.upperBound <= edit.startByte {
            return n
        }

        // If node is entirely after the edit, shift offsets
        if n.byteRange.lowerBound >= edit.oldEndByte {
            let delta = edit.newEndByte - edit.oldEndByte
            n.byteRange = (n.byteRange.lowerBound + delta) ..< (n.byteRange.upperBound + delta)
            n.pointRange = shift(n.pointRange, by: edit)
            n.children = n.children.map { applyEdit(to: $0, edit: edit) }
            n.fields = applyEdit(to: n.fields, edit: edit)
            return n
        }

        // Node overlaps with edit — recurse into children
        n.children = n.children.map { applyEdit(to: $0, edit: edit) }
        n.fields = applyEdit(to: n.fields, edit: edit)

        // Adjust this node's range
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

        return n
    }

    private func applyEdit(to fields: [String: [SyntaxNode]], edit: TextEdit) -> [String:
        [SyntaxNode]]
    {
        Dictionary(
            uniqueKeysWithValues: fields.map { key, nodes in
                (key, nodes.map { applyEdit(to: $0, edit: edit) })
            })
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
