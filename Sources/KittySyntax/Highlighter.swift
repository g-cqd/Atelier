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
        // Collect all captures with their byte ranges
        var rawSpans: [(byteRange: Range<Int>, style: Style)] = []

        for match in matches {
            for capture in match.captures {
                let style = theme.style(for: capture.name)
                rawSpans.append((byteRange: capture.node.byteRange, style: style))
            }
        }

        // Sort by start position (later captures override earlier)
        rawSpans.sort { $0.byteRange.lowerBound < $1.byteRange.lowerBound }

        guard !rawSpans.isEmpty else {
            return [StyledSpan(text: source, style: theme.defaultStyle)]
        }

        // Build non-overlapping spans
        var spans: [StyledSpan] = []
        let utf8 = Array(source.utf8)
        var pos = 0

        for raw in rawSpans {
            guard raw.byteRange.lowerBound < utf8.count else { continue }

            // Emit unstyled gap
            if raw.byteRange.lowerBound > pos {
                let text = String(bytes: utf8[pos..<raw.byteRange.lowerBound], encoding: .utf8) ?? ""
                if !text.isEmpty {
                    spans.append(StyledSpan(text: text, style: theme.defaultStyle))
                }
            }

            let end = min(raw.byteRange.upperBound, utf8.count)
            if end > max(pos, raw.byteRange.lowerBound) {
                let start = max(pos, raw.byteRange.lowerBound)
                let text = String(bytes: utf8[start..<end], encoding: .utf8) ?? ""
                if !text.isEmpty {
                    spans.append(StyledSpan(text: text, style: raw.style))
                }
            }

            pos = max(pos, raw.byteRange.upperBound)
        }

        // Trailing unstyled text
        if pos < utf8.count {
            let text = String(bytes: utf8[pos...], encoding: .utf8) ?? ""
            if !text.isEmpty {
                spans.append(StyledSpan(text: text, style: theme.defaultStyle))
            }
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
