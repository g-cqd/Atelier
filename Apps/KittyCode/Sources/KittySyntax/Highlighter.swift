import Foundation
import KittyGrammar
public import KittyParser
public import KittyQuery
public import KittyStyle

final class HighlightScratch {
    struct RawCaptureSpan {
        var byteRange: Range<Int>
        var styleIndex: UInt8
        var patternIndex: Int
    }

    var rawSpans: [RawCaptureSpan] = []
    /// Palette of unique styles used in current highlight pass (max 255 + 1 sentinel).
    var stylePalette: [Style] = []
    /// Maps Style → palette index for deduplication.
    var styleMap: [Style: UInt8] = [:]
    /// Per-byte style index (0xFF = no style / use default).
    var byteStyleIndices: [UInt8] = []
    var spans: [StyledSpan] = []

    /// Returns the palette index for a style, inserting it if new.
    func paletteIndex(for style: Style) -> UInt8 {
        if let existing = styleMap[style] {
            return existing
        }
        let idx = UInt8(clamping: stylePalette.count)
        stylePalette.append(style)
        styleMap[style] = idx
        return idx
    }

    /// Resets the palette and registers the default style at index 0.
    func resetPalette(defaultStyle: Style) {
        stylePalette.removeAll(keepingCapacity: true)
        styleMap.removeAll(keepingCapacity: true)
        // Default style is always index 0 — ensures unstyled bytes
        // coalesce with explicitly-default-styled bytes.
        stylePalette.append(defaultStyle)
        styleMap[defaultStyle] = 0
    }
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

    private func buildSpans(source: String, matches: [QueryMatch], scratch: HighlightScratch)
        -> [StyledSpan]
    {
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

        let defaultStyle = theme.defaultStyle
        scratch.resetPalette(defaultStyle: defaultStyle)
        scratch.rawSpans.removeAll(keepingCapacity: true)
        scratch.rawSpans.reserveCapacity(matches.reduce(into: 0) { $0 += $1.captures.count })

        for match in matches {
            for capture in match.captures {
                let style = theme.style(for: capture.name)
                let idx = scratch.paletteIndex(for: style)
                scratch.rawSpans.append(
                    .init(
                        byteRange: capture.node.byteRange,
                        styleIndex: idx,
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
            if a.byteRange.lowerBound != b.byteRange.lowerBound {
                return a.byteRange.lowerBound < b.byteRange.lowerBound
            }
            return a.byteRange.upperBound < b.byteRange.upperBound
        }

        // Build per-byte style index map (1 byte per source byte instead of ~32)
        // Index 0 = defaultStyle, registered in resetPalette().
        let defaultIdx: UInt8 = 0
        scratch.byteStyleIndices.removeAll(keepingCapacity: true)
        scratch.byteStyleIndices.reserveCapacity(utf8.count)
        scratch.byteStyleIndices.append(contentsOf: repeatElement(defaultIdx, count: utf8.count))

        for span in scratch.rawSpans {
            let start = min(max(span.byteRange.lowerBound, 0), utf8.count)
            let end = min(max(span.byteRange.upperBound, start), utf8.count)
            let idx = span.styleIndex
            for i in start ..< end {
                scratch.byteStyleIndices[i] = idx
            }
        }

        // Coalesce into spans — index comparison works because defaultStyle
        // is always palette index 0, so unstyled and explicitly-default bytes match.
        let palette = scratch.stylePalette
        scratch.spans.removeAll(keepingCapacity: true)
        scratch.spans.reserveCapacity(min(scratch.rawSpans.count + 1, utf8.count))
        var pos = 0
        while pos < utf8.count {
            let styleIdx = scratch.byteStyleIndices[pos]
            var end = pos + 1
            while end < utf8.count && scratch.byteStyleIndices[end] == styleIdx {
                end += 1
            }
            let textBuf = UnsafeBufferPointer(rebasing: utf8[pos ..< end])
            let text = String(bytes: textBuf, encoding: .utf8) ?? String(decoding: textBuf, as: UTF8.self)
            if !text.isEmpty {
                scratch.spans.append(StyledSpan(text: text, style: palette[Int(styleIdx)]))
            }
            pos = end
        }
        return scratch.spans
    }

    // MARK: - Token-based highlighting

    /// Build intermediate `HighlightToken`s from query matches.
    /// These tokens preserve semantic roles and can be merged across layers.
    ///
    /// Priority is inverted from patternIndex: earlier patterns in the query file
    /// get *higher* priority, matching the existing span-path convention where
    /// earlier patterns win on identical byte ranges.
    public func buildTokens(
        matches: [QueryMatch],
        layer: HighlightLayer = .structural
    ) -> [HighlightToken] {
        let maxPatternIndex = matches.map(\.patternIndex).max() ?? 0
        var tokens: [HighlightToken] = []
        tokens.reserveCapacity(matches.reduce(into: 0) { $0 += $1.captures.count })

        for match in matches {
            for capture in match.captures {
                let (role, modifiers) = CaptureRoleMapper.map(capture.name)
                tokens.append(
                    HighlightToken(
                        byteRange: capture.node.byteRange,
                        role: role,
                        modifiers: modifiers,
                        layer: layer,
                        priority: maxPatternIndex - match.patternIndex
                    ))
            }
        }

        return tokens
    }

    /// Convert merged tokens to styled spans using a role-based theme resolver.
    public func tokensToSpans(
        tokens: [HighlightToken],
        source: String,
        resolver: RoleBasedThemeResolver
    ) -> [StyledSpan] {
        HighlightMerger.resolveToSpans(
            tokens: tokens,
            source: source,
            resolver: resolver,
            defaultStyle: theme.defaultStyle
        )
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
