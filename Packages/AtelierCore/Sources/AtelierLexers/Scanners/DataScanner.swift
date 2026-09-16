import AtelierSyntaxModel

/// Scans JSON, YAML and TOML: keys, strings, numbers, the few literal keywords, comments, tables and anchors.
struct DataScanner<Unit: LexerUnit> {
    let units: [Unit]
    let format: Language
    private var tokens: [Token] = []

    init(units: [Unit], format: Language) {
        self.units = units
        self.format = format
    }

    mutating func scan() -> [Token] {
        var index = 0
        while index < units.count {
            let unit = units[index]
            let atLineStart = isAtLineStart(index)
            if format != .json, unit == ASCII.hash, index == 0 || ASCII.isSpace(units[index - 1]) {
                index = scanUntilNewline(from: index, kind: .comment)
            } else if format == .toml, atLineStart, unit == ASCII.openBracket {
                index = scanUntilNewline(from: index, kind: .tag)
            } else if format == .yaml, atLineStart, matches("---", at: index) || matches("...", at: index) {
                index = scanUntilNewline(from: index, kind: .keyword)
            } else if format == .yaml, unit == ASCII.ampersand || unit == ASCII.asterisk || unit == ASCII.exclamation,
                index + 1 < units.count, !ASCII.isSpace(units[index + 1])
            {
                var end = index + 1
                while end < units.count, !ASCII.isSpace(units[end]), units[end] != ASCII.comma,
                    units[end] != ASCII.closeBracket, units[end] != ASCII.closeBrace
                { end += 1 }
                tokens.append(Token(kind: .attribute, range: index ..< end))
                index = end
            } else if unit == ASCII.quote || unit == ASCII.apostrophe && format != .json {
                index = scanQuoted(from: index, quote: unit)
            } else if ASCII.isDigit(unit)
                || unit == ASCII.hyphen && index + 1 < units.count && ASCII.isDigit(units[index + 1])
            {
                index = scanNumber(from: index)
            } else if ASCII.isIdentifierStart(unit) {
                index = scanBareWord(from: index)
            } else {
                index += 1
            }
        }
        return tokens
    }

    private func isAtLineStart(_ index: Int) -> Bool {
        var cursor = index - 1
        while cursor >= 0, units[cursor] == 32 || units[cursor] == 9 { cursor -= 1 }
        return cursor < 0 || units[cursor] == ASCII.newline
    }

    private func matches(_ text: String, at index: Int) -> Bool {
        let pattern = Array(text.utf16)
        guard index + pattern.count <= units.count else { return false }
        for (offset, unit) in pattern.enumerated() where units[index + offset] != unit { return false }
        return true
    }

    /// Whether the next meaningful unit after `index` makes what precedes it a key.
    private func isKey(endingAt index: Int) -> Bool {
        var cursor = index
        while cursor < units.count, units[cursor] == 32 || units[cursor] == 9 { cursor += 1 }
        guard cursor < units.count else { return false }
        switch format {
            case .json: return units[cursor] == ASCII.colon
            case .toml: return units[cursor] == ASCII.equals || units[cursor] == ASCII.dot
            default:
                return units[cursor] == ASCII.colon && (cursor + 1 >= units.count || ASCII.isSpace(units[cursor + 1]))
        }
    }

    private mutating func scanUntilNewline(from start: Int, kind: TokenKind) -> Int {
        var index = start
        while index < units.count, units[index] != ASCII.newline { index += 1 }
        tokens.append(Token(kind: kind, range: start ..< index))
        return index
    }

    private mutating func scanQuoted(from start: Int, quote: Unit) -> Int {
        let isTriple =
            format == .toml && start + 2 < units.count && units[start + 1] == quote && units[start + 2] == quote
        var index = start + (isTriple ? 3 : 1)
        while index < units.count {
            let unit = units[index]
            if unit == ASCII.backslash, quote == ASCII.quote {
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
            } else if unit == ASCII.newline {
                break
            }
            index += 1
        }
        index = min(index, units.count)
        tokens.append(Token(kind: isKey(endingAt: index) ? .attributeName : .string, range: start ..< index))
        return index
    }

    private mutating func scanNumber(from start: Int) -> Int {
        var index = start + 1
        while index < units.count,
            ASCII.isIdentifier(units[index]) || units[index] == ASCII.dot || units[index] == ASCII.hyphen
                || units[index] == ASCII.colon || units[index] == ASCII.plus
        {
            if units[index] == ASCII.colon, format != .toml { break }
            index += 1
        }
        if isKey(endingAt: index) {
            tokens.append(Token(kind: .attributeName, range: start ..< index))
        } else {
            tokens.append(Token(kind: .number, range: start ..< index))
        }
        return index
    }

    private mutating func scanBareWord(from start: Int) -> Int {
        var index = start
        while index < units.count,
            ASCII.isIdentifier(units[index]) || units[index] == ASCII.hyphen
                || (format == .yaml && units[index] == 32 && index + 1 < units.count
                    && ASCII.isIdentifier(units[index + 1]) && isBareKeyLine(start))
        {
            index += 1
        }
        if isKey(endingAt: index) {
            tokens.append(Token(kind: .attributeName, range: start ..< index))
        } else {
            let word = Unit.text(units[start ..< index])
            if [
                "true", "false", "null", "yes", "no", "on", "off", "inf", "nan", "True", "False", "Null", "TRUE",
                "FALSE", "NULL"
            ]
            .contains(word) {
                tokens.append(Token(kind: .keyword, range: start ..< index))
            }
        }
        return index
    }

    /// YAML keys may contain spaces; only a word that starts a line (after indent and an optional `- `) can be one.
    private func isBareKeyLine(_ start: Int) -> Bool {
        var cursor = start - 1
        while cursor >= 0, units[cursor] == 32 || units[cursor] == 9 { cursor -= 1 }
        if cursor >= 0, units[cursor] == ASCII.hyphen {
            cursor -= 1
            while cursor >= 0, units[cursor] == 32 || units[cursor] == 9 { cursor -= 1 }
        }
        return cursor < 0 || units[cursor] == ASCII.newline
    }
}
