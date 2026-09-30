package import AppKit
import DiffRendering
import Foundation

/// Where a TextKit 2 pane's rows lie, read from its layout fragments (text-renderer.md §4.2): from the fragment at the
/// top of the rect asked for, down past its bottom, as the gutter walks them.
@MainActor
package struct TextKit2RowGeometry: DiffRowGeometry {
    let textView: NSTextView
    let coordinator: DiffTextViewCoordinator

    /// Read live from the coordinator, so one geometry made when the pane is built (``DiffGutterView/source``) never
    /// goes stale as the pane shows a new text.
    var rendered: RenderedText? { coordinator.rendered }

    package var documentHeight: CGFloat { coordinator.contentHeight() }

    package func forEachRow(in rect: CGRect, _ body: (_ row: Int, _ frame: CGRect, _ firstBaseline: CGFloat) -> Void) {
        guard let rendered, !rendered.rows.isEmpty, let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        let origin = textView.textContainerOrigin
        let top = CGPoint(x: 0, y: max(rect.minY - origin.y, 0))
        let viewport = layoutManager.textViewportLayoutController
        // A top not laid out yet starts at the laid-out viewport when it lies below the viewport's top, and at the
        // document's start otherwise, as the gutter does.
        let start =
            layoutManager.textLayoutFragment(for: top)?.rangeInElement.location
            ?? viewport.viewportRange.flatMap { top.y >= viewport.viewportBounds.minY ? $0.location : nil }
            ?? layoutManager.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
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

    package func visibleRows() -> Range<Int> {
        coordinator.visibleRows()
    }

    /// `row`'s fragment, found directly by its character location rather than by walking from the document's start.
    package func frame(ofRow row: Int) -> (frame: CGRect, firstBaseline: CGFloat)? {
        guard let rendered, rendered.lineStarts.indices.contains(row), let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager,
            let location = contentManager.location(
                layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row])
        else { return nil }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        let origin = textView.textContainerOrigin
        let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
        let firstBaseline =
            fragment.textLineFragments.first.map { $0.typographicBounds.minY + $0.glyphOrigin.y }
            ?? frame.height * 0.75
        return (frame, frame.minY + firstBaseline)
    }
}
