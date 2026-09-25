import AppKit
import AtelierHighlighting
import DiffCore
import Foundation

@testable import DiffRendering

/// Decorations built as the pipeline builds them, for tests that read what a pane draws (PERF-09).
enum DecorationFixtures {
    /// `tokens`, found over the whole of `text` in UTF-8 byte offsets, cut into `lines` in UTF-16 offsets from each
    /// line's start: what a tier's update over those lines carries.
    static func byLine(_ tokens: [HighlightToken], text: String, lines: [Substring]) -> LineTokens {
        let request = TierRequest(
            revision: revision(text, language: .swift), text: text,
            lineRanges: DiffRenderer.lineRanges(of: text, lines: lines), visibleLines: 0 ..< lines.count,
            unit: .utf16)
        return request.lineTokens(tokens, lines: 0 ..< lines.count)
    }

    /// The layers a tier gives a side whose every line takes `tokens`, cut as ``byLine(_:text:lines:)`` cuts them.
    static func layers(
        _ tokens: [HighlightToken], text: String, layer: HighlightLayer = .syntactic,
        over base: LayeredLineTokens? = nil
    ) -> LayeredLineTokens {
        let lines = DiffModel.lines(of: text)
        var layered = base ?? LayeredLineTokens(lineCount: lines.count)
        layered.apply(
            TierUpdate(
                layer: layer, coverage: .complete, revision: revision(text, language: .swift),
                lines: 0 ..< lines.count, tokens: byLine(tokens, text: text, lines: lines)))
        return layered
    }

    /// The lexer tier's layers for `text`, run as the pipeline runs it: tier 0 of the tier job, visible lines first,
    /// in UTF-16 offsets. Empty for a language the lexer does not know.
    static func lexed(_ text: String, language: Language) async -> LayeredLineTokens {
        let lines = DiffModel.lines(of: text)
        var layered = LayeredLineTokens(lineCount: lines.count)
        let tier = LexicalTier()
        guard tier.supports(language) else { return layered }
        let request = TierRequest(
            revision: revision(text, language: language), text: text,
            lineRanges: DiffRenderer.lineRanges(of: text, lines: lines), visibleLines: 0 ..< min(lines.count, 20),
            unit: .utf16)
        try? await tier.run(request) { layered.apply($0) }
        return layered
    }

    /// Decorations that colour both sides with `old` and `new`.
    static func colors(old: LayeredLineTokens?, new: LayeredLineTokens?, version: Int = 1) -> DiffDecorations {
        DiffDecorations(old: .init(colors: old), new: .init(colors: new), colorVersion: version)
    }

    /// `rendered`'s text with the colours `decorations` give its rows, as a pane draws them: each token in its role's
    /// colour, the plain text colour between, and a bidi control's placeholder keeping its own.
    static func painted(_ rendered: RenderedText, with decorations: DiffDecorations) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: rendered.attributed)
        for (row, meta) in rendered.rows.enumerated() {
            guard let tokens = decorations.tokens(of: meta, on: rendered.side) else { continue }
            let start = rendered.lineStarts[row]
            let end = row + 1 < rendered.lineStarts.count ? rendered.lineStarts[row + 1] - 1 : result.length
            for token in tokens {
                let upper = min(start + token.range.upperBound, end)
                guard upper > start + token.range.lowerBound else { continue }
                result.addAttribute(
                    .foregroundColor, value: rendered.palette.color(for: token.role),
                    range: NSRange(
                        location: start + token.range.lowerBound, length: upper - start - token.range.lowerBound))
            }
        }
        let whole = NSRange(location: 0, length: rendered.attributed.length)
        rendered.attributed.enumerateAttribute(.diffBidiControl, in: whole) { value, range, _ in
            guard value != nil else { return }
            let color = rendered.attributed.attribute(.foregroundColor, at: range.location, effectiveRange: nil)
            if let color { result.addAttribute(.foregroundColor, value: color, range: range) }
        }
        return result
    }

    /// `diff`'s panes painted with the lexer tier's colour of each side, as the pipeline decorates them.
    static func lexedPanes(_ diff: RenderedDiff, old: String, new: String, language: Language) async
        -> [RenderedSide: NSAttributedString]
    {
        let decorations = colors(
            old: await lexed(old, language: language), new: await lexed(new, language: language))
        var panes: [RenderedSide: NSAttributedString] = [:]
        for text in [diff.unified, diff.old, diff.new].compactMap(\.self) {
            panes[text.side] = painted(text, with: decorations)
        }
        return panes
    }

    private static func revision(_ text: String, language: Language) -> SourceRevision {
        SourceRevision(documentID: "fixture", language: language, key: .content(String(text.hashValue)))
    }
}
