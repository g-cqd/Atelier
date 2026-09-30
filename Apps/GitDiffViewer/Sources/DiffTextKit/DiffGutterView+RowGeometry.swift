package import AppKit
import DiffRendering
import Foundation

/// The `DiffRowGeometry` conformances a gutter beside a card reads, which have no `DiffTextViewCoordinator` to route
/// through as a pane's gutter does (``TextKit2RowGeometry``): cards keep TextKit 2 this hand-back
/// (text-renderer.md §4.2, §4.5 commit 9).

/// A plain `NSTextView`'s own rows, for an embedded gutter beside a card's text view, which has no `RenderedText`
/// mapping of its own: its rows are its layout fragments, in document order, from the container's origin.
extension NSTextView: DiffRowGeometry {
    package var documentHeight: CGFloat { textLayoutManager?.usageBoundsForTextContainer.height ?? 0 }

    package func forEachRow(in rect: CGRect, _ body: (_ row: Int, _ frame: CGRect, _ firstBaseline: CGFloat) -> Void) {
        guard let layoutManager = textLayoutManager else { return }
        let origin = textContainerOrigin
        var index = 0
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            defer { index += 1 }
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            if frame.minY > rect.maxY { return false }
            if frame.maxY < rect.minY { return true }
            let firstBaseline =
                fragment.textLineFragments.first.map { $0.typographicBounds.minY + $0.glyphOrigin.y }
                ?? frame.height * 0.75
            body(index, frame, frame.minY + firstBaseline)
            return true
        }
    }

    /// Always empty: a card shows its whole document, with no clip view of its own to report visible rows for.
    package func visibleRows() -> Range<Int> { 0 ..< 0 }

    package func frame(ofRow row: Int) -> (frame: CGRect, firstBaseline: CGFloat)? {
        var found: (frame: CGRect, firstBaseline: CGFloat)?
        forEachRow(
            in: CGRect(
                x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        ) {
            index, frame, firstBaseline in
            guard index == row, found == nil else { return }
            found = (frame, firstBaseline)
        }
        return found
    }
}

/// A card's detached layout, for an embedded gutter that reads it directly rather than through the text view that
/// shows it (`ChangeMarkerTests`): it has its own `RenderedText`, so its rows map the way a pane's do.
extension StaticTextLayout: DiffRowGeometry {
    package var documentHeight: CGFloat { height }

    package func forEachRow(in rect: CGRect, _ body: (_ row: Int, _ frame: CGRect, _ firstBaseline: CGFloat) -> Void) {
        guard !rendered.rows.isEmpty, let contentManager = layoutManager.textContentManager else { return }
        let top = CGPoint(x: 0, y: max(rect.minY - inset, 0))
        let start =
            layoutManager.textLayoutFragment(for: top)?.rangeInElement.location ?? layoutManager.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: inset)
            if frame.minY > rect.maxY { return false }
            if frame.maxY < rect.minY { return true }
            let offset = contentManager.offset(
                from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
            let firstBaseline =
                fragment.textLineFragments.first.map { $0.typographicBounds.minY + $0.glyphOrigin.y }
                ?? frame.height * 0.75
            body(rendered.rowIndex(containing: offset), frame, frame.minY + firstBaseline)
            return true
        }
    }

    /// A card shows its whole document.
    package func visibleRows() -> Range<Int> { 0 ..< rendered.rows.count }

    package func frame(ofRow row: Int) -> (frame: CGRect, firstBaseline: CGFloat)? {
        guard rendered.lineStarts.indices.contains(row), let contentManager = layoutManager.textContentManager,
            let location = contentManager.location(
                layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row])
        else { return nil }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: inset)
        let firstBaseline =
            fragment.textLineFragments.first.map { $0.typographicBounds.minY + $0.glyphOrigin.y } ?? frame.height * 0.75
        return (frame, frame.minY + firstBaseline)
    }
}
