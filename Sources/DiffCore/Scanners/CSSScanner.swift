/// Scans CSS and its supersets: comments, strings, at-rules, property names inside blocks, numbers with units,
/// hex colours, `!important`, and class or id selectors outside blocks.
struct CSSScanner {
    let units: [UInt16]
    private var tokens: [Token] = []
    private var depth = 0

    init(units: [UInt16]) {
        self.units = units
    }

    mutating func scan() -> [Token] {
        var index = 0
        while index < units.count {
            let unit = units[index]
            let next = index + 1 < units.count ? units[index + 1] : 0
            if unit == ASCII.slash, next == ASCII.asterisk {
                index = scanBlockComment(from: index)
            } else if unit == ASCII.slash, next == ASCII.slash {
                index = scanUntilNewline(from: index, kind: .comment)
            } else if unit == ASCII.quote || unit == ASCII.apostrophe {
                index = scanString(from: index, quote: unit)
            } else if unit == ASCII.at, ASCII.isIdentifierStart(next) {
                index = scanWord(from: index, kind: .attribute)
            } else if unit == ASCII.exclamation, ASCII.isIdentifierStart(next) {
                index = scanWord(from: index, kind: .keyword)
            } else if unit == ASCII.hash, ASCII.isIdentifier(next) {
                index = scanWord(from: index, kind: isHexColor(at: index) ? .number : .type)
            } else if unit == ASCII.dot, ASCII.isIdentifierStart(next) || next == ASCII.hyphen {
                index = scanWord(from: index, kind: .type)
            } else if ASCII.isDigit(unit) || unit == ASCII.dot && ASCII.isDigit(next) || unit == ASCII.hyphen && ASCII.isDigit(next) {
                index = scanNumber(from: index)
            } else if ASCII.isIdentifierStart(unit) || unit == ASCII.hyphen && ASCII.isIdentifierStart(next) {
                index = scanIdentifier(from: index)
            } else {
                if unit == ASCII.openBrace { depth += 1 }
                if unit == ASCII.closeBrace { depth = max(depth - 1, 0) }
                index += 1
            }
        }
        return tokens
    }

    /// `#` followed by 3, 4, 6 or 8 hex digits is a colour; anything else is an id selector.
    private func isHexColor(at start: Int) -> Bool {
        var index = start + 1
        while index < units.count, ASCII.isDigit(units[index]) || (units[index] | 32) >= 97 && (units[index] | 32) <= 102 { index += 1 }
        let length = index - start - 1
        return [3, 4, 6, 8].contains(length) && (index >= units.count || !ASCII.isIdentifier(units[index]))
    }

    private mutating func scanBlockComment(from start: Int) -> Int {
        var index = start + 2
        while index + 1 < units.count, !(units[index] == ASCII.asterisk && units[index + 1] == ASCII.slash) { index += 1 }
        index = min(index + 2, units.count)
        tokens.append(Token(kind: .comment, range: start..<index))
        return index
    }

    private mutating func scanUntilNewline(from start: Int, kind: TokenKind) -> Int {
        var index = start
        while index < units.count, units[index] != ASCII.newline { index += 1 }
        tokens.append(Token(kind: kind, range: start..<index))
        return index
    }

    private mutating func scanString(from start: Int, quote: UInt16) -> Int {
        var index = start + 1
        while index < units.count, units[index] != quote, units[index] != ASCII.newline {
            index += units[index] == ASCII.backslash ? 2 : 1
        }
        index = min(index + 1, units.count)
        tokens.append(Token(kind: .string, range: start..<index))
        return index
    }

    private mutating func scanWord(from start: Int, kind: TokenKind, allowsHyphen: Bool = true) -> Int {
        var index = start + 1
        while index < units.count, ASCII.isIdentifier(units[index]) || allowsHyphen && units[index] == ASCII.hyphen { index += 1 }
        tokens.append(Token(kind: kind, range: start..<index))
        return index
    }

    private mutating func scanNumber(from start: Int) -> Int {
        var index = start + 1
        while index < units.count, ASCII.isIdentifier(units[index]) || units[index] == ASCII.dot || units[index] == ASCII.percent { index += 1 }
        tokens.append(Token(kind: .number, range: start..<index))
        return index
    }

    /// Inside a block an identifier followed by a colon is a property name; elsewhere plain words stay unstyled.
    private mutating func scanIdentifier(from start: Int) -> Int {
        var index = start
        while index < units.count, ASCII.isIdentifier(units[index]) || units[index] == ASCII.hyphen { index += 1 }
        var cursor = index
        while cursor < units.count, units[cursor] == 32 { cursor += 1 }
        if depth > 0, cursor < units.count, units[cursor] == ASCII.colon {
            tokens.append(Token(kind: .attributeName, range: start..<index))
        }
        return index
    }
}
