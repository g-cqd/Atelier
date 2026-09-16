import Foundation
public import KittyStyle

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

    /// Resolve merged tokens to styled spans using a theme resolver.
    public static func resolveToSpans(
        tokens: [HighlightToken],
        source: String,
        resolver: RoleBasedThemeResolver,
        defaultStyle: Style
    ) -> [StyledSpan] {
        guard !tokens.isEmpty else {
            return source.isEmpty ? [] : [StyledSpan(text: source, style: defaultStyle)]
        }

        let utf8 = Array(source.utf8)
        var spans: [StyledSpan] = []
        var pos = 0

        for token in tokens {
            let start = max(token.byteRange.lowerBound, 0)
            let end = min(token.byteRange.upperBound, utf8.count)
            guard start < end else { continue }

            // Fill gap before this token with default style
            if pos < start {
                let gapText =
                    String(bytes: utf8[pos ..< start], encoding: .utf8)
                    ?? String(decoding: utf8[pos ..< start], as: UTF8.self)
                if !gapText.isEmpty {
                    spans.append(StyledSpan(text: gapText, style: defaultStyle))
                }
            }

            let text =
                String(bytes: utf8[start ..< end], encoding: .utf8)
                ?? String(decoding: utf8[start ..< end], as: UTF8.self)
            if !text.isEmpty {
                let style = resolver.resolve(role: token.role, modifiers: token.modifiers)
                spans.append(StyledSpan(text: text, style: style))
            }
            pos = end
        }

        // Trailing gap
        if pos < utf8.count {
            let text =
                String(bytes: utf8[pos...], encoding: .utf8)
                ?? String(decoding: utf8[pos...], as: UTF8.self)
            if !text.isEmpty {
                spans.append(StyledSpan(text: text, style: defaultStyle))
            }
        }

        return spans
    }
}
