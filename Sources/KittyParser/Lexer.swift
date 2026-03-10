import KittyGrammar

/// Context-aware lexer that tokenizes source text using a LexTable.
public struct Lexer: Sendable {
    private let lexTable: LexTable
    private let extras: Set<String>

    public init(lexTable: LexTable, extras: Set<String> = []) {
        self.lexTable = lexTable
        self.extras = extras
    }

    /// A token produced by the lexer.
    public struct Token: Sendable, Equatable {
        public var type: String
        public var byteRange: Range<Int>
        public var pointRange: Range<Point>
        public var text: String
        public var isExtra: Bool

        public init(type: String, byteRange: Range<Int>, pointRange: Range<Point>, text: String, isExtra: Bool = false) {
            self.type = type
            self.byteRange = byteRange
            self.pointRange = pointRange
            self.text = text
            self.isExtra = isExtra
        }
    }

    /// Tokenize the source text starting from a byte offset.
    public func tokenize(_ source: String, from offset: Int = 0) -> [Token] {
        let utf8 = Array(source.utf8)
        var tokens: [Token] = []
        var pos = offset
        var point = pointAt(utf8: utf8, byte: offset)

        while pos < utf8.count {
            // Try keyword match first
            if let token = matchKeyword(utf8: utf8, pos: pos, point: point) {
                tokens.append(token)
                point = advancePoint(point, over: utf8, from: pos, to: token.byteRange.upperBound)
                pos = token.byteRange.upperBound
                continue
            }

            // Skip whitespace (common extra)
            if utf8[pos] == 0x20 || utf8[pos] == 0x0a || utf8[pos] == 0x09 || utf8[pos] == 0x0d {
                let start = pos
                let startPoint = point
                while pos < utf8.count && (utf8[pos] == 0x20 || utf8[pos] == 0x0a || utf8[pos] == 0x09 || utf8[pos] == 0x0d) {
                    if utf8[pos] == 0x0a {
                        point = Point(row: point.row + 1, column: 0)
                    } else {
                        point = Point(row: point.row, column: point.column + 1)
                    }
                    pos += 1
                }
                tokens.append(Token(
                    type: "_whitespace",
                    byteRange: start..<pos,
                    pointRange: startPoint..<point,
                    text: String(bytes: utf8[start..<pos], encoding: .utf8) ?? "",
                    isExtra: true
                ))
                continue
            }

            // Single character token (fallback)
            let startPoint = point
            let char = utf8[pos]
            let text = String(bytes: [char], encoding: .utf8) ?? "?"
            if char == 0x0a {
                point = Point(row: point.row + 1, column: 0)
            } else {
                point = Point(row: point.row, column: point.column + 1)
            }
            pos += 1
            tokens.append(Token(
                type: text,
                byteRange: (pos - 1)..<pos,
                pointRange: startPoint..<point,
                text: text
            ))
        }

        return tokens
    }

    private func matchKeyword(utf8: [UInt8], pos: Int, point: Point) -> Token? {
        guard !lexTable.states.isEmpty else { return nil }

        var state = 0
        var current = pos
        var lastAccepting: (id: Int, end: Int)? = nil

        if let accepting = lexTable.states[0].accepting {
            lastAccepting = (accepting, current)
        }

        while current < utf8.count {
            let char = UInt32(utf8[current])
            var nextState: Int? = nil

            for (range, target) in lexTable.states[state].transitions {
                if range.contains(char) {
                    nextState = target
                    break
                }
            }

            guard let next = nextState else { break }
            state = next
            current += 1

            if let accepting = lexTable.states[state].accepting {
                lastAccepting = (accepting, current)
            }
        }

        guard let (_, end) = lastAccepting, end > pos else { return nil }
        let text = String(bytes: utf8[pos..<end], encoding: .utf8) ?? ""

        // Find the keyword string that matched
        let tokenType: String
        if let kw = lexTable.keywords.first(where: { $0.key == text }) {
            tokenType = "\"" + kw.key + "\""
        } else {
            tokenType = text
        }

        let endPoint = advancePoint(point, over: utf8, from: pos, to: end)
        return Token(
            type: tokenType,
            byteRange: pos..<end,
            pointRange: point..<endPoint,
            text: text
        )
    }

    private func pointAt(utf8: [UInt8], byte: Int) -> Point {
        var row = 0
        var col = 0
        for i in 0..<min(byte, utf8.count) {
            if utf8[i] == 0x0a {
                row += 1
                col = 0
            } else {
                col += 1
            }
        }
        return Point(row: row, column: col)
    }

    private func advancePoint(_ point: Point, over utf8: [UInt8], from: Int, to: Int) -> Point {
        var p = point
        for i in from..<min(to, utf8.count) {
            if utf8[i] == 0x0a {
                p = Point(row: p.row + 1, column: 0)
            } else {
                p = Point(row: p.row, column: p.column + 1)
            }
        }
        return p
    }
}
