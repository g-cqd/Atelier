extension HighlightToken {
    /// Splits tokens at line boundaries and rebases them on their line.
    /// - Parameters:
    ///   - tokens: Tokens over the whole text, ascending and disjoint.
    ///   - lineStarts: Offset of each line's first unit, ascending, in the unit the tokens are measured in.
    ///   - textLength: Length of the whole text in that unit, which ends the last line.
    /// - Returns: One token array per line, with ranges relative to the line start; a token spanning lines is cut.
    /// - Complexity: O(tokens + lines)
    public static func byLine(_ tokens: [HighlightToken], lineStarts: [Int], textLength: Int) -> [[HighlightToken]] {
        var result = [[HighlightToken]](repeating: [], count: lineStarts.count)
        var line = 0
        for token in tokens {
            while line + 1 < lineStarts.count, lineStarts[line + 1] <= token.byteRange.lowerBound {
                line += 1
            }
            var current = line
            while current < lineStarts.count, lineStarts[current] < token.byteRange.upperBound {
                let base = lineStarts[current]
                let lineEnd = current + 1 < lineStarts.count ? lineStarts[current + 1] - 1 : textLength
                let start = max(token.byteRange.lowerBound, base)
                let end = min(token.byteRange.upperBound, lineEnd)
                if end > start {
                    result[current]
                        .append(
                            HighlightToken(
                                byteRange: (start - base) ..< (end - base), role: token.role,
                                modifiers: token.modifiers,
                                layer: token.layer, priority: token.priority))
                }
                current += 1
            }
        }
        return result
    }
}
