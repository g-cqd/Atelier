import KittyCodecs
import KittyGrammar
import KittyParser
import KittyQuery

final class HighlightScratch {
    struct RawCaptureSpan {
        var byteRange: Range<Int>
        var style: Style
        var patternIndex: Int
    }

    var rawSpans: [RawCaptureSpan] = []
    var byteStyles: [Style?] = []
    var spans: [StyledSpan] = []
}

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
        let scratch = HighlightScratch()
        return highlight(source: source, tree: tree, query: query, scratch: scratch)
    }

    func highlight(
        source: String,
        tree: SyntaxTree,
        query: Query,
        scratch: HighlightScratch
    ) -> [StyledSpan] {
        let matches = QueryMatcher.execute(query: query, tree: tree)
        return buildSpans(source: source, matches: matches, scratch: scratch)
    }

    private func buildSpans(source: String, matches: [QueryMatch], scratch: HighlightScratch) -> [StyledSpan] {
        if let spans = source.utf8.withContiguousStorageIfAvailable({ utf8 in
            buildSpans(source: source, utf8: utf8, matches: matches, scratch: scratch)
        }) {
            return spans
        }

        let utf8 = Array(source.utf8)
        return utf8.withUnsafeBufferPointer { utf8 in
            buildSpans(source: source, utf8: utf8, matches: matches, scratch: scratch)
        }
    }

    private func buildSpans(
        source: String,
        utf8: UnsafeBufferPointer<UInt8>,
        matches: [QueryMatch],
        scratch: HighlightScratch
    ) -> [StyledSpan] {
        guard !utf8.isEmpty else {
            return [StyledSpan(text: source, style: theme.defaultStyle)]
        }

        scratch.rawSpans.removeAll(keepingCapacity: true)
        scratch.rawSpans.reserveCapacity(matches.reduce(into: 0) { $0 += $1.captures.count })

        for match in matches {
            for capture in match.captures {
                let style = theme.style(for: capture.name)
                scratch.rawSpans.append(
                    .init(
                        byteRange: capture.node.byteRange,
                        style: style,
                        patternIndex: match.patternIndex
                    )
                )
            }
        }
        guard !scratch.rawSpans.isEmpty else {
            return [StyledSpan(text: source, style: theme.defaultStyle)]
        }

        // Sort: broader ranges first, then later patterns first.
        // Since styles are written in order and later writes win, this keeps
        // smaller captures more specific than broader ones while still honoring
        // query-file precedence for identical ranges.
        scratch.rawSpans.sort { a, b in
            let aSize = a.byteRange.count
            let bSize = b.byteRange.count
            if aSize != bSize { return aSize > bSize }
            if a.patternIndex != b.patternIndex { return a.patternIndex > b.patternIndex }
            if a.byteRange.lowerBound != b.byteRange.lowerBound { return a.byteRange.lowerBound < b.byteRange.lowerBound }
            return a.byteRange.upperBound < b.byteRange.upperBound
        }

        // Build per-byte style map
        scratch.byteStyles.removeAll(keepingCapacity: true)
        scratch.byteStyles.reserveCapacity(utf8.count)
        scratch.byteStyles.append(contentsOf: repeatElement(nil, count: utf8.count))

        for span in scratch.rawSpans {
            let start = min(max(span.byteRange.lowerBound, 0), utf8.count)
            let end = min(max(span.byteRange.upperBound, start), utf8.count)
            for i in start..<end {
                scratch.byteStyles[i] = span.style
            }
        }

        // Coalesce into spans
        scratch.spans.removeAll(keepingCapacity: true)
        scratch.spans.reserveCapacity(min(scratch.rawSpans.count + 1, utf8.count))
        var pos = 0
        while pos < utf8.count {
            let style = scratch.byteStyles[pos] ?? theme.defaultStyle
            var end = pos + 1
            while end < utf8.count && (scratch.byteStyles[end] ?? theme.defaultStyle) == style {
                end += 1
            }
            let text = String(decoding: UnsafeBufferPointer(rebasing: utf8[pos..<end]), as: UTF8.self)
            if !text.isEmpty {
                scratch.spans.append(StyledSpan(text: text, style: style))
            }
            pos = end
        }
        return scratch.spans
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
