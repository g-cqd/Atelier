/// Reads a query's text a character at a time for ``QueryParser``.
struct QueryScanner: Sendable {
    var source: String
    var index: String.Index
    var depth: Int = 0
    /// The capture names the text has defined so far, which a predicate may name: tree-sitter's query-wide capture
    /// table, which grows as ts_query__parse_pattern reads each `@name` (lib/src/query.c).
    var definedCaptures: Set<String> = []

    init(source: String) {
        self.source = source
        self.index = source.startIndex
    }

    var isAtEnd: Bool { index >= source.endIndex }

    /// Where the scanner stands, to name in an error.
    var position: QueryPosition { QueryPosition(source: source, index: index) }

    /// A syntax error at the scanner's position.
    func syntaxError(_ message: String) -> QueryError {
        position.syntaxError(message)
    }

    func peek() -> Character? {
        guard !isAtEnd else { return nil }
        return source[index]
    }

    mutating func advance() {
        guard !isAtEnd else { return }
        index = source.index(after: index)
    }

    @discardableResult
    mutating func skipWhitespaceAndComments() -> Bool {
        while let ch = peek() {
            if ch.isWhitespace {
                advance()
            } else if ch == ";" {
                // Line comment
                while let c = peek(), c != "\n" { advance() }
            } else {
                break
            }
        }
        return !isAtEnd
    }

    mutating func readIdentifier() -> String {
        var result = ""
        while let ch = peek(), ch.isLetter || ch.isNumber || ch == "_" || ch == "." || ch == "-" {
            result.append(ch)
            advance()
        }
        return result
    }

    mutating func readCaptureName() -> String {
        var result = ""
        while let ch = peek(), ch.isLetter || ch.isNumber || ch == "_" || ch == "." || ch == "-" {
            result.append(ch)
            advance()
        }
        return result
    }

    mutating func readString() throws(QueryError) -> String {
        guard peek() == "\"" else { throw syntaxError("Expected a string") }
        let start = position
        advance()
        var result = ""
        while let ch = peek(), ch != "\"" {
            if ch == "\\" {
                advance()
                if let escaped = peek() {
                    result.append(escaped)
                    advance()
                }
            } else {
                result.append(ch)
                advance()
            }
        }
        guard peek() == "\"" else { throw start.syntaxError("Unterminated string") }
        advance()
        return result
    }

    func isFieldPrefix() -> Bool {
        // Look ahead for pattern: identifier followed by ':'
        var tempIdx = index
        while tempIdx < source.endIndex {
            let ch = source[tempIdx]
            if ch.isLetter || ch.isNumber || ch == "_" {
                tempIdx = source.index(after: tempIdx)
            } else if ch == ":" {
                return true
            } else {
                return false
            }
        }
        return false
    }

    func isParenthesizedPredicateStart() -> Bool {
        guard peek() == "(" else { return false }

        var tempIdx = source.index(after: index)
        while tempIdx < source.endIndex {
            let ch = source[tempIdx]

            if ch.isWhitespace {
                tempIdx = source.index(after: tempIdx)
                continue
            }

            if ch == ";" {
                while tempIdx < source.endIndex, source[tempIdx] != "\n" {
                    tempIdx = source.index(after: tempIdx)
                }
                continue
            }

            return ch == "#"
        }

        return false
    }

    func isGroupStart() -> Bool {
        guard let next = peek() else { return false }
        return next == "(" || next == "[" || next == "\"" || next == "."
    }
}

/// A place in a query's text, which an error names by line and column; both count from 1, the column in characters.
struct QueryPosition: Sendable {
    var source: String
    var index: String.Index

    /// A syntax error at this position.
    func syntaxError(_ message: String) -> QueryError {
        .syntaxError("\(message) at \(lineAndColumn)")
    }

    /// A capture error at this position.
    func invalidCapture(_ message: String) -> QueryError {
        .invalidCapture("\(message) at \(lineAndColumn)")
    }

    /// "line L, column C".
    private var lineAndColumn: String {
        var line = 1
        var column = 1
        for character in source[..<index] {
            if character == "\n" || character == "\r\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return "line \(line), column \(column)"
    }
}
