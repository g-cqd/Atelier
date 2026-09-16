import Foundation

/// Merges highlight tokens from multiple layers into a single non-overlapping sequence.
///
/// Precedence rules:
/// 1. Higher layer wins (semantic > structural > lexical)
/// 2. Within the same layer, higher priority wins
/// 3. Within the same layer and priority, narrower range wins
public enum HighlightMerger: Sendable {
    /// Merge tokens from multiple layers into non-overlapping tokens.
    /// The input tokens may overlap; the output tokens will not.
    public static func merge(
        _ tokens: [HighlightToken],
        sourceByteCount: Int
    ) -> [HighlightToken] {
        guard !tokens.isEmpty, sourceByteCount > 0 else { return [] }

        // Sort: broader ranges first, then lower layer/priority first,
        // so that later (higher-priority) writes overwrite earlier ones.
        let sorted = tokens.sorted { a, b in
            let aSize = a.byteRange.count
            let bSize = b.byteRange.count
            if aSize != bSize { return aSize > bSize }
            if a.layer != b.layer { return a.layer < b.layer }
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
