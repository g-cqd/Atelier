import SwiftParser
import SwiftSyntax

/// Token boundaries per line, as UTF-16 ranges relative to the line, for the syntax tier of the intraline diff.
public enum SyntaxTokenizer {
    /// - Complexity: O(text) plus one swift-syntax parse for Swift.
    public static func tokenRangesByLine(text: String, language: Language) -> [[Range<Int>]] {
        let lines = DiffModel.lines(of: text)
        switch language {
            case .swift:
                return swiftTokenRangesByLine(text: text, lineCount: lines.count)
            default:
                return lines.map { IntralineTokenizer.codeTokens(Array($0.utf16)) }
        }
    }

    private static func swiftTokenRangesByLine(text: String, lineCount: Int) -> [[Range<Int>]] {
        var utf8Ranges: [Range<Int>] = []
        let tree = Parser.parse(source: text)
        for token in tree.tokens(viewMode: .sourceAccurate) {
            var offset = token.position.utf8Offset
            for piece in token.leadingTrivia.pieces {
                append(trivia: piece, at: offset, to: &utf8Ranges)
                offset += piece.sourceLength.utf8Length
            }
            let length = token.text.utf8.count
            if length > 0 {
                utf8Ranges.append(offset ..< (offset + length))
            }
            offset += length
            for piece in token.trailingTrivia.pieces {
                append(trivia: piece, at: offset, to: &utf8Ranges)
                offset += piece.sourceLength.utf8Length
            }
        }
        return splitByLine(utf16Ranges(from: utf8Ranges, in: text), text: text, lineCount: lineCount)
    }

    /// Comments are split into words so a changed word inside a comment is emphasized on its own.
    private static func append(trivia piece: TriviaPiece, at offset: Int, to ranges: inout [Range<Int>]) {
        switch piece {
            case .lineComment(let text), .blockComment(let text), .docLineComment(let text), .docBlockComment(let text):
                for word in IntralineTokenizer.words(Array(text.utf16)) {
                    let start = utf8Offset(of: word.lowerBound, inUTF16Of: text)
                    let end = utf8Offset(of: word.upperBound, inUTF16Of: text)
                    ranges.append((offset + start) ..< (offset + end))
                }
            case .spaces(let count), .tabs(let count):
                ranges.append(offset ..< (offset + count))
            default:
                break
        }
    }

    private static func utf8Offset(of utf16Offset: Int, inUTF16Of text: String) -> Int {
        let index = text.utf16.index(text.utf16.startIndex, offsetBy: utf16Offset)
        return text.utf8.distance(from: text.utf8.startIndex, to: index)
    }

    /// Converts ascending UTF-8 ranges to UTF-16 ranges in one pass over the bytes.
    /// - Complexity: O(text + ranges)
    private static func utf16Ranges(from utf8Ranges: [Range<Int>], in text: String) -> [Range<Int>] {
        var boundaries: [Int] = []
        boundaries.reserveCapacity(utf8Ranges.count * 2)
        for range in utf8Ranges {
            boundaries.append(range.lowerBound)
            boundaries.append(range.upperBound)
        }
        var converted = [Int](repeating: 0, count: boundaries.count)
        var next = 0
        var utf8Offset = 0
        var utf16Offset = 0
        var bytes = text.utf8.makeIterator()
        while next < boundaries.count {
            while next < boundaries.count, boundaries[next] == utf8Offset {
                converted[next] = utf16Offset
                next += 1
            }
            guard let byte = bytes.next() else { break }
            utf8Offset += 1
            if byte & 0xC0 != 0x80 {
                utf16Offset += byte >= 0xF0 ? 2 : 1
            }
        }
        while next < boundaries.count {
            converted[next] = utf16Offset
            next += 1
        }
        return stride(from: 0, to: converted.count, by: 2).map { converted[$0] ..< converted[$0 + 1] }
    }

    private static func splitByLine(_ ranges: [Range<Int>], text: String, lineCount: Int) -> [[Range<Int>]] {
        var lineStarts: [Int] = [0]
        for (offset, unit) in text.utf16.enumerated() where unit == 10 {
            lineStarts.append(offset + 1)
        }
        if lineStarts.count > lineCount { lineStarts.removeLast(lineStarts.count - max(lineCount, 1)) }
        let tokens = ranges.map { Token(kind: .keyword, range: $0) }
        return SyntaxHighlighter.tokensByLine(tokens, lineStarts: lineStarts, textLength: text.utf16.count)
            .map { $0.map(\.range) }
    }
}
