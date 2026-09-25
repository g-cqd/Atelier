import AtelierLexers
public import AtelierSyntaxModel

/// The identifier under a position, read from the text and the lexical scanner's tokens, with no parser: a run of
/// letters, digits, `_` and, outside Go, `$`, that the scanner did not read as a keyword, a literal or a comment.
public struct LexicalIdentifierLocator: IdentifierLocating {
    public init() {}

    public func identifier(in text: String, language: Language, line: Int, utf16Column: Int) async -> String? {
        Self.identifier(in: text, language: language, line: line, utf16Column: utf16Column)
    }

    /// The identifier covering `(line, utf16Column)`, zero-based, in UTF-16 units, or ending right before it; nil over
    /// anything else, past the line's end, or for `.plain` text.
    /// - Complexity: O(UTF-16 length of `text`), with one lexical scan.
    public static func identifier(in text: String, language: Language, line: Int, utf16Column: Int) -> String? {
        guard language != .plain, line >= 0, utf16Column >= 0 else { return nil }
        let units = Array(text.utf16)
        guard let lineStart = start(ofLine: line, in: units) else { return nil }
        var lineEnd = lineStart
        while lineEnd < units.count, units[lineEnd] != UInt16(UInt8(ascii: "\n")) { lineEnd += 1 }
        var position = lineStart + utf16Column
        guard position <= lineEnd else { return nil }
        let allowsDollar = language != .go
        func isIdentifier(_ offset: Int) -> Bool {
            offset >= lineStart && offset < lineEnd && isIdentifierUnit(units[offset], allowsDollar: allowsDollar)
        }
        // A hover right past a name still means the name.
        if !isIdentifier(position), isIdentifier(position - 1) { position -= 1 }
        guard isIdentifier(position) else { return nil }
        var start = position
        while isIdentifier(start - 1) { start -= 1 }
        var end = position
        while isIdentifier(end) { end += 1 }
        let first = units[start]
        guard first < UInt16(UInt8(ascii: "0")) || first > UInt16(UInt8(ascii: "9")) else { return nil }
        let tokens = SyntaxHighlighter.tokens(in: text, language: language)
        let covering = tokens.first { $0.range.contains(start) }
        if let kind = covering?.kind, kind != .type, kind != .attribute { return nil }
        return String(decoding: units[start ..< end], as: UTF16.self)
    }

    /// The UTF-16 offset where zero-based `line` starts; nil past the last line.
    private static func start(ofLine line: Int, in units: [UInt16]) -> Int? {
        var remaining = line
        var index = 0
        while remaining > 0 {
            guard let newline = units[index...].firstIndex(of: UInt16(UInt8(ascii: "\n"))) else { return nil }
            index = newline + 1
            remaining -= 1
        }
        return index
    }

    /// Whether `unit` can be part of an identifier: an ASCII letter, digit or `_`, `$` where the language allows it,
    /// or a letter or digit outside ASCII. A surrogate, half of an emoji or of a rare letter, is not.
    private static func isIdentifierUnit(_ unit: UInt16, allowsDollar: Bool) -> Bool {
        if unit < 0x80 {
            let byte = UInt8(unit)
            let lower = byte | 0x20
            return (lower >= UInt8(ascii: "a") && lower <= UInt8(ascii: "z"))
                || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")) || byte == UInt8(ascii: "_")
                || (allowsDollar && byte == UInt8(ascii: "$"))
        }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
    }
}
