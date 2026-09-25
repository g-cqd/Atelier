/// Tokens cut at line boundaries and rebased on their line, with every line's tokens in one flat buffer.
///
/// Line `i`'s tokens are `tokens[offsets[i] ..< offsets[i + 1]]`, each range relative to the line's start, so a whole
/// document costs two allocations rather than one array per line. As a collection it holds one slice of tokens per
/// line, and reads as `[[HighlightToken]]` did: `lineTokens[i]`, `lineTokens.count`.
///
/// A second per-token buffer can share `offsets`: for token `k` of line `i`, `k` indexes both buffers.
///
/// The ranges are in the unit the tokens were cut in, until ``moveToUTF16(over:lineRanges:)`` moves them from UTF-8 to
/// UTF-16.
public struct LineTokens: Sendable, Equatable, RandomAccessCollection {
    /// Every line's tokens, line after line, each range relative to its line's start.
    public private(set) var tokens: [HighlightToken]
    /// Where each line's tokens start in `tokens`, plus the end of the last line's: one more entry than lines.
    public private(set) var offsets: [UInt32]

    public var startIndex: Int { 0 }
    public var endIndex: Int { offsets.count - 1 }

    /// Line `line`'s tokens, ascending and disjoint, each range relative to the line's start.
    public subscript(line: Int) -> ArraySlice<HighlightToken> {
        tokens[tokenIndices(ofLine: line)]
    }

    /// Where line `line`'s tokens lie in `tokens`.
    public func tokenIndices(ofLine line: Int) -> Range<Int> {
        Int(offsets[line]) ..< Int(offsets[line + 1])
    }

    /// `lineCount` lines without a token, the result for a text that is not scanned.
    public init(emptyLines lineCount: Int) {
        tokens = []
        offsets = [UInt32](repeating: 0, count: lineCount + 1)
    }

    /// Cuts `tokens` at the lines that `lineStarts` and `textLength` bound, into the lines
    /// ``HighlightToken/byLine(_:lineStarts:textLength:)`` returns.
    /// - Parameters:
    ///   - tokens: Tokens over the whole text, ascending and disjoint.
    ///   - lineStarts: Offset of each line's first unit, ascending, in the unit the tokens are measured in. A line ends
    ///     one unit before the next line starts, at its line break.
    ///   - textLength: Length of the whole text in that unit, which ends the last line.
    /// - Complexity: O(tokens + lines), in two allocations.
    public init(_ tokens: [HighlightToken], lineStarts: [Int], textLength: Int) {
        self.init(tokens, bounds: StartsAndLength(starts: lineStarts, textLength: textLength))
    }

    /// Cuts `tokens` at the lines `lineRanges` gives, each line ending where its own text does, before any line break.
    /// - Parameters:
    ///   - tokens: Tokens over the whole text, ascending and disjoint.
    ///   - lineRanges: Each line's text within the whole text, ascending and disjoint, in the tokens' unit.
    /// - Complexity: O(tokens + lines), in two allocations.
    public init(_ tokens: [HighlightToken], lineRanges: [Range<Int>]) {
        self.init(tokens, bounds: Ranges(ranges: lineRanges))
    }

    /// Moves every line's tokens from UTF-8 offsets to UTF-16 offsets, both from the line's start, in one pass over
    /// `text`. A byte before a line's first non-ASCII byte is one unit, so the ASCII stretches are skipped eight bytes
    /// at a time, and a line walks its bytes only from its first non-ASCII byte to its last token's end.
    /// - Parameters:
    ///   - text: The whole text's UTF-8, which the tokens were cut from.
    ///   - lineRanges: The ranges the tokens were cut at, in bytes of `text`.
    /// - Complexity: O(bytes of `text` + tokens)
    public mutating func moveToUTF16(over text: Span<UInt8>, lineRanges: [Range<Int>]) {
        let offsets = offsets
        var tokens = tokens.mutableSpan
        // The first non-ASCII byte at or after the start of the last line that looked for one.
        var nonASCII = -1
        for line in lineRanges.indices {
            let first = Int(offsets[line])
            let past = Int(offsets[line + 1])
            guard first < past else { continue }
            let start = lineRanges[line].lowerBound
            if nonASCII < start { nonASCII = UTF16Offsets.firstNonASCII(in: text, from: start) }
            guard nonASCII < start + tokens[past - 1].byteRange.upperBound else { continue }
            let prefix = nonASCII - start
            var byte = nonASCII
            var unit = prefix
            for index in first ..< past {
                let token = tokens[index]
                let range = token.byteRange
                guard range.upperBound > prefix else { continue }
                var lower = range.lowerBound
                if lower > prefix {
                    UTF16Offsets.advance(&byte, to: start + lower, in: text, counting: &unit)
                    lower = unit
                }
                UTF16Offsets.advance(&byte, to: start + range.upperBound, in: text, counting: &unit)
                tokens[index] = HighlightToken(
                    byteRange: lower ..< unit, role: token.role, modifiers: token.modifiers, layer: token.layer,
                    priority: token.priority)
            }
        }
    }

    /// One pass over the tokens: lines only move forward, since the tokens are ascending and disjoint, so each token's
    /// pieces go at the end of the flat buffer and a line's offset is set when a later line takes its first piece.
    /// Generic rather than over a closure, so each kind of bounds is specialized and inlined.
    private init<Bounds: LineBounds>(_ tokens: [HighlightToken], bounds: Bounds) {
        let lineCount = bounds.count
        var flat: [HighlightToken] = []
        flat.reserveCapacity(tokens.count)
        var offsets: [UInt32] = []
        offsets.reserveCapacity(lineCount + 1)
        offsets.append(0)
        var line = 0
        for token in tokens {
            let lower = token.byteRange.lowerBound
            let upper = token.byteRange.upperBound
            while line + 1 < lineCount, bounds.start(of: line + 1) <= lower {
                line += 1
            }
            var current = line
            while current < lineCount {
                let lineStart = bounds.start(of: current)
                guard lineStart < upper else { break }
                let start = Swift.max(lower, lineStart)
                let end = Swift.min(upper, bounds.end(of: current))
                if end > start {
                    while offsets.count <= current { offsets.append(UInt32(flat.count)) }
                    flat.append(
                        HighlightToken(
                            byteRange: (start - lineStart) ..< (end - lineStart), role: token.role,
                            modifiers: token.modifiers, layer: token.layer, priority: token.priority))
                }
                current += 1
            }
        }
        while offsets.count <= lineCount { offsets.append(UInt32(flat.count)) }
        self.tokens = flat
        self.offsets = offsets
    }
}

/// Where each line of a text starts and ends, in the tokens' unit.
private protocol LineBounds {
    var count: Int { get }
    func start(of line: Int) -> Int
    /// The end of the line's text; before `start(of:)` for a line with none, which then takes no token.
    func end(of line: Int) -> Int
}

/// Lines from their starts: each ends one unit before the next starts, at its line break, and the last at the text's
/// end.
private struct StartsAndLength: LineBounds {
    let starts: [Int]
    let textLength: Int

    var count: Int { starts.count }

    @inline(__always)
    func start(of line: Int) -> Int { starts[line] }

    @inline(__always)
    func end(of line: Int) -> Int { line + 1 < starts.count ? starts[line + 1] - 1 : textLength }
}

/// Lines from their text's ranges.
private struct Ranges: LineBounds {
    let ranges: [Range<Int>]

    var count: Int { ranges.count }

    @inline(__always)
    func start(of line: Int) -> Int { ranges[line].lowerBound }

    @inline(__always)
    func end(of line: Int) -> Int { ranges[line].upperBound }
}
