/// A borrowed input view for a grammar scanner. Its positions use the parser's byte and point coordinates.
struct BufferScannerLexer: ScannerLexer {
    private let bytes: UnsafeBufferPointer<UInt8>
    private(set) var position: TokenScanner.Cursor
    private(set) var tokenStart: TokenScanner.Cursor
    var tokenEnd: TokenScanner.Cursor { markedEnd ?? position }
    var resultSymbol = 0
    private var markedEnd: TokenScanner.Cursor?

    init(_ bytes: UnsafeBufferPointer<UInt8>, at cursor: TokenScanner.Cursor) {
        self.bytes = bytes
        position = cursor
        tokenStart = cursor
    }

    var lookahead: UInt32 {
        guard !isAtEnd else { return 0 }
        return TokenScanner.decode(bytes, at: position.offset).scalar
    }

    var isAtEnd: Bool { position.offset >= bytes.count }
    var isAtIncludedRangeStart: Bool { false }

    mutating func advance(skip: Bool) {
        guard !isAtEnd else { return }
        let (scalar, length) = TokenScanner.decode(bytes, at: position.offset)
        position.offset += length
        position.point =
            scalar == 0x0A
            ? Point(row: position.point.row + 1, column: 0)
            : Point(row: position.point.row, column: position.point.column + length)
        if skip { tokenStart = position }
    }

    mutating func markEnd() {
        markedEnd = position
    }

    mutating func column() -> UInt32 {
        var lineStart = position.offset
        while lineStart > 0, bytes[lineStart - 1] != UInt8(ascii: "\n") { lineStart -= 1 }
        var offset = lineStart
        var count: UInt32 = 0
        while offset < position.offset {
            offset += TokenScanner.decode(bytes, at: offset).length
            count += 1
        }
        return count
    }
}
