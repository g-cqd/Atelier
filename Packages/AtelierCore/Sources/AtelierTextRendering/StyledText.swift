/// An immutable snapshot of a document's text (text-renderer.md §3.2): UTF-8 bytes end to end, row starts, and one
/// ASCII bit per row for the identity fast path. Safe to build off the main actor and hand to a typesetting task,
/// since every stored property is `Sendable` and nothing here is mutated after construction.
public struct StyledText: Sendable {
    /// The document's text, one row after another; a row's bytes never include its own terminator.
    public let utf8: [UInt8]
    /// The byte offset of each row's first byte, `rowCount + 1` entries ascending, the last equal to `utf8.count`.
    public let rowStarts: [UInt32]
    public let runs: LineRuns
    public let styles: StyleSheet
    /// One bit per row: whether every byte in it is ASCII, so a scalar-boundary search can skip decoding.
    private let asciiRows: [Bool]

    public init(utf8: [UInt8], rowStarts: [UInt32], runs: LineRuns, styles: StyleSheet) {
        self.utf8 = utf8
        self.rowStarts = rowStarts
        self.runs = runs
        self.styles = styles
        asciiRows = rowStarts.indices.dropLast()
            .map { index in
                utf8[Int(rowStarts[index]) ..< Int(rowStarts[index + 1])].allSatisfy { $0 < 0x80 }
            }
    }

    public var rowCount: Int { max(rowStarts.count - 1, 0) }

    /// - Complexity: O(1).
    public func bytes(ofRow row: RowIndex) -> ArraySlice<UInt8> {
        let index = row.index
        guard rowStarts.indices.contains(index), rowStarts.indices.contains(index + 1) else { return [] }
        return utf8[Int(rowStarts[index]) ..< Int(rowStarts[index + 1])]
    }

    public func isASCII(row: RowIndex) -> Bool {
        asciiRows.indices.contains(row.index) ? asciiRows[row.index] : true
    }

    /// The row a byte offset from the document's start falls in.
    /// - Complexity: O(log rows)
    public func row(containingDocumentOffset offset: Int) -> RowIndex {
        var low = 0
        var high = rowCount
        while low < high {
            let middle = (low + high + 1) / 2
            if Int(rowStarts[middle]) <= offset { low = middle } else { high = middle - 1 }
        }
        return RowIndex(low)
    }
}

extension StyledText {
    /// Builds a text from plain UTF-8 rows, every byte in the plain style (`StyleID(0)`); a caller layers runs on top
    /// through ``LineRuns`` when it has them.
    public static func plain(rows: [[UInt8]], font: FontSpec, plainStyle: TextStyle) -> StyledText {
        var utf8: [UInt8] = []
        var rowStarts: [UInt32] = []
        rowStarts.reserveCapacity(rows.count + 1)
        for row in rows {
            rowStarts.append(UInt32(utf8.count))
            utf8.append(contentsOf: row)
        }
        rowStarts.append(UInt32(utf8.count))
        return StyledText(
            utf8: utf8, rowStarts: rowStarts, runs: .empty(rowCount: rows.count),
            styles: StyleSheet(font: font, styles: [plainStyle]))
    }

    /// Builds a text from plain `String` rows, for tests and simple hosts.
    public static func plain(rows: [String], font: FontSpec, plainStyle: TextStyle) -> StyledText {
        .plain(rows: rows.map { Array($0.utf8) }, font: font, plainStyle: plainStyle)
    }
}
