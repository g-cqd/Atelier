public import AtelierGrammar
import Foundation

/// Context-aware lexer that tokenizes source text using a LexTable.
public struct Lexer: Sendable {
    private let lexTable: LexTable
    private let extras: Set<String>
    /// The table's comment patterns as bytes, in the table's order, so matching one allocates nothing.
    private let comments: [CommentBytes]
    /// Each keyword's token type, the keyword in quotes, by keyword.
    private let keywordTypes: [String: String]

    public init(
        lexTable: LexTable,
        extras: Set<String> = []
    ) {
        self.lexTable = lexTable
        self.extras = extras
        self.comments = lexTable.commentPatterns.map { pattern in
            switch pattern {
                case .line(let prefix): .line(prefix: Array(prefix.utf8))
                case .block(let open, let close): .block(open: Array(open.utf8), close: Array(close.utf8))
            }
        }
        var keywordTypes = [String: String](minimumCapacity: lexTable.keywords.count)
        for keyword in lexTable.keywords.keys {
            keywordTypes[keyword] = "\"" + keyword + "\""
        }
        self.keywordTypes = keywordTypes
    }

    /// A comment pattern's delimiters as bytes.
    private enum CommentBytes {
        case line(prefix: [UInt8])
        case block(open: [UInt8], close: [UInt8])
    }

    /// The text of each single byte, `?` for a byte that is no UTF-8 on its own, as the fallback token takes it.
    private static let singleByteTexts: [String] = (0 ... 255)
        .map { byte in
            String(bytes: [UInt8(byte)], encoding: .utf8) ?? "?"
        }

    /// `bytes` decoded as `String(bytes:encoding: .utf8)` decodes them, nil when they are no UTF-8. That initializer
    /// drops a leading byte order mark, so only bytes that start with one take it; the others are validated by the
    /// standard library, without Foundation's generic path.
    private static func text(of bytes: UnsafeBufferPointer<UInt8>) -> String? {
        guard bytes.count < 3 || bytes[0] != 0xEF || bytes[1] != 0xBB || bytes[2] != 0xBF else {
            return String(bytes: bytes, encoding: .utf8)
        }
        return String(validating: bytes, as: UTF8.self)
    }

    /// A token produced by the lexer.
    public struct Token: Sendable, Equatable {
        public var type: String
        public var byteRange: Range<Int>
        public var pointRange: Range<Point>
        public var text: String
        public var isExtra: Bool

        public init(
            type: String, byteRange: Range<Int>, pointRange: Range<Point>, text: String,
            isExtra: Bool = false
        ) {
            self.type = type
            self.byteRange = byteRange
            self.pointRange = pointRange
            self.text = text
            self.isExtra = isExtra
        }
    }

    /// Tokenize the source text starting from a byte offset.
    public func tokenize(_ source: String, from offset: Int = 0) -> [Token] {
        if let tokens = source.utf8.withContiguousStorageIfAvailable({ utf8 in
            tokenize(utf8: utf8, from: offset)
        }) {
            return tokens
        }

        let utf8 = Array(source.utf8)
        return utf8.withUnsafeBufferPointer { utf8 in
            tokenize(utf8: utf8, from: offset)
        }
    }

    private func tokenize(utf8: UnsafeBufferPointer<UInt8>, from offset: Int) -> [Token] {
        var tokens: [Token] = []
        var pos = offset
        var point = pointAt(utf8: utf8, byte: offset)

        while pos < utf8.count {
            // Try comment match first (before keywords)
            if let token = matchComment(utf8: utf8, pos: pos, point: point) {
                tokens.append(token)
                point = advancePoint(point, over: utf8, from: pos, to: token.byteRange.upperBound)
                pos = token.byteRange.upperBound
                continue
            }

            // Try keyword match
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
                while pos < utf8.count
                    && (utf8[pos] == 0x20 || utf8[pos] == 0x0a || utf8[pos] == 0x09
                        || utf8[pos] == 0x0d)
                {
                    if utf8[pos] == 0x0a {
                        point = Point(row: point.row + 1, column: 0)
                    } else {
                        point = Point(row: point.row, column: point.column + 1)
                    }
                    pos += 1
                }
                tokens.append(
                    Token(
                        type: "_whitespace",
                        byteRange: start ..< pos,
                        pointRange: startPoint ..< point,
                        text: "",
                        isExtra: true
                    ))
                continue
            }

            // Single character token (fallback)
            let startPoint = point
            let char = utf8[pos]
            let text = Self.singleByteTexts[Int(char)]
            if char == 0x0a {
                point = Point(row: point.row + 1, column: 0)
            } else {
                point = Point(row: point.row, column: point.column + 1)
            }
            pos += 1
            tokens.append(
                Token(
                    type: text,
                    byteRange: (pos - 1) ..< pos,
                    pointRange: startPoint ..< point,
                    text: text
                ))
        }

        return tokens
    }

    private func matchComment(utf8: UnsafeBufferPointer<UInt8>, pos: Int, point: Point) -> Token? {
        for pattern in comments {
            switch pattern {
                case .line(let prefixBytes):
                    guard pos + prefixBytes.count <= utf8.count else { continue }
                    var matches = true
                    for (j, b) in prefixBytes.enumerated() where utf8[pos + j] != b {
                        matches = false
                        break
                    }
                    guard matches else { continue }
                    // Scan to end of line
                    var end = pos + prefixBytes.count
                    while end < utf8.count && utf8[end] != 0x0a { end += 1 }
                    let text = Self.text(of: UnsafeBufferPointer(rebasing: utf8[pos ..< end])) ?? ""
                    let endPoint = advancePoint(point, over: utf8, from: pos, to: end)
                    return Token(
                        type: "comment", byteRange: pos ..< end, pointRange: point ..< endPoint, text: text,
                        isExtra: true)

                case .block(let openBytes, let closeBytes):
                    guard pos + openBytes.count <= utf8.count else { continue }
                    var matches = true
                    for (j, b) in openBytes.enumerated() where utf8[pos + j] != b {
                        matches = false
                        break
                    }
                    guard matches else { continue }
                    // Scan for close delimiter
                    var end = pos + openBytes.count
                    while end + closeBytes.count <= utf8.count {
                        var found = true
                        for (j, b) in closeBytes.enumerated() where utf8[end + j] != b {
                            found = false
                            break
                        }
                        if found {
                            end += closeBytes.count
                            break
                        }
                        end += 1
                    }
                    if end > utf8.count { end = utf8.count }
                    let text = Self.text(of: UnsafeBufferPointer(rebasing: utf8[pos ..< end])) ?? ""
                    let endPoint = advancePoint(point, over: utf8, from: pos, to: end)
                    return Token(
                        type: "comment", byteRange: pos ..< end, pointRange: point ..< endPoint, text: text,
                        isExtra: true)
            }
        }
        return nil
    }

    private func matchKeyword(utf8: UnsafeBufferPointer<UInt8>, pos: Int, point: Point) -> Token? {
        guard !lexTable.states.isEmpty else { return nil }

        var state = 0
        var current = pos
        var lastAccepting: (id: Int, end: Int)?

        if let accepting = lexTable.states[0].accepting {
            lastAccepting = (accepting, current)
        }

        while current < utf8.count {
            let char = UInt32(utf8[current])
            var nextState: Int?

            for (range, target) in lexTable.states[state].transitions where range.contains(char) {
                nextState = target
                break
            }

            guard let next = nextState else { break }
            state = next
            current += 1

            if let accepting = lexTable.states[state].accepting {
                lastAccepting = (accepting, current)
            }
        }

        guard let (_, end) = lastAccepting, end > pos else { return nil }
        let text = Self.text(of: UnsafeBufferPointer(rebasing: utf8[pos ..< end])) ?? ""
        // A keyword's type is the keyword in quotes; any other match is its own type.
        let tokenType = keywordTypes[text] ?? text

        let endPoint = advancePoint(point, over: utf8, from: pos, to: end)
        return Token(
            type: tokenType,
            byteRange: pos ..< end,
            pointRange: point ..< endPoint,
            text: text
        )
    }

    private func pointAt(utf8: UnsafeBufferPointer<UInt8>, byte: Int) -> Point {
        var row = 0
        var col = 0
        for i in 0 ..< min(byte, utf8.count) {
            if utf8[i] == 0x0a {
                row += 1
                col = 0
            } else {
                col += 1
            }
        }
        return Point(row: row, column: col)
    }

    private func advancePoint(
        _ point: Point, over utf8: UnsafeBufferPointer<UInt8>, from: Int, to: Int
    ) -> Point {
        var p = point
        for i in from ..< min(to, utf8.count) {
            if utf8[i] == 0x0a {
                p = Point(row: p.row + 1, column: 0)
            } else {
                p = Point(row: p.row, column: p.column + 1)
            }
        }
        return p
    }
}
