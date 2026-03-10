import KittyCodecs
import KittyGrammar
import KittyParser
import KittyQuery

/// Combines parsing, querying, and theming to produce styled text.
public final class Highlighter: Sendable {
    private let theme: Theme

    public init(theme: Theme = .monokai) {
        self.theme = theme
    }

    /// Highlight source code given a pre-parsed syntax tree and query.
    public func highlight(
        source: String,
        tree: SyntaxTree,
        query: Query
    ) -> [StyledSpan] {
        let matches = QueryMatcher.execute(query: query, tree: tree)
        return buildSpans(source: source, matches: matches)
    }

    private func buildSpans(source: String, matches: [QueryMatch]) -> [StyledSpan] {
        let utf8 = Array(source.utf8)
        guard !utf8.isEmpty else {
            return [StyledSpan(text: source, style: theme.defaultStyle)]
        }

        // Collect all captures with byte ranges and pattern index
        var rawSpans: [(byteRange: Range<Int>, style: Style, patternIndex: Int)] = []
        for match in matches {
            for capture in match.captures {
                let style = theme.style(for: capture.name)
                rawSpans.append((byteRange: capture.node.byteRange, style: style, patternIndex: match.patternIndex))
            }
        }
        guard !rawSpans.isEmpty else {
            return [StyledSpan(text: source, style: theme.defaultStyle)]
        }

        // Sort: larger ranges first, then earlier patterns first.
        // This way, more specific (smaller/later) captures override broader ones.
        rawSpans.sort { a, b in
            let aSize = a.byteRange.count
            let bSize = b.byteRange.count
            if aSize != bSize { return aSize > bSize }
            if a.patternIndex != b.patternIndex { return a.patternIndex < b.patternIndex }
            if a.byteRange.lowerBound != b.byteRange.lowerBound { return a.byteRange.lowerBound < b.byteRange.lowerBound }
            return a.byteRange.upperBound < b.byteRange.upperBound
        }

        // Build per-byte style map
        var byteStyles = [Style?](repeating: nil, count: utf8.count)
        for span in rawSpans {
            let start = min(max(span.byteRange.lowerBound, 0), utf8.count)
            let end = min(max(span.byteRange.upperBound, start), utf8.count)
            for i in start..<end {
                byteStyles[i] = span.style
            }
        }

        // Coalesce into spans
        var spans: [StyledSpan] = []
        var pos = 0
        while pos < utf8.count {
            let style = byteStyles[pos] ?? theme.defaultStyle
            var end = pos + 1
            while end < utf8.count && (byteStyles[end] ?? theme.defaultStyle) == style {
                end += 1
            }
            if let text = String(bytes: utf8[pos..<end], encoding: .utf8), !text.isEmpty {
                spans.append(StyledSpan(text: text, style: style))
            }
            pos = end
        }
        return spans
    }
}

// MARK: - Styled Span

public struct StyledSpan: Sendable, Equatable {
    public var text: String
    public var style: Style

    public init(text: String, style: Style) {
        self.text = text
        self.style = style
    }
}
