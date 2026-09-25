package import AppKit
import DiffCore
package import DiffRendering
import Foundation

/// A pane's refined colours (PERF-11 step 1): the tokens a tier after the lexer found for the sides the pane shows,
/// drawn over the colours the text was rendered with as TextKit 2 rendering attributes, which change no layout.
///
/// The text keeps the lexer's colours in its storage, so the first paint is the one the pane always made. Once the
/// refined tokens land, ``validate(_:in:)`` colours each row laid out in the viewport from the tokens of the source line
/// the row shows, where they differ from the storage's, and the fragments' views are redrawn. TextKit drops rendering
/// attributes when it lays a fragment out again, and calls the validator for it, so they are rebuilt from here every
/// time and never lost. Each pane, the scrolling one and a card's, installs one on its own layout manager.
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
        let range = fragment.rangeInElement
        // Every location is found from the fragment's start: an offset from the document's start walks the document.
        let startOffset = contentManager.offset(from: layoutManager.documentRange.location, to: range.location)
        let anchor = (location: range.location, offset: startOffset)
        let end = anchor.offset + contentManager.offset(from: range.location, to: range.endLocation)
        let storage = (contentManager as? NSTextContentStorage)?.textStorage
        let length = storage?.length ?? end
        var row = rendered.rowIndex(containing: anchor.offset)
        while row < rendered.rows.count, rendered.lineStarts[row] < max(end, anchor.offset + 1) {
            let lineStart = rendered.lineStarts[row]
            let lineEnd = min(row + 1 < rendered.lineStarts.count ? rendered.lineStarts[row + 1] - 1 : length, length)
            if let tokens = sides.tokens(of: rendered.rows[row], on: rendered.side), lineEnd > lineStart {
                paint(tokens, from: lineStart, to: lineEnd, storage: storage, in: layoutManager, anchor: anchor)
            }
            row += 1
        }
    }

    /// Colours one row, `lineStart ..< lineEnd` in the text, with its source line's tokens: the plain text colour where
    /// no token lies, since a byte the tier left without one is plain on purpose, each token's colour elsewhere. Only
    /// the stretches whose colour differs from the storage's get a rendering attribute: each costs TextKit some 10 µs,
    /// and most of a row agrees with the lexer. A bidi control's placeholder keeps the colour the renderer gave it.
    /// - Complexity: O(the row's length + its tokens), plus one rendering attribute per stretch that changes colour.
    private func paint(
        _ tokens: [HighlightToken], from lineStart: Int, to lineEnd: Int, storage: NSTextStorage?,
        in layoutManager: NSTextLayoutManager, anchor: (location: any NSTextLocation, offset: Int)
    ) {
        guard let rendered, let storage, let contentManager = layoutManager.textContentManager else { return }
        let length = lineEnd - lineStart
        var colors = [rendered.palette.textColor]
        func index(of color: NSColor) -> UInt8 {
            if let known = colors.firstIndex(where: { $0 === color || $0 == color }) { return UInt8(known) }
            guard colors.count < Int(Self.keep) else { return 0 }
            colors.append(color)
            return UInt8(colors.count - 1)
        }
        // Each unit's colour, as an index into `colors`: the refined one, and the one the storage draws.
        var wanted = [UInt8](repeating: 0, count: length)
        for token in tokens {
            let lower = max(token.byteRange.lowerBound, 0)
            let upper = min(token.byteRange.upperBound, length)
            guard upper > lower else { continue }
            let color = index(of: rendered.palette.color(for: token.role))
            for unit in lower ..< upper { wanted[unit] = color }
        }
        var shown = [UInt8](repeating: 0, count: length)
        storage.enumerateAttributes(
            in: NSRange(location: lineStart, length: length), options: .longestEffectiveRangeNotRequired
        ) { attributes, run, _ in
            let color =
                attributes[.diffBidiControl] != nil
                ? Self.keep : index(of: attributes[.foregroundColor] as? NSColor ?? rendered.palette.textColor)
            for unit in (run.location - lineStart) ..< (run.upperBound - lineStart) { shown[unit] = color }
        }
        var unit = 0
        while unit < length {
            guard shown[unit] != Self.keep, wanted[unit] != shown[unit] else {
                unit += 1
                continue
            }
            var end = unit + 1
            while end < length, shown[end] != Self.keep, wanted[end] == wanted[unit], wanted[end] != shown[end] {
                end += 1
            }
            if let from = contentManager.location(anchor.location, offsetBy: lineStart + unit - anchor.offset),
                let to = contentManager.location(from, offsetBy: end - unit),
                let range = NSTextRange(location: from, end: to)
            {
                layoutManager.setRenderingAttributes([.foregroundColor: colors[Int(wanted[unit])]], for: range)
            }
            unit = end
        }
    }

    /// The colour index of a unit whose colour is left as the storage has it.
    private static let keep: UInt8 = .max
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
