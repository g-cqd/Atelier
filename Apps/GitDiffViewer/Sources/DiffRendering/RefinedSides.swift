package import AtelierHighlighting
import AtelierSwiftSyntax
package import DiffCore
package import Foundation

/// The colour the tiers after the lexer found for one rendered file's two sides (PERF-11): each side's layers per
/// source line, in UTF-16 offsets from the line's start, merged a line at a time under the coverage rule. A side, or a
/// line, no tier has reached is nil and keeps the lexer's colour, which the text holds.
package struct RefinedSides: Sendable {
    /// Tells this value apart from every other, so a pane knows at once whether what it shows changed.
    package let id = UUID()
    package let old: LayeredLineTokens?
    package let new: LayeredLineTokens?

    package init(old: LayeredLineTokens?, new: LayeredLineTokens?) {
        self.old = old
        self.new = new
    }

    /// The tokens of the source line `row` shows on a pane of `side`; nil for a row that shows no source line, or one
    /// no tier has reached.
    /// - Complexity: O(the line's tokens and covered length), the per-line merge.
    package func tokens(of row: RowMeta, on side: RenderedSide) -> [LineToken]? {
        let line: (tokens: LayeredLineTokens?, number: Int?) =
            switch side {
                case .old: (old, row.oldNumber)
                case .new: (new, row.newNumber)
                // A unified row shows its new line, or its old one when it has no new line.
                case .unified: row.newNumber != nil ? (new, row.newNumber) : (old, row.oldNumber)
            }
        guard row.kind != .filler, row.kind != .header, let tokens = line.tokens, let number = line.number else {
            return nil
        }
        return tokens.merged(line: number - 1)
    }
}

extension RefinedSides {
    /// The tiers GitDiffViewer runs after the lexer's first paint: swift-syntax on Swift sides (D33), reading and
    /// filling `store` when given one, so a side the intraline diff or hover parsed is not parsed again (step 3).
    package static func tiers(store: SyntaxFactsStore? = nil) -> [any AtelierHighlighting.HighlightTier] {
        [SwiftSyntaxTier(store: store)]
    }
}
