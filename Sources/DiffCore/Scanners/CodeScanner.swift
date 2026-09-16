/// Scans C-like and script languages over UTF-16 units, driven by a `LanguageSyntax`.
struct CodeScanner {
    let units: [UInt16]
    let syntax: LanguageSyntax
    private var tokens: [Token] = []

    init(units: [UInt16], syntax: LanguageSyntax) {
        self.units = units
        self.syntax = syntax
    }

    mutating func scan() -> [Token] {
        var index = 0
        let count = units.count
        while index < count {
            let unit = units[index]
            let next = index + 1 < count ? units[index + 1] : 0
            if syntax.hasPreprocessor, unit == ASCII.hash, ASCII.isIdentifierStart(next) {
                index = scanWord(from: index, kind: .attribute)
            } else if unit == ASCII.at, syntax.quotes.contains(next), syntax.hasPreprocessor {
                index = scanString(from: index + 1, quote: next, prefixLength: 1)
            } else if let comment = syntax.lineComments.first(where: { matches($0, at: index) }) {
                index = scanLineComment(from: index, length: comment.count)
            } else if let block = syntax.blockComment, matches(block.start, at: index) {
                index = scanBlockComment(from: index, block: block)
            } else if syntax.quotes.contains(unit) {
                index = scanString(from: index, quote: unit)
            } else if syntax.hasAnnotations, unit == ASCII.at, ASCII.isIdentifierStart(next) {
                index = scanWord(from: index, kind: .attribute)
            } else if syntax.hasVariables, unit == ASCII.dollar, ASCII.isIdentifierStart(next) || next == ASCII.openBrace {
                index = scanVariable(from: index)
            } else if ASCII.isDigit(unit) {
                index = scanNumber(from: index)
            } else if ASCII.isIdentifierStart(unit) {
                index = scanIdentifier(from: index)
            } else {
                index += 1
            }
        }
        return tokens
    }

    private func matches(_ pattern: [UInt16], at index: Int) -> Bool {
        guard index + pattern.count <= units.count else { return false }
        for (offset, unit) in pattern.enumerated() where units[index + offset] != unit { return false }
        return true
    }

    private mutating func scanLineComment(from start: Int, length: Int) -> Int {
        var index = start + length
        while index < units.count, units[index] != ASCII.newline { index += 1 }
        tokens.append(Token(kind: .comment, range: start..<index))
        return index
    }

    private mutating func scanBlockComment(from start: Int, block: (start: [UInt16], end: [UInt16])) -> Int {
        var index = start + block.start.count
        var depth = 1
        while index < units.count, depth > 0 {
            if syntax.nestsBlockComments, matches(block.start, at: index) {
                depth += 1
                index += block.start.count
            } else if matches(block.end, at: index) {
                depth -= 1
                index += block.end.count
            } else {
                index += 1
            }
        }
        tokens.append(Token(kind: .comment, range: start..<index))
        return index
    }

    private mutating func scanString(from start: Int, quote: UInt16, prefixLength: Int = 0) -> Int {
        let isTriple = syntax.tripleQuotes.contains(quote) && start + 2 < units.count
            && units[start + 1] == quote && units[start + 2] == quote
        let spansLines = isTriple || syntax.multilineQuotes.contains(quote)
        var index = start + (isTriple ? 3 : 1)
        while index < units.count {
            let unit = units[index]
            if unit == ASCII.backslash {
                index += 2
                continue
            }
            if isTriple {
                if unit == quote, index + 2 < units.count, units[index + 1] == quote, units[index + 2] == quote {
                    index += 3
                    break
                }
            } else if unit == quote {
                index += 1
                break
            } else if unit == ASCII.newline, !spansLines {
                break
            }
            index += 1
        }
        index = min(index, units.count)
        tokens.append(Token(kind: .string, range: (start - prefixLength)..<index))
        return index
    }

    private mutating func scanVariable(from start: Int) -> Int {
        var index = start + 1
        if index < units.count, units[index] == ASCII.openBrace {
            while index < units.count, units[index] != ASCII.closeBrace, units[index] != ASCII.newline { index += 1 }
            index = min(index + 1, units.count)
        } else {
            while index < units.count, ASCII.isIdentifier(units[index]) { index += 1 }
        }
        tokens.append(Token(kind: .attribute, range: start..<index))
        return index
    }

    private mutating func scanNumber(from start: Int) -> Int {
        var index = start
        while index < units.count, ASCII.isIdentifier(units[index]) || units[index] == ASCII.dot {
            if units[index] == ASCII.dot, index + 1 < units.count, !ASCII.isDigit(units[index + 1]) { break }
            index += 1
        }
        tokens.append(Token(kind: .number, range: start..<index))
        return index
    }

    private mutating func scanWord(from start: Int, kind: TokenKind) -> Int {
        var index = start + 1
        while index < units.count, ASCII.isIdentifier(units[index]) { index += 1 }
        tokens.append(Token(kind: kind, range: start..<index))
        return index
    }

    private mutating func scanIdentifier(from start: Int) -> Int {
        var index = start
        while index < units.count, ASCII.isIdentifier(units[index]) { index += 1 }
        let word = String(decoding: units[start..<index], as: UTF16.self)
        if syntax.keywords.contains(word) {
            tokens.append(Token(kind: .keyword, range: start..<index))
        } else if ASCII.isUpper(units[start]) {
            tokens.append(Token(kind: .type, range: start..<index))
        }
        return index
    }
}
