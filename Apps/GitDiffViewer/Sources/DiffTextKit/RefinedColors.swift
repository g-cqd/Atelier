package import AppKit
import DiffCore
package import DiffRendering
import Foundation

/// A pane's refined colours (PERF-11 step 1): the tokens a tier after the lexer found for the sides the pane shows,
/// drawn over the colours the text was rendered with as TextKit 2 rendering attributes, which change no layout.
///
/// The text keeps the lexer's colours in its storage, so the first paint is the one the pane always made. Once the
/// refined tokens land, the pane's layout manager is asked to validate the rendering attributes of what it shows, and
/// its ``validate(_:in:)`` colours each row it is handed from the tokens of the source line the row shows: the plain
/// text colour first, since a byte the tier left without a token is plain on purpose, then each token's colour. TextKit
/// drops rendering attributes when it lays a fragment out again, and asks for them again, so they are rebuilt from here
/// every time and never lost. Each pane, the scrolling one and a card's, installs one on its own layout manager.
@MainActor
package final class RefinedColors {
    /// The text the pane shows, whose rows map to source lines.
    package private(set) var rendered: RenderedText?
    /// What the pane colours ``rendered``'s rows with; nil leaves the storage's colours.
    package private(set) var sides: RefinedSides?
    private weak var layoutManager: NSTextLayoutManager?

    package init() {}

    /// Makes this the validator of `layoutManager`'s rendering attributes.
    package func install(on layoutManager: NSTextLayoutManager) {
        self.layoutManager = layoutManager
        layoutManager.renderingAttributesValidator = { [weak self] layoutManager, fragment in
            MainActor.assumeIsolated { self?.validate(fragment, in: layoutManager) }
        }
    }

    /// Shows `sides` over `rendered`: a no-op unless either changed. Clears the colours the pane drew before, colours
    /// the fragments laid out in the viewport again, and redraws them; nothing is laid out again.
    /// - Parameters:
    ///   - rendered: The text the pane shows.
    ///   - sides: What to colour its rows with; nil gives back the lexer's colours.
    ///   - view: The text view that shows the pane, whose fragment views are redrawn.
    package func update(rendered: RenderedText?, sides: RefinedSides?, view: NSView?) {
        guard rendered !== self.rendered || sides?.id != self.sides?.id else { return }
        let hadColors = self.rendered != nil && self.sides != nil
        self.rendered = rendered
        self.sides = sides
        guard let layoutManager, hadColors || sides != nil else { return }
        let range = layoutManager.documentRange
        if hadColors { layoutManager.removeRenderingAttribute(.foregroundColor, for: range) }
        layoutManager.invalidateRenderingAttributes(for: range)
        if let viewport = layoutManager.textViewportLayoutController.viewportRange {
            layoutManager.enumerateTextLayoutFragments(from: viewport.location) { fragment in
                guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
                    return false
                }
                validate(fragment, in: layoutManager)
                return true
            }
        }
        // TextKit draws each fragment in a view of its own, below the text view, and keeps what it drew.
        var views = view.map { [$0] } ?? []
        while let next = views.popLast() {
            next.needsDisplay = true
            views.append(contentsOf: next.subviews)
        }
    }

    /// Fills the rendering attributes of `fragment`'s rows from ``sides``; does nothing while there are none, or for a
    /// row whose side is not refined.
    /// - Complexity: O(rows in the fragment + their tokens)
    package func validate(_ fragment: NSTextLayoutFragment, in layoutManager: NSTextLayoutManager) {
        guard let rendered, let sides, !rendered.rows.isEmpty,
            let contentManager = layoutManager.textContentManager
        else { return }
        let documentStart = layoutManager.documentRange.location
        let range = fragment.rangeInElement
        let start = contentManager.offset(from: documentStart, to: range.location)
        let end = contentManager.offset(from: documentStart, to: range.endLocation)
        let storage = (contentManager as? NSTextContentStorage)?.textStorage
        let length = storage?.length ?? end
        var row = rendered.rowIndex(containing: start)
        while row < rendered.rows.count, rendered.lineStarts[row] < max(end, start + 1) {
            let lineStart = rendered.lineStarts[row]
            let lineEnd = min(row + 1 < rendered.lineStarts.count ? rendered.lineStarts[row + 1] - 1 : length, length)
            if let tokens = sides.tokens(of: rendered.rows[row], on: rendered.side), lineEnd > lineStart {
                paint(tokens, from: lineStart, to: lineEnd, storage: storage, in: layoutManager, start: documentStart)
            }
            row += 1
        }
    }

    /// Colours one row, `lineStart ..< lineEnd` in the text, with its source line's tokens.
    private func paint(
        _ tokens: ArraySlice<HighlightToken>, from lineStart: Int, to lineEnd: Int, storage: NSTextStorage?,
        in layoutManager: NSTextLayoutManager, start documentStart: any NSTextLocation
    ) {
        guard let rendered, let contentManager = layoutManager.textContentManager else { return }
        let palette = rendered.palette
        func textRange(_ lower: Int, _ upper: Int) -> NSTextRange? {
            guard let from = contentManager.location(documentStart, offsetBy: lower),
                let to = contentManager.location(from, offsetBy: upper - lower)
            else { return nil }
            return NSTextRange(location: from, end: to)
        }
        guard let line = textRange(lineStart, lineEnd) else { return }
        layoutManager.setRenderingAttributes([.foregroundColor: palette.textColor], for: line)
        for token in tokens {
            let lower = lineStart + token.byteRange.lowerBound
            let upper = min(lineStart + token.byteRange.upperBound, lineEnd)
            guard upper > lower, let range = textRange(lower, upper) else { continue }
            layoutManager.addRenderingAttribute(.foregroundColor, value: palette.color(for: token.role), for: range)
        }
        // A bidi control's placeholder keeps the colour the renderer gave it.
        guard let storage else { return }
        storage.enumerateAttribute(
            .diffBidiControl, in: NSRange(location: lineStart, length: lineEnd - lineStart),
            options: .longestEffectiveRangeNotRequired
        ) { value, run, _ in
            guard value != nil, let range = textRange(run.location, run.upperBound) else { return }
            layoutManager.removeRenderingAttribute(.foregroundColor, for: range)
        }
    }
}

extension DiffTextView {
    /// This pane with `sides` drawn over its lexer colours once they land; nil keeps the lexer's.
    package func refined(with sides: RefinedSides?) -> DiffTextView {
        var pane = self
        pane.refinedSides = sides
        return pane
    }
}

extension EmbeddedDiffTextView {
    /// This card pane with `sides` drawn over its lexer colours once they land; nil keeps the lexer's.
    package func refined(with sides: RefinedSides?) -> EmbeddedDiffTextView {
        var pane = self
        pane.refinedSides = sides
        return pane
    }
}
