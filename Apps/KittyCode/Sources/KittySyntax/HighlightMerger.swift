public import AtelierSyntaxModel
import Foundation
public import KittyStyle

extension HighlightMerger {
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
        return resolveToSpans(tokens: tokens, utf8: utf8[...], resolver: resolver, defaultStyle: defaultStyle)
    }

    /// Resolve tokens over one run of bytes to styled spans; gaps between tokens take the default style.
    /// Token ranges are relative to the slice's start index.
    /// - Complexity: O(bytes + tokens)
    public static func resolveToSpans(
        tokens: [HighlightToken],
        utf8: ArraySlice<UInt8>,
        resolver: RoleBasedThemeResolver,
        defaultStyle: Style
    ) -> [StyledSpan] {
        let base = utf8.startIndex
        let count = utf8.count
        var spans: [StyledSpan] = []
        spans.reserveCapacity(tokens.count * 2 + 1)
        var pos = 0

        func append(_ range: Range<Int>, _ style: Style) {
            guard !range.isEmpty else { return }
            let text = String(decoding: utf8[(base + range.lowerBound) ..< (base + range.upperBound)], as: UTF8.self)
            spans.append(StyledSpan(text: text, style: style))
        }

        for token in tokens {
            let start = max(token.byteRange.lowerBound, pos)
            let end = min(token.byteRange.upperBound, count)
            guard start < end else { continue }
            append(pos ..< start, defaultStyle)
            append(start ..< end, resolver.resolve(role: token.role, modifiers: token.modifiers))
            pos = end
        }
        append(pos ..< count, defaultStyle)
        return spans
    }

    /// Resolve tokens over a whole document to one span array per line, the shape the terminal renderer paints.
    /// Lines are split on `\n`; a token spanning lines is cut at the boundary; an empty line has no spans.
    /// - Returns: Exactly one entry per line of `utf8` (a document without newlines is one line).
    /// - Complexity: O(bytes + tokens)
    public static func resolveToLines(
        tokens: [HighlightToken],
        utf8: [UInt8],
        resolver: RoleBasedThemeResolver,
        defaultStyle: Style
    ) -> [[StyledSpan]] {
        var lineStarts = [0]
        for (offset, byte) in utf8.enumerated() where byte == 0x0A {
            lineStarts.append(offset + 1)
        }
        let byLine = HighlightToken.byLine(tokens, lineStarts: lineStarts, textLength: utf8.count)
        var lines: [[StyledSpan]] = []
        lines.reserveCapacity(lineStarts.count)
        for (index, start) in lineStarts.enumerated() {
            let end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : utf8.count
            lines.append(
                resolveToSpans(
                    tokens: byLine[index], utf8: utf8[start ..< end], resolver: resolver, defaultStyle: defaultStyle))
        }
        return lines
    }
}
