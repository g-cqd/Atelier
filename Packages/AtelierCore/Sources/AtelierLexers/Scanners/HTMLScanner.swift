/// Scans HTML and XML over borrowed UTF-8 bytes: tags, attribute names and values, comments, declarations and
/// entities. The body of a `script` or `style` element is skipped, not scanned.
struct HTMLScanner {
    private static let commentStart = Array("<!--".utf8)
    private static let commentEnd = Array("-->".utf8)
    private static let declarationStart = Array("<!".utf8)
    private static let declarationEnd = Array(">".utf8)
    private static let script = Array("script".utf8)
    private static let style = Array("style".utf8)
    private static let scriptEnd = Array("</script".utf8)
    private static let styleEnd = Array("</style".utf8)

    func scan<Output: ScannerToken>(_ units: Span<UInt8>, as: Output.Type) -> [Output] {
        var tokens: [Output] = []
        tokens.reserveCapacity(units.count / 16 + 16)
        var index = 0
        while index < units.count {
            if units[index] == ASCII.lessThan {
                index = scanAngle(units, from: index, tokens: &tokens)
            } else if units[index] == ASCII.ampersand {
                index = scanEntity(units, from: index, tokens: &tokens)
            } else {
                index += 1
            }
        }
        return tokens
    }

    /// Whether `pattern` starts at `index`. A byte also matches its pattern byte minus 32, which lets an uppercase
    /// letter match a lowercase one; it also lets a few control characters stand for punctuation, as it always has.
    private func matches(_ pattern: [UInt8], in units: Span<UInt8>, at index: Int) -> Bool {
        guard pattern.count <= units.count - index else { return false }
        for offset in pattern.indices {
            let unit = units[index + offset]
            if unit != pattern[offset], unit != pattern[offset] &- 32 { return false }
        }
        return true
    }

    private func find(_ pattern: [UInt8], in units: Span<UInt8>, from index: Int) -> Int? {
        var cursor = index
        while cursor < units.count {
            if matches(pattern, in: units, at: cursor) { return cursor }
            cursor += 1
        }
        return nil
    }

    private func scanAngle<Output: ScannerToken>(
        _ units: Span<UInt8>, from start: Int, tokens: inout [Output]
    ) -> Int {
        if matches(Self.commentStart, in: units, at: start) {
            let end = find(Self.commentEnd, in: units, from: start + 4).map { $0 + 3 } ?? units.count
            tokens.append(Output(kind: .comment, range: start ..< end))
            return end
        }
        if matches(Self.declarationStart, in: units, at: start) {
            let end = find(Self.declarationEnd, in: units, from: start).map { $0 + 1 } ?? units.count
            tokens.append(Output(kind: .keyword, range: start ..< end))
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
        tokens.append(Output(kind: .tag, range: start ..< index))
        let nameEnd = index
        index = scanAttributes(units, from: index, tokens: &tokens)
        guard !isClosing else { return index }
        if isName(Self.script, in: units, nameStart ..< nameEnd) {
            return find(Self.scriptEnd, in: units, from: index) ?? units.count
        }
        if isName(Self.style, in: units, nameStart ..< nameEnd) {
            return find(Self.styleEnd, in: units, from: index) ?? units.count
        }
        return index
    }

    /// Whether the tag name in `range` is `name`, in any case.
    private func isName(_ name: [UInt8], in units: Span<UInt8>, _ range: Range<Int>) -> Bool {
        guard range.count == name.count else { return false }
        for offset in name.indices where units[range.lowerBound + offset] | 0x20 != name[offset] { return false }
        return true
    }

    private func scanAttributes<Output: ScannerToken>(
        _ units: Span<UInt8>, from start: Int, tokens: inout [Output]
    ) -> Int {
        var index = start
        while index < units.count {
            let unit = units[index]
            if unit == ASCII.greaterThan {
                tokens.append(Output(kind: .tag, range: index ..< (index + 1)))
                return index + 1
            }
            if unit == ASCII.slash, index + 1 < units.count, units[index + 1] == ASCII.greaterThan {
                tokens.append(Output(kind: .tag, range: index ..< (index + 2)))
                return index + 2
            }
            if unit == ASCII.quote || unit == ASCII.apostrophe {
                let valueStart = index
                index += 1
                while index < units.count, units[index] != unit { index += 1 }
                index = min(index + 1, units.count)
                tokens.append(Output(kind: .string, range: valueStart ..< index))
            } else if ASCII.isIdentifierStart(unit) {
                let nameStart = index
                while index < units.count,
                    ASCII.isIdentifier(units[index]) || units[index] == ASCII.hyphen || units[index] == ASCII.colon
                {
                    index += 1
                }
                tokens.append(Output(kind: .attributeName, range: nameStart ..< index))
            } else {
                index += 1
            }
        }
        return index
    }

    private func scanEntity<Output: ScannerToken>(
        _ units: Span<UInt8>, from start: Int, tokens: inout [Output]
    ) -> Int {
        var index = start + 1
        // Entity names are ASCII, which keeps the 12-byte cap the same length in UTF-8 and in UTF-16.
        while index < units.count, index - start < 12,
            ASCII.isAlpha(units[index]) || ASCII.isDigit(units[index]) || units[index] == ASCII.hash
        {
            index += 1
        }
        guard index < units.count, units[index] == ASCII.semicolon, index > start + 1 else { return start + 1 }
        tokens.append(Output(kind: .entity, range: start ..< (index + 1)))
        return index + 1
    }
}
