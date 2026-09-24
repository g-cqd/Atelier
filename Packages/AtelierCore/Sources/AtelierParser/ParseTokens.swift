import AtelierGrammar

/// A token as the parser takes it: its terminal, if the table has one, and its leaf.
struct ParseToken: Sendable, Equatable {
    /// The terminal's index in the parse table; nil for a token the table does not know, which every stack takes as
    /// an error.
    var terminal: Int?
    var type: String
    var byteRange: Range<Int>
    var pointRange: Range<Point>
    var isNamed = false
    /// Whether the parser skips it, as it does comments and the grammar's other extras.
    var isExtra = false
}

/// Where a parse gets its tokens, one at a time.
protocol ParseTokenSource {
    /// Where the source ends, once ``next(for:)`` has returned nil.
    var end: Point { get }

    /// The next token, read for `stacks`, whose states may decide how it is read; nil at the end of the source.
    mutating func next(for stacks: [ParseStack]) -> ParseToken?
}

/// The tokens of a lex table with lex modes, each read in the mode of the parser's preferred stack.
///
/// When that mode reads no token, the source tries the modes of the other stacks, then the error mode, and at last
/// takes the scalar where a token would start as an error token of its own, so the parse always moves on.
struct ScannedTokenSource: ParseTokenSource {
    private let scanner: TokenScanner
    private let tokens: [LexToken]
    private let tokenTerminals: [Int?]
    private let utf8: UnsafeBufferPointer<UInt8>
    private var cursor = TokenScanner.Cursor.start
    private var lastEmptyOffset: Int?
    private(set) var end = Point.zero

    /// `tokenTerminals` gives each token's terminal index.
    init(
        _ utf8: UnsafeBufferPointer<UInt8>,
        scanner: TokenScanner,
        tokens: [LexToken],
        tokenTerminals: [Int?]
    ) {
        self.utf8 = utf8
        self.scanner = scanner
        self.tokens = tokens
        self.tokenTerminals = tokenTerminals
    }

    mutating func next(for stacks: [ParseStack]) -> ParseToken? {
        let preferred = preferredMode(for: stacks)
        var outcome =
            preferred.map { scanner.scan(utf8, from: cursor, mode: $0, suppressEmptyAt: lastEmptyOffset) }
            ?? .none(start: cursor)
        if case .none = outcome {
            for mode in fallbackModes(for: stacks, besides: preferred) {
                outcome = scanner.scan(utf8, from: cursor, mode: mode, suppressEmptyAt: lastEmptyOffset)
                guard case .none = outcome else { break }
            }
        }
        switch outcome {
            case .token(let scanned):
                lastEmptyOffset = scanned.start.offset == scanned.end.offset ? scanned.end.offset : nil
                cursor = scanned.end
                return ParseToken(
                    terminal: tokenTerminals[scanned.token],
                    type: tokens[scanned.token].name,
                    byteRange: scanned.start.offset ..< scanned.end.offset,
                    pointRange: scanned.start.point ..< scanned.end.point,
                    isNamed: tokens[scanned.token].isNamed,
                    isExtra: tokens[scanned.token].isExtra
                )
            case .end(let sourceEnd):
                cursor = sourceEnd
                end = sourceEnd.point
                return nil
            case .none(let tokenStart):
                lastEmptyOffset = nil
                return errorToken(at: tokenStart)
        }
    }

    /// The mode of the preferred stack's state.
    private func preferredMode(for stacks: [ParseStack]) -> Int? {
        guard stacks.count > 1 else { return stacks.first.flatMap { scanner.mode(ofState: $0.state) } }
        return stacks.indices.min { stacks[$0].isPreferred(over: stacks[$1]) }
            .flatMap { scanner.mode(ofState: stacks[$0].state) }
    }

    /// The modes to try when `preferred` reads nothing: the other stacks' in order, then the error mode.
    private func fallbackModes(for stacks: [ParseStack], besides preferred: Int?) -> [Int] {
        var modes: [Int] = []
        for stack in stacks {
            if let mode = scanner.mode(ofState: stack.state), mode != preferred, !modes.contains(mode) {
                modes.append(mode)
            }
        }
        if let errorMode = scanner.errorMode, errorMode != preferred, !modes.contains(errorMode) {
            modes.append(errorMode)
        }
        return modes
    }

    /// The scalar at `start`, a token no terminal has, or nil at the end of the source.
    private mutating func errorToken(at start: TokenScanner.Cursor) -> ParseToken? {
        guard start.offset < utf8.count else {
            cursor = start
            end = start.point
            return nil
        }
        let (scalar, length) = TokenScanner.decode(utf8, at: start.offset)
        let next = advanced(start, by: length, ending: scalar == 0x0A)
        cursor = next
        return ParseToken(
            terminal: nil,
            type: Unicode.Scalar(scalar).map { String(Character($0)) } ?? "\u{FFFD}",
            byteRange: start.offset ..< next.offset,
            pointRange: start.point ..< next.point
        )
    }

    /// `cursor` moved past `length` bytes, onto the next row when they end a line.
    private func advanced(_ cursor: TokenScanner.Cursor, by length: Int, ending line: Bool) -> TokenScanner.Cursor {
        TokenScanner.Cursor(
            offset: cursor.offset + length,
            point: line
                ? Point(row: cursor.point.row + 1, column: 0)
                : Point(row: cursor.point.row, column: cursor.point.column + length))
    }
}

/// The tokens of a lex table without lex modes, as tests build by hand: the context-free lexer's, whitespace left
/// out and comments kept as extras.
struct TokenizedSource: ParseTokenSource {
    private let tokens: [Lexer.Token]
    private let terminalIndex: [String: Int]
    private var index = 0
    /// The lexer's tokens, whitespace included, cover the source, so the last one ends where the source ends.
    let end: Point

    init(_ tokens: [Lexer.Token], terminalIndex: [String: Int]) {
        self.tokens = tokens
        self.terminalIndex = terminalIndex
        self.end = tokens.last?.pointRange.upperBound ?? .zero
    }

    mutating func next(for stacks: [ParseStack]) -> ParseToken? {
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            guard !token.isExtra || token.type == "comment" else { continue }
            return ParseToken(
                terminal: terminalIndex[token.type],
                type: token.type,
                byteRange: token.byteRange,
                pointRange: token.pointRange,
                isNamed: token.isExtra,
                isExtra: token.isExtra
            )
        }
        return nil
    }
}
