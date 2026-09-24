public import AtelierDiff
public import AtelierSyntaxModel
import SwiftParser
import SwiftSyntax

/// Token boundaries per line for the syntax tier of the intraline diff: swift-syntax tokens for Swift, with comments
/// split into words, and the code-aware lexer for every other language.
public struct SwiftSyntaxTokenRanges: SelectedSyntaxTokenRanging {
    public init() {}

    /// - Complexity: O(text) plus one swift-syntax parse for Swift.
    public func tokenRangesByLine(text: String, language: Language) -> [[Range<Int>]] {
        switch language {
            case .swift:
                let ranges = Self.swiftTokenRanges(text: text, selectedLines: nil)
                return Self.splitByLine(
                    Self.utf16Ranges(from: ranges, in: text), text: text, lineCount: Self.lineCount(text))
            default:
                return CodeTokenRanges().tokenRangesByLine(text: text, language: language)
        }
    }

    /// Returns ranges only for requested lines, preserving whole-side token boundaries across lines.
    /// - Parameters:
    ///   - text: The whole side, separated into lines by `\n`.
    ///   - language: The language that selects the Swift parser or code-aware lexer.
    ///   - lineIndices: Zero-based line indices to convert; invalid indices are ignored.
    /// - Returns: UTF-16 ranges relative to each valid requested line.
    /// - Complexity: O(text + returned ranges) plus one swift-syntax parse for Swift.
    public func tokenRangesByLine(text: String, language: Language, lineIndices: [Int]) -> [Int: [Range<Int>]] {
        switch language {
            case .swift:
                let lines = Self.selectedLines(in: text, indices: Set(lineIndices))
                guard !lines.isEmpty else { return [:] }
                let ranges = Self.swiftTokenRanges(text: text, selectedLines: lines)
                return Self.splitSelected(Self.utf16Ranges(from: ranges, in: text), among: lines)
            default:
                let lines = DiffModel.lines(of: text)
                var selected: [Int: [Range<Int>]] = [:]
                selected.reserveCapacity(lineIndices.count)
                for index in lineIndices where lines.indices.contains(index) {
                    selected[index] = IntralineTokenizer.codeTokens(Array(lines[index].utf16))
                }
                return selected
        }
    }

    private struct LineSpan {
        let index: Int
        let utf8: Range<Int>
        let utf16: Range<Int>
    }

    private struct RangeCollector {
        let selectedLines: [LineSpan]?
        var selectedCursor = 0
        var ranges: [Range<Int>] = []

        mutating func intersects(_ range: Range<Int>) -> Bool {
            guard let selectedLines else { return true }
            while selectedCursor < selectedLines.count,
                selectedLines[selectedCursor].utf8.upperBound <= range.lowerBound
            {
                selectedCursor += 1
            }
            return selectedCursor < selectedLines.count
                && selectedLines[selectedCursor].utf8.lowerBound < range.upperBound
        }

        mutating func append(_ range: Range<Int>) {
            if intersects(range) { ranges.append(range) }
        }
    }

    /// Parsed and walked on ``SwiftSyntaxStack``: a side whose brackets never close nests past a worker thread's stack.
    private static func swiftTokenRanges(text: String, selectedLines: [LineSpan]?) -> [Range<Int>] {
        SwiftSyntaxStack.run {
            var collector = RangeCollector(selectedLines: selectedLines)
            let tree = Parser.parse(source: text)
            for token in tree.tokens(viewMode: .sourceAccurate) {
                if let last = selectedLines?.last, token.position.utf8Offset >= last.utf8.upperBound { break }
                var offset = token.position.utf8Offset
                for piece in token.leadingTrivia.pieces {
                    append(trivia: piece, at: offset, to: &collector)
                    offset += piece.sourceLength.utf8Length
                }
                let length = token.text.utf8.count
                if length > 0 {
                    collector.append(offset ..< (offset + length))
                }
                offset += length
                for piece in token.trailingTrivia.pieces {
                    append(trivia: piece, at: offset, to: &collector)
                    offset += piece.sourceLength.utf8Length
                }
            }
            return collector.ranges
        }
    }

    /// Comments are split into words so a changed word inside a comment is emphasized on its own.
    private static func append(trivia piece: TriviaPiece, at offset: Int, to collector: inout RangeCollector) {
        switch piece {
            case .lineComment(let text), .blockComment(let text), .docLineComment(let text), .docBlockComment(let text):
                guard collector.intersects(offset ..< (offset + piece.sourceLength.utf8Length)) else { return }
                var utf16Offset = 0
                var utf8Offset = 0
                var index = text.utf16.startIndex
                func advance(to target: Int) -> Int {
                    let next = text.utf16.index(index, offsetBy: target - utf16Offset)
                    utf8Offset += text.utf8.distance(from: index, to: next)
                    utf16Offset = target
                    index = next
                    return utf8Offset
                }
                for word in IntralineTokenizer.words(Array(text.utf16)) {
                    let start = advance(to: word.lowerBound)
                    let end = advance(to: word.upperBound)
                    collector.append((offset + start) ..< (offset + end))
                }
            case .spaces(let count), .tabs(let count):
                collector.append(offset ..< (offset + count))
            default:
                break
        }
    }

    private static func lineCount(_ text: String) -> Int {
        var newlines = 0
        var lastByte: UInt8?
        for byte in text.utf8 {
            if byte == 10 { newlines += 1 }
            lastByte = byte
        }
        guard let lastByte else { return 0 }
        return newlines + (lastByte == 10 ? 0 : 1)
    }

    private static func selectedLines(in text: String, indices: Set<Int>) -> [LineSpan] {
        var selected: [LineSpan] = []
        selected.reserveCapacity(indices.count)
        var line = 0
        var lineUTF8Start = 0
        var lineUTF16Start = 0
        var utf8Offset = 0
        var utf16Offset = 0
        var lastByte: UInt8?
        for byte in text.utf8 {
            if byte == 10, indices.contains(line) {
                selected.append(
                    LineSpan(index: line, utf8: lineUTF8Start ..< utf8Offset, utf16: lineUTF16Start ..< utf16Offset))
            }
            utf8Offset += 1
            if byte & 0xC0 != 0x80 {
                utf16Offset += byte >= 0xF0 ? 2 : 1
            }
            if byte == 10 {
                line += 1
                lineUTF8Start = utf8Offset
                lineUTF16Start = utf16Offset
            }
            lastByte = byte
        }
        if lastByte != nil, lastByte != 10, indices.contains(line) {
            selected.append(
                LineSpan(index: line, utf8: lineUTF8Start ..< utf8Offset, utf16: lineUTF16Start ..< utf16Offset))
        }
        return selected
    }

    private static func splitSelected(_ ranges: [Range<Int>], among lines: [LineSpan]) -> [Int: [Range<Int>]] {
        var result: [Int: [Range<Int>]] = [:]
        result.reserveCapacity(lines.count)
        for line in lines { result[line.index] = [] }
        var cursor = 0
        for range in ranges {
            while cursor < lines.count, lines[cursor].utf16.upperBound <= range.lowerBound {
                cursor += 1
            }
            var current = cursor
            while current < lines.count, lines[current].utf16.lowerBound < range.upperBound {
                let line = lines[current]
                let start = max(range.lowerBound, line.utf16.lowerBound)
                let end = min(range.upperBound, line.utf16.upperBound)
                if end > start {
                    result[line.index, default: []]
                        .append(
                            (start - line.utf16.lowerBound) ..< (end - line.utf16.lowerBound))
                }
                current += 1
            }
        }
        return result
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
        // The model has no line after a closing newline; the last kept line then ends before that newline.
        let keptLines = max(lineCount, 1)
        let lastLineEnd = lineStarts.count > keptLines ? lineStarts[keptLines] - 1 : text.utf16.count
        if lineStarts.count > keptLines { lineStarts.removeLast(lineStarts.count - keptLines) }
        let tokens = ranges.map { HighlightToken(byteRange: $0, role: .keyword) }
        return HighlightToken.byLine(tokens, lineStarts: lineStarts, textLength: lastLineEnd)
            .map { $0.map(\.byteRange) }
    }
}
