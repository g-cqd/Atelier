/// The lexer an external scanner reads, shaped after tree-sitter's `TSLexer` so that a grammar's `scanner.c` ports
/// line for line: each member names the C field or function it stands for.
///
/// The input is UTF-8; `lookahead` is the Unicode scalar at the current position, as tree-sitter decodes it.
public protocol ScannerLexer {
    /// The scalar at the current position, or 0 at the end of the input (`lookahead`).
    var lookahead: UInt32 { get }

    /// The index, in the grammar's `externals` list, of the token the scanner recognised (`result_symbol`).
    var resultSymbol: Int { get set }

    /// Moves past the current scalar. With `skip`, the scalar is whitespace before the token rather than part of it
    /// (`advance`).
    mutating func advance(skip: Bool)

    /// Ends the token at the current position; later calls to ``advance(skip:)`` only look ahead (`mark_end`).
    /// Without a call, the token ends wherever the scanner stopped advancing.
    mutating func markEnd()

    /// The column of the current position, counted in scalars from the start of its line (`get_column`).
    mutating func column() -> UInt32

    /// Whether the current position is at the end of the input (`eof`).
    var isAtEnd: Bool { get }

    /// Whether the current position starts one of the parser's included ranges (`is_at_included_range_start`).
    /// Always false: the parsers here read whole documents.
    var isAtIncludedRangeStart: Bool { get }
}

/// A grammar's external scanner, shaped after tree-sitter's `tree_sitter_<language>_external_scanner_*` functions.
///
/// A value holds the scanner's state. The parser keeps one value per parse stack, saves it with ``serialize(into:)``
/// after every external token and restores it with ``deserialize(_:)`` when it resumes a stack, as tree-sitter does.
public protocol GrammarExternalScanner: Sendable {
    /// The grammar's `externals`, in order. `validSymbols` and ``ScannerLexer/resultSymbol`` index into it.
    static var externalNames: [String] { get }

    /// A scanner in its initial state (`create`).
    init()

    /// Tries to recognise one external token at the lexer's position (`scan`). `validSymbols[index]` says whether
    /// `externalNames[index]` is valid in the current parse state; all of them are during error recovery.
    /// - Returns: Whether a token was recognised; on success the lexer's ``ScannerLexer/resultSymbol`` names it and
    ///   the token ends at the last ``ScannerLexer/markEnd()``, or where the scanner stopped advancing.
    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool

    /// Appends the scanner's state to `buffer`, at most ``maximumSerializedScannerStateSize`` bytes (`serialize`).
    func serialize(into buffer: inout [UInt8])

    /// Restores the state that ``serialize(into:)`` wrote; an empty `state` resets the scanner (`deserialize`).
    mutating func deserialize(_ state: ArraySlice<UInt8>)
}

/// The most bytes a scanner may serialize, tree-sitter's `TREE_SITTER_SERIALIZATION_BUFFER_SIZE`.
public let maximumSerializedScannerStateSize = 1024

/// A ``ScannerLexer`` over a UTF-8 string, for testing a scanner on its own: scan at an offset and read where the
/// token the scanner recognised ends.
public struct StringScannerLexer: ScannerLexer {
    private let bytes: [UInt8]
    /// The byte offset of the current position.
    public private(set) var position: Int
    /// The byte offset where the token starts: past everything advanced over with `skip` before its first scalar.
    public private(set) var tokenStart: Int
    /// The byte offset where the token ends: the last ``markEnd()``, else ``position``.
    public var tokenEnd: Int { markedEnd ?? position }
    public var resultSymbol = 0
    private var markedEnd: Int?
    private var hasTokenStarted = false

    /// A lexer over `text` whose current position is `offset` bytes in.
    public init(_ text: String, at offset: Int = 0) {
        self.init(utf8: Array(text.utf8), at: offset)
    }

    /// A lexer over raw bytes, which may hold invalid UTF-8, whose current position is `offset` bytes in.
    public init(utf8 bytes: [UInt8], at offset: Int = 0) {
        self.bytes = bytes
        position = min(max(offset, 0), bytes.count)
        tokenStart = position
    }

    public var lookahead: UInt32 { Self.decode(bytes, at: position).scalar }

    public var isAtEnd: Bool { position >= bytes.count }

    public var isAtIncludedRangeStart: Bool { false }

    public mutating func advance(skip: Bool) {
        guard !isAtEnd else { return }
        position += Self.decode(bytes, at: position).length
        if skip && !hasTokenStarted {
            tokenStart = position
        } else {
            hasTokenStarted = true
        }
    }

    public mutating func markEnd() {
        markedEnd = position
    }

    public mutating func column() -> UInt32 {
        var start = position
        while start > 0, bytes[start - 1] != UInt8(ascii: "\n") { start -= 1 }
        var column: UInt32 = 0
        var index = start
        while index < position {
            index += Self.decode(bytes, at: index).length
            column += 1
        }
        return column
    }

    /// The scalar at `offset` and its length in bytes; an invalid sequence reads as U+FFFD one byte long, and the end
    /// of the input as 0.
    private static func decode(_ bytes: [UInt8], at offset: Int) -> (scalar: UInt32, length: Int) {
        guard offset < bytes.count else { return (0, 0) }
        let lead = bytes[offset]
        let (length, initial): (Int, UInt32) =
            switch lead {
                case 0x00 ... 0x7F: (1, UInt32(lead))
                case 0xC2 ... 0xDF: (2, UInt32(lead & 0x1F))
                case 0xE0 ... 0xEF: (3, UInt32(lead & 0x0F))
                case 0xF0 ... 0xF4: (4, UInt32(lead & 0x07))
                default: (0, 0)
            }
        guard length > 0, offset + length <= bytes.count else { return (0xFFFD, 1) }
        var scalar = initial
        for continuation in bytes[(offset + 1) ..< (offset + length)] {
            guard continuation & 0xC0 == 0x80 else { return (0xFFFD, 1) }
            scalar = scalar << 6 | UInt32(continuation & 0x3F)
        }
        return (scalar, length)
    }
}
