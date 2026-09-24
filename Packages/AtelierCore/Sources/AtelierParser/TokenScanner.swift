import AtelierGrammar

/// Reads one token at a time with a lex table's automaton, in the lex mode the parser asks for.
///
/// Built once per parser from the table: it lays the automaton out for reading, a direct table for the moves on
/// ASCII scalars and sorted ranges for the others.
struct TokenScanner: Sendable {
    /// A place in the source: a byte offset and its point, columns counted in bytes.
    struct Cursor: Sendable, Equatable {
        var offset: Int
        var point: Point

        static let start = Cursor(offset: 0, point: .zero)
    }

    /// A token the automaton read: its index in the lex table's tokens and where it lies.
    struct Scanned: Sendable, Equatable {
        var token: Int
        var start: Cursor
        var end: Cursor
    }

    /// What a read found.
    enum Outcome: Sendable, Equatable {
        case token(Scanned)
        /// Nothing but separators before the end of the source, which `end` is.
        case end(Cursor)
        /// No token of the mode starts after the separators, at `start`.
        case none(start: Cursor)
    }

    /// For each state and ASCII scalar, `target << 1 | skips`, or -1 where the state has no move.
    private let asciiMoves: [Int32]
    private let moves: [[LexTransition]]
    /// Each state's accepted token, or -1.
    private let accepts: [Int32]
    private let modeStarts: [Int]
    private let stateModes: [Int]
    let errorMode: Int?
    private let wordToken: Int?
    private let keywordTrie: [KeywordNode]
    private let modeValidTokens: [Set<Int>]
    private let modeEmptyTokens: [Int?]
    private let modeEmptyAfterSeparator: [Int?]

    private struct KeywordNode: Sendable {
        var next: [UInt8: Int] = [:]
        var token: Int?
    }

    /// Nil for a table without lex modes.
    init?(_ table: LexTable) {
        guard !table.modeStarts.isEmpty else { return nil }
        var asciiMoves = [Int32](repeating: -1, count: table.automaton.count * 128)
        for (state, automatonState) in table.automaton.enumerated() {
            for transition in automatonState.transitions where transition.lower < 128 {
                let move = Int32(transition.target) << 1 | (transition.skips ? 1 : 0)
                for scalar in Int(transition.lower) ... Int(min(transition.upper, 127)) {
                    asciiMoves[state << 7 | scalar] = move
                }
            }
        }
        self.asciiMoves = asciiMoves
        self.moves = table.automaton.map(\.transitions)
        self.accepts = table.automaton.map { Int32($0.accept ?? -1) }
        self.modeStarts = table.modeStarts
        self.stateModes = table.stateModes
        self.errorMode = table.errorMode
        self.wordToken = table.wordToken
        self.modeValidTokens = table.wordToken == nil ? [] : table.modeValidTokens.map(Set.init)
        self.modeEmptyTokens = table.modeEmptyTokens
        self.modeEmptyAfterSeparator = table.modeEmptyAfterSeparator
        var trie = [KeywordNode()]
        if table.wordToken != nil {
            for spelling in table.keywordTokens.keys.sorted() {
                guard let token = table.keywordTokens[spelling] else { continue }
                var node = 0
                for byte in spelling.utf8 {
                    if let next = trie[node].next[byte] {
                        node = next
                    } else {
                        trie[node].next[byte] = trie.count
                        node = trie.count
                        trie.append(KeywordNode())
                    }
                }
                trie[node].token = token
            }
        }
        self.keywordTrie = trie
    }

    /// The lex mode of parse state `state`.
    func mode(ofState state: Int) -> Int? {
        stateModes.indices.contains(state) ? stateModes[state] : nil
    }

    /// The token that starts at `cursor`, after any separators, in `mode`: the automaton reads as far as it can and
    /// the last token it accepted on the way is the one read.
    ///
    /// - Complexity: O(n) in the scalars the automaton reads.
    func scan(
        _ utf8: UnsafeBufferPointer<UInt8>, from cursor: Cursor, mode: Int,
        suppressEmptyAt: Int? = nil
    ) -> Outcome {
        var state = modeStarts[mode]
        var position = cursor
        var tokenStart = cursor
        var scanned: Scanned? =
            accepts[state] >= 0
            ? Scanned(token: Int(accepts[state]), start: cursor, end: cursor) : nil
        while position.offset < utf8.count {
            let (scalar, length) = Self.decode(utf8, at: position.offset)
            let move = self.move(from: state, on: scalar)
            guard move >= 0 else { break }
            position.offset += length
            position.point =
                scalar == 0x0A
                ? Point(row: position.point.row + 1, column: 0)
                : Point(row: position.point.row, column: position.point.column + length)
            state = Int(move >> 1)
            if move & 1 == 1 {
                tokenStart = position
            } else if accepts[state] >= 0 {
                scanned = Scanned(token: Int(accepts[state]), start: tokenStart, end: position)
            }
        }
        if let scanned {
            guard modeValidTokens.indices.contains(mode) else { return .token(scanned) }
            return .token(classifyingKeyword(scanned, in: utf8, validTokens: modeValidTokens[mode]))
        }
        let emptyTokens = tokenStart.offset == cursor.offset ? modeEmptyTokens : modeEmptyAfterSeparator
        if emptyTokens.indices.contains(mode), let empty = emptyTokens[mode], tokenStart.offset != suppressEmptyAt {
            return .token(Scanned(token: empty, start: tokenStart, end: tokenStart))
        }
        return tokenStart.offset == utf8.count ? .end(tokenStart) : .none(start: tokenStart)
    }

    /// `scanned` as the keyword its text spells, when it is the word token and `validTokens` holds that keyword: as
    /// tree-sitter does, the lexer reads a word and then looks it up among the grammar's keywords.
    func classifyingKeyword(
        _ scanned: Scanned, in utf8: UnsafeBufferPointer<UInt8>, validTokens: Set<Int>
    ) -> Scanned {
        guard scanned.token == wordToken else { return scanned }
        var node = 0
        for offset in scanned.start.offset ..< scanned.end.offset {
            guard let next = keywordTrie[node].next[utf8[offset]] else { return scanned }
            node = next
        }
        guard let keyword = keywordTrie[node].token, validTokens.contains(keyword) else { return scanned }
        var classified = scanned
        classified.token = keyword
        return classified
    }

    /// The token `mode` reads at `cursor`, read as ``scan(_:from:mode:suppressEmptyAt:)`` reads a mode of the table,
    /// with the mode building the states the read passes through; nil when the mode's automaton passes its limit.
    ///
    /// - Complexity: O(n) in the scalars read, plus the states built on the way.
    func scan(
        _ utf8: UnsafeBufferPointer<UInt8>, from cursor: Cursor, lazyMode mode: inout LazyLexMode,
        suppressEmptyAt: Int? = nil
    ) -> Outcome? {
        do throws(GrammarError) {
            var state = try mode.state(mode.start)
            var position = cursor
            var tokenStart = cursor
            var scanned = state.accept.map { Scanned(token: $0, start: cursor, end: cursor) }
            while position.offset < utf8.count {
                let (scalar, length) = Self.decode(utf8, at: position.offset)
                guard let transition = Self.transition(in: state.transitions, on: scalar) else { break }
                position.offset += length
                position.point =
                    scalar == 0x0A
                    ? Point(row: position.point.row + 1, column: 0)
                    : Point(row: position.point.row, column: position.point.column + length)
                state = try mode.state(transition.target)
                if transition.skips {
                    tokenStart = position
                } else if let accept = state.accept {
                    scanned = Scanned(token: accept, start: tokenStart, end: position)
                }
            }
            if let scanned {
                return .token(classifyingKeyword(scanned, in: utf8, validTokens: Set(mode.validTokens)))
            }
            let empty = tokenStart.offset == cursor.offset ? mode.emptyToken : mode.emptyTokenAfterSeparator
            if let empty, tokenStart.offset != suppressEmptyAt {
                return .token(Scanned(token: empty, start: tokenStart, end: tokenStart))
            }
            return tokenStart.offset == utf8.count ? .end(tokenStart) : .none(start: tokenStart)
        } catch {
            return nil
        }
    }

    /// The move of `transitions`, sorted and disjoint, that reads `scalar`.
    private static func transition(in transitions: [LexTransition], on scalar: UInt32) -> LexTransition? {
        var low = 0
        var high = transitions.count
        while low < high {
            let middle = (low + high) / 2
            if transitions[middle].upper < scalar {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low < transitions.count, transitions[low].lower <= scalar else { return nil }
        return transitions[low]
    }

    /// `target << 1 | skips` for the move from `state` on `scalar`, or -1.
    private func move(from state: Int, on scalar: UInt32) -> Int32 {
        if scalar < 128 {
            return asciiMoves[state << 7 | Int(scalar)]
        }
        let transitions = moves[state]
        var low = 0
        var high = transitions.count
        while low < high {
            let middle = (low + high) / 2
            if transitions[middle].upper < scalar {
                low = middle + 1
            } else {
                high = middle
            }
        }
        guard low < transitions.count, transitions[low].lower <= scalar else { return -1 }
        return Int32(transitions[low].target) << 1 | (transitions[low].skips ? 1 : 0)
    }

    /// The scalar at `offset` and its length in bytes; U+FFFD for one byte of a sequence with no valid lead byte or
    /// too few continuation bytes. A `String`'s bytes are always well formed; the check keeps a bad buffer from
    /// reading as a scalar that spans the bytes after it.
    static func decode(_ utf8: UnsafeBufferPointer<UInt8>, at offset: Int) -> (scalar: UInt32, length: Int) {
        let lead = utf8[offset]
        guard lead >= 0x80 else { return (UInt32(lead), 1) }
        let length =
            switch lead {
                case 0xF8...: 1
                case 0xF0...: 4
                case 0xE0...: 3
                case 0xC0...: 2
                default: 1
            }
        guard length > 1, offset + length <= utf8.count else { return (0xFFFD, 1) }
        var value = UInt32(lead) & (0x7F >> length)
        for index in offset + 1 ..< offset + length {
            guard utf8[index] & 0xC0 == 0x80 else { return (0xFFFD, 1) }
            value = value << 6 | UInt32(utf8[index] & 0x3F)
        }
        return (value, length)
    }
}
