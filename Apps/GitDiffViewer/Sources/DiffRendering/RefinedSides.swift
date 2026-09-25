import AtelierSwiftSyntax
package import DiffCore
package import Foundation

/// The colour a tier after the lexer found for one rendered file's two sides (PERF-11): each side's tokens per source
/// line, in UTF-16 offsets from the line's start, as ``PreparedDiff/oldTokens`` holds the lexer's. A side the tier has
/// not refined is nil and keeps the lexer's colour.
package struct RefinedSides: Sendable {
    /// Tells this value apart from every other, so a pane knows at once whether what it shows changed.
    package let id = UUID()
    package let old: LineTokens?
    package let new: LineTokens?

    package init(old: LineTokens?, new: LineTokens?) {
        self.old = old
        self.new = new
    }

    /// The tokens of the source line `row` shows on a pane of `side`, with that line's index; nil for a row that shows
    /// no source line, or one whose side is not refined.
    /// - Complexity: O(1)
    package func tokens(of row: RowMeta, on side: RenderedSide) -> ArraySlice<HighlightToken>? {
        let line: (tokens: LineTokens?, number: Int?) =
            switch side {
                case .old: (old, row.oldNumber)
                case .new: (new, row.newNumber)
                // A unified row shows its new line, or its old one when it has no new line.
                case .unified: row.newNumber != nil ? (new, row.newNumber) : (old, row.oldNumber)
            }
        guard row.kind != .filler, row.kind != .header, let tokens = line.tokens, let number = line.number,
            tokens.indices.contains(number - 1)
        else { return nil }
        return tokens[number - 1]
    }
}

/// The syntactic tier as the render pipeline runs it: one side's text in, its tokens per line out, off the main actor.
/// Injected, so a test can count the parses or hold one.
package struct SyntaxRefiner: Sendable {
    /// Refines `text`, whose lines `lines` cuts as `DiffModel.lines(of:)` does; throws when the tier fails or is
    /// cancelled.
    package typealias Refine = @Sendable (_ text: String, _ lines: [Substring]) async throws -> LineTokens

    private let body: Refine

    package init(_ refine: @escaping Refine) {
        body = refine
    }

    @concurrent
    package func refine(_ text: String, lines: [Substring]) async throws -> LineTokens {
        try await body(text, lines)
    }

    /// swift-syntax's colour (``SwiftSyntaxHighlights``), parsed and classified on its deep stack.
    package static let live = SyntaxRefiner { text, lines in
        let tokens = try await SwiftSyntaxHighlights.tokens(in: text)
        return DiffRenderer.tokensByLine(tokens, text: text, lines: lines)
    }
}
