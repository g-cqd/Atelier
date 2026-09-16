struct HTMLScanner<Unit: LexerUnit> {
    let units: [Unit]
    private var tokens: [Token] = []

    init(units: [Unit]) {
        self.units = units
    }

    mutating func scan() -> [Token] {
        var index = 0
        while index < units.count {
            if units[index] == ASCII.lessThan {
                index = scanAngle(from: index)
            } else if units[index] == ASCII.ampersand {
                index = scanEntity(from: index)
            } else {
                index += 1
            }
        }
        return tokens
    }

    private func matches(_ text: String, at index: Int) -> Bool {
        let pattern = Array(text.utf16)
        guard index + pattern.count <= units.count else { return false }
        for (offset, unit) in pattern.enumerated()
        where units[index + offset] != unit && units[index + offset] != unit - 32 {
            return false
        }
        return true
    }

    private func find(_ text: String, from index: Int) -> Int? {
        var cursor = index
        while cursor < units.count {
            if matches(text, at: cursor) { return cursor }
            cursor += 1
        }
        return nil
    }

    private mutating func scanAngle(from start: Int) -> Int {
        if matches("<!--", at: start) {
            let end = find("-->", from: start + 4).map { $0 + 3 } ?? units.count
            tokens.append(Token(kind: .comment, range: start ..< end))
            return end
        }
        if matches("<!", at: start) {
            let end = find(">", from: start).map { $0 + 1 } ?? units.count
            tokens.append(Token(kind: .keyword, range: start ..< end))
            return end
        }
        var index = start + 1
        let isClosing = index < units.count && units[index] == ASCII.slash
        if isClosing { index += 1 }
        guard index < units.count, ASCII.isAlpha(units[index]) else { return start + 1 }

        let nameStart = index
        while index < units.count,
            ASCII.isIdentifier(units[index]) || units[index] == ASCII.hyphen || units[index] == ASCII.colon
        {
            index += 1
        }
        tokens.append(Token(kind: .tag, range: start ..< index))
        let name = Unit.text(units[nameStart ..< index]).lowercased()

        index = scanAttributes(from: index)
        if !isClosing, name == "script" || name == "style" {
            index = find("</\(name)", from: index) ?? units.count
        }
        return index
    }

    private mutating func scanAttributes(from start: Int) -> Int {
        var index = start
        while index < units.count {
            let unit = units[index]
            if unit == ASCII.greaterThan {
                tokens.append(Token(kind: .tag, range: index ..< (index + 1)))
                return index + 1
            }
            if unit == ASCII.slash, index + 1 < units.count, units[index + 1] == ASCII.greaterThan {
                tokens.append(Token(kind: .tag, range: index ..< (index + 2)))
                return index + 2
            }
            if unit == ASCII.quote || unit == ASCII.apostrophe {
                let valueStart = index
                index += 1
                while index < units.count, units[index] != unit { index += 1 }
                index = min(index + 1, units.count)
                tokens.append(Token(kind: .string, range: valueStart ..< index))
            } else if ASCII.isIdentifierStart(unit) {
                let nameStart = index
                while index < units.count,
                    ASCII.isIdentifier(units[index]) || units[index] == ASCII.hyphen || units[index] == ASCII.colon
                {
                    index += 1
                }
                tokens.append(Token(kind: .attributeName, range: nameStart ..< index))
            } else {
                index += 1
            }
        }
        return index
    }

    private mutating func scanEntity(from start: Int) -> Int {
        var index = start + 1
        while index < units.count, index - start < 12, ASCII.isIdentifier(units[index]) || units[index] == ASCII.hash {
            index += 1
        }
        guard index < units.count, units[index] == ASCII.semicolon, index > start + 1 else { return start + 1 }
        tokens.append(Token(kind: .entity, range: start ..< (index + 1)))
        return index + 1
    }
}
