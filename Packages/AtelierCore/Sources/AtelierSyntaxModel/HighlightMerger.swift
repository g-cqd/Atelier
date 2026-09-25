import Foundation

/// Merges highlight tokens from multiple layers into a single non-overlapping sequence.
///
/// Where tokens overlap, each byte takes the token that wins it:
/// 1. The higher layer wins: semantic over syntactic over structural over lexical, however narrow the lower token.
/// 2. Within a layer, the narrower token wins, so a token nested in another shows through it: an escape sequence keeps
///    its colour inside a string, although the query lists the string's pattern first.
/// 3. Within a layer and a width, the higher priority wins: on identical ranges, the earlier query pattern, which
///    `buildTokens` gives the higher priority.
///
/// The merge sorts the tokens by layer, then by width, wider first, then by priority, lower first, and paints them in
/// that order, so each token overwrites the bytes of those it wins over.
public enum HighlightMerger: Sendable {
    /// Merge tokens from multiple layers into non-overlapping tokens.
    /// The input tokens may overlap; the output tokens will not.
    public static func merge(
        _ tokens: [HighlightToken],
        sourceByteCount: Int
    ) -> [HighlightToken] {
        guard !tokens.isEmpty, sourceByteCount > 0 else { return [] }

        // Painted in this order, a later token overwrites an earlier one: layer, then width, then priority.
        let sorted = tokens.sorted { a, b in
            if a.layer != b.layer { return a.layer < b.layer }
            let aSize = a.byteRange.count
            let bSize = b.byteRange.count
            if aSize != bSize { return aSize > bSize }
            if a.priority != b.priority { return a.priority < b.priority }
            return a.byteRange.lowerBound < b.byteRange.lowerBound
        }

        // Per-byte token index assignment (similar to Highlighter.buildSpans)
        var byteTokenIdx = [Int](repeating: -1, count: sourceByteCount)

        for (idx, token) in sorted.enumerated() {
            let start = max(token.byteRange.lowerBound, 0)
            let end = min(token.byteRange.upperBound, sourceByteCount)
            for i in start ..< end {
                byteTokenIdx[i] = idx
            }
        }

        // Coalesce into non-overlapping tokens
        var result: [HighlightToken] = []
        var pos = 0

        while pos < sourceByteCount {
            let tokenIdx = byteTokenIdx[pos]
            guard tokenIdx >= 0 else {
                pos += 1
                continue
            }

            let token = sorted[tokenIdx]
            var end = pos + 1
            while end < sourceByteCount && byteTokenIdx[end] == tokenIdx {
                end += 1
            }

            result.append(
                HighlightToken(
                    byteRange: pos ..< end,
                    role: token.role,
                    modifiers: token.modifiers,
                    layer: token.layer,
                    priority: token.priority
                ))
            pos = end
        }

        return result
    }
}
