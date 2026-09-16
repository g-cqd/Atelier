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
