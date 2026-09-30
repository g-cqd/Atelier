package import AppKit
import DiffCore
package import DiffRendering
import Foundation
import Synchronization

/// What a pane's fragments read as they draw: the text the pane shows and its decorations, handed over under a lock,
/// since TextKit may draw a fragment on a thread of its own.
package final class DecorationSnapshot: Sendable {
    private struct State {
        var rendered: RenderedText?
        var decorations: DiffDecorations?
    }

    private let state = Mutex(State())

    package init() {}

    func set(rendered: RenderedText?, decorations: DiffDecorations?) {
        state.withLock { $0 = State(rendered: rendered, decorations: decorations) }
    }

    /// The decorations of `rendered`; nil while the pane shows another text, or none has landed.
    package func decorations(for rendered: RenderedText) -> DiffDecorations? {
        state.withLock { $0.rendered === rendered ? $0.decorations : nil }
    }
}

/// A pane's decorations (PERF-09 stages 1 and 2, PERF-11): what the stages after the text found for the sides the pane
/// shows, drawn over its plain text without laying anything out again.
///
/// - Colour goes through TextKit 2's rendering attributes: ``validate(_:in:)`` colours each row laid out in the viewport
///   from the tokens of the source line the row shows, where they differ from the storage's plain colour. TextKit drops
///   rendering attributes when it lays a fragment out again, and calls the validator for it, so they are rebuilt from
///   here every time and never lost.
/// - Emphasis and the moved rows' background are read by each row's fragment as it draws, from ``snapshot``: when they
///   land, the fragments are only redrawn.
///
/// Each pane, the scrolling one and a card's, keeps one and installs it on its own layout manager.
@MainActor
package final class DecorationStore {
    /// What the pane's fragments draw the decorations from.
    package let snapshot = DecorationSnapshot()
    /// The text the pane shows, whose rows map to source lines.
    package private(set) var rendered: RenderedText?
    /// What the pane decorates ``rendered``'s rows with; nil leaves them plain.
    package private(set) var decorations: DiffDecorations?
    weak var layoutManager: NSTextLayoutManager?
    /// The gutter beside the pane, which draws the scope ribbon from ``snapshot`` and is redrawn when scopes land.
    package weak var gutter: NSView?
    /// The braces of the scope under the pointer, in UTF-16 offsets of the text, lit in the accent colour (DIFF-03).
    var litBraces: [Int] = []
    /// Whether the layout manager keeps the rows it laid out when they leave the viewport, as a card's does.
    private var retainsLayout = false

    package init() {}

    /// Makes this the validator of `layoutManager`'s rendering attributes.
    /// - Parameters:
    ///   - layoutManager: The pane's layout manager.
    ///   - retainsLayout: Whether it keeps the rows it laid out when they leave the viewport, as a card's does
    ///     (`DiffPaneTextView`): TextKit asks the validator for a row only when it lays the row out, so when colours
    ///     land, every row laid out is coloured, not only the viewport's.
    package func install(on layoutManager: NSTextLayoutManager, retainsLayout: Bool = false) {
        self.layoutManager = layoutManager
        self.retainsLayout = retainsLayout
        layoutManager.renderingAttributesValidator = { [weak self] layoutManager, fragment in
            MainActor.assumeIsolated { self?.validate(fragment, in: layoutManager) }
        }
    }

    /// Shows `decorations` over `rendered`: a no-op unless the text or a decoration changed. New colours clear those the
    /// pane drew before and colour the fragments laid out in the viewport again, or every fragment laid out when the
    /// layout manager keeps them; new emphasis or moved lines only redraw them. Nothing is laid out again.
    /// - Complexity: O(rows coloured + their tokens)
    /// - Parameters:
    ///   - rendered: The text the pane shows.
    ///   - decorations: What to decorate its rows with; nil leaves them plain.
    ///   - view: The text view that shows the pane, whose fragment views are redrawn.
    package func update(rendered: RenderedText?, decorations: DiffDecorations?, view: NSView?) {
        let isNewText = rendered !== self.rendered
        let colorsChanged = isNewText || decorations?.colorVersion != self.decorations?.colorVersion
        let marksChanged = isNewText || decorations?.markVersion != self.decorations?.markVersion
        guard colorsChanged || marksChanged else { return }
        let hadColors = self.rendered != nil && self.decorations != nil
        // Braces lit in another text point at nothing in this one; recolouring below clears what they drew.
        if isNewText { litBraces = [] }
        self.rendered = rendered
        self.decorations = decorations
        snapshot.set(rendered: rendered, decorations: decorations)
        if colorsChanged { recolor(clearing: hadColors) }
        if marksChanged { gutter?.needsDisplay = true }
        // TextKit draws each fragment in a view of its own, below the text view, and keeps what it drew.
        var views = view.map { [$0] } ?? []
        while let next = views.popLast() {
            next.needsDisplay = true
            views.append(contentsOf: next.subviews)
        }
    }

    /// Colours again the fragments laid out in the viewport, or every one laid out when the layout manager keeps them,
    /// having cleared the colours drawn before when `clearing`.
    private func recolor(clearing: Bool) {
        guard let layoutManager, clearing || decorations != nil else { return }
        let range = layoutManager.documentRange
        if clearing { layoutManager.removeRenderingAttribute(.foregroundColor, for: range) }
        layoutManager.invalidateRenderingAttributes(for: range)
        if retainsLayout {
            _ = layoutManager.enumerateTextLayoutFragments(from: range.location) { fragment in
                if fragment.state == .layoutAvailable { validate(fragment, in: layoutManager) }
                return true
            }
        } else if let viewport = layoutManager.textViewportLayoutController.viewportRange {
            layoutManager.enumerateTextLayoutFragments(from: viewport.location) { fragment in
                guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
                    return false
                }
                validate(fragment, in: layoutManager)
                return true
            }
        }
    }

    /// Fills the rendering attributes of `fragment`'s rows from ``decorations``; does nothing while there are none, or
    /// for a row whose side has no colour yet.
    /// - Complexity: O(rows in the fragment + their tokens)
    package func validate(_ fragment: NSTextLayoutFragment, in layoutManager: NSTextLayoutManager) {
        guard let rendered, let decorations, !rendered.rows.isEmpty,
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
            if let tokens = decorations.tokens(of: rendered.rows[row], on: rendered.side), lineEnd > lineStart {
                paint(tokens, from: lineStart, to: lineEnd, storage: storage, in: layoutManager, anchor: anchor)
            }
            row += 1
        }
        paintLitBraces(in: anchor.offset ..< end, anchor: anchor, layoutManager: layoutManager)
    }

    /// Colours one row, `lineStart ..< lineEnd` in the text, with its source line's tokens: the plain text colour where
    /// no token lies, since a byte the tier left without one is plain on purpose, each token's colour elsewhere. Only
    /// the stretches whose colour differs from the storage's get a rendering attribute: each costs TextKit some 10 µs,
    /// and most of a row agrees with the lexer. A bidi control's placeholder keeps the colour the renderer gave it.
    /// - Complexity: O(the row's length + its tokens), plus one rendering attribute per stretch that changes colour.
    private func paint(
        _ tokens: [LineToken], from lineStart: Int, to lineEnd: Int, storage: NSTextStorage?,
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
            let lower = token.range.lowerBound
            let upper = min(token.range.upperBound, length)
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
    /// This pane with `decorations` drawn over its plain text as they land, and its visible rows reported to
    /// `viewport`; nil leaves it plain.
    package func decorated(with decorations: DiffDecorations?, viewport: DecorationViewport? = nil) -> DiffTextView {
        var pane = self
        pane.decorations = decorations
        pane.viewport = viewport
        return pane
    }
}

extension EmbeddedDiffTextView {
    /// This card pane with `decorations` drawn over its plain text as they land, and its visible rows reported to
    /// `viewport`; nil leaves it plain.
    package func decorated(with decorations: DiffDecorations?, viewport: DecorationViewport? = nil)
        -> EmbeddedDiffTextView
    {
        var pane = self
        pane.decorations = decorations
        pane.viewport = viewport
        return pane
    }
}
