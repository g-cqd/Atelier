package import AppKit
package import DiffRendering
import Foundation

/// Where a file pane is scrolled: the row the model asks it to show, the position a file tab comes back to (book
/// TAB-10), and the scrolls that keep within the text view. Placements wait for the end of the text view's layout
/// pass, when the pane has its size and TextKit has laid out what it shows.
extension DiffTextViewCoordinator {
    /// Shows `rendered`, the file remembered under `key`. Another file than the one on show first records where the
    /// pane was for that one, then comes back where it was itself, or starts at its top when it has no position; the
    /// same file keeps its position when `keepingScroll`, and starts at its top otherwise, as ``apply(_:keepingScroll:)``
    /// does.
    package func show(_ rendered: RenderedText, keepingScroll: Bool, key: PaneScrollMemory.Key?) {
        let isAnotherFile = key != memoryKey
        if isAnotherFile { rememberPosition() }
        memoryKey = key
        pendingPosition = nil
        apply(rendered, keepingScroll: keepingScroll && !isAnotherFile)
        if isAnotherFile, let key, let position = scrollMemory?.position(for: key) { restore(position) }
    }

    /// Records where the pane is scrolled for the file on show.
    package func rememberPosition() {
        guard let memoryKey, let scrollMemory, let position = currentPosition() else { return }
        scrollMemory.record(position, for: memoryKey)
    }

    /// The row at the top of the pane and how far into it the pane is scrolled; nil with nothing laid out.
    private func currentPosition() -> PaneScrollPosition? {
        guard let textView, let rendered, !rendered.rows.isEmpty, let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager,
            let clipView = textView.enclosingScrollView?.contentView
        else { return nil }
        let top = clipView.bounds.minY
        let inset = textView.textContainerInset.height
        let row =
            layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: max(top - inset, 0)))
            .map {
                rendered.rowIndex(
                    containing: contentManager.offset(
                        from: layoutManager.documentRange.location, to: $0.rangeInElement.location))
            } ?? rendered.rows.count - 1
        guard let rowTop = self.top(ofRow: row) else { return nil }
        return PaneScrollPosition(row: row, offset: Double(top - rowTop), x: Double(clipView.bounds.minX))
    }

    /// Scrolls to `position` now, or once the pane has a size when it has none yet, as a pane just made.
    func restore(_ position: PaneScrollPosition) {
        guard let rendered, !rendered.rows.isEmpty, let clipView = textView?.enclosingScrollView?.contentView else {
            return
        }
        guard clipView.bounds.height > 0 else {
            pendingPosition = position
            return
        }
        pendingPosition = nil
        let row = min(position.row, rendered.rows.count - 1)
        // Laying the viewport out where the row lands can move it: the rows above it were only estimated. A second
        // pass puts it back where it belongs, now that they are laid out.
        for _ in 0 ..< 2 {
            guard let rowTop = top(ofRow: row) else { return }
            let target = NSPoint(x: max(0, position.x), y: max(0, rowTop + position.offset))
            guard clipView.bounds.origin != target else { return }
            // Laying out down to the row may have grown the text; give it the room to scroll there.
            updateOverscroll(in: clipView)
            scroll(clipView, to: target)
            textView?.textLayoutManager?.textViewportLayoutController.layoutViewport()
        }
    }

    /// Brings `row` into view at the end of the text view's next layout pass: its top three lines below the pane's top,
    /// or its middle at the pane's middle when `centered`, as near as the pane scrolls. A text that fits the pane stays
    /// at its top, whole (book DIFF-08).
    ///
    /// The pass comes once the pane has its size, which a pane made in the same update has not, and once TextKit has
    /// laid out the text it shows, which a text applied in the same update has not: a row placed any earlier sat where
    /// the layout, the size or the text of the moment put it, and the pane showed it elsewhere.
    package func scroll(toRow row: Int, in scrollView: NSScrollView, centered: Bool = false) {
        pendingPosition = nil
        pendingScroll = RowPlacement(row: row, centered: centered)
        textView?.needsLayout = true
    }

    /// Places the row placed last again once the split view has aligned its rows, which moves them, unless the pane
    /// has been scrolled since.
    package func rowsDidAlign() {
        guard pendingScroll == nil, let placedRow, let clipView = textView?.enclosingScrollView?.contentView,
            abs(clipView.bounds.minY - placedRow.y) < 0.5
        else { return }
        pendingScroll = RowPlacement(row: placedRow.placement.row, centered: placedRow.placement.centered)
        textView?.needsLayout = true
    }

    /// Sizes the pane to what TextKit laid out in the pass that ended, then places a row asked for.
    func layoutDidEnd() {
        if let clipView = textView?.enclosingScrollView?.contentView { updateOverscroll(in: clipView) }
        placePendingScroll()
    }

    /// Places the row of ``scroll(toRow:in:centered:)``, if any, once the pane has a size, and checks it again at the
    /// end of the next layout pass, until it stays in place.
    ///
    /// TextKit places a row after its estimates of the rows above it that it has not laid out, and moves it as it lays
    /// them out: the text is laid out down to the row first. Rows can still move once placed: side by side, the other
    /// pane's placement scrolls this one along, and TextKit lays out what then shows from its estimates.
    private func placePendingScroll() {
        guard var placement = pendingScroll, let textView, let rendered,
            let clipView = textView.enclosingScrollView?.contentView, clipView.bounds.height > 0
        else { return }
        guard let top = top(ofRow: placement.row) else {
            pendingScroll = nil
            return
        }
        updateOverscroll(in: clipView)
        let margin = placement.centered ? (clipView.bounds.height - rendered.lineHeight) / 2 : 3 * rendered.lineHeight
        // A text that fits the pane shows whole, from its top.
        let target = contentHeight() > clipView.bounds.height ? clamped(top - margin, in: clipView) : 0
        let isInPlace = placement.top.map { abs($0 - top) < 0.5 } == true && abs(clipView.bounds.minY - target) < 0.5
        guard !isInPlace, placement.passes < RowPlacement.passes else {
            pendingScroll = nil
            placedRow = (placement, clipView.bounds.minY)
            return
        }
        scroll(clipView, toY: target)
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        placement.top = top
        placement.passes += 1
        pendingScroll = placement
        textView.needsLayout = true
    }

    /// The top of `row`'s line in the text view, laying the text out from its start down to the row.
    private func top(ofRow row: Int) -> CGFloat? {
        guard let textView, let rendered, rendered.lineStarts.indices.contains(row),
            let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager,
            let location = contentManager.location(
                layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row]),
            let range = NSTextRange(location: layoutManager.documentRange.location, end: location)
        else { return nil }
        layoutManager.ensureLayout(for: range)
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        return fragment.layoutFragmentFrame.minY + textView.textContainerInset.height
    }

    /// Scrolls `clipView` down to `y`, kept within the text view: never above its top, never past its end, where no
    /// text is drawn.
    private func scroll(_ clipView: NSClipView, toY y: CGFloat) {
        scroll(clipView, to: NSPoint(x: clipView.bounds.minX, y: y))
    }

    /// Scrolls `clipView` to `point`, its height kept within the text view.
    func scroll(_ clipView: NSClipView, to point: NSPoint) {
        clipView.scroll(to: NSPoint(x: point.x, y: clamped(point.y, in: clipView)))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    /// `y` kept between the text view's top and the furthest `clipView` scrolls in it.
    private func clamped(_ y: CGFloat, in clipView: NSClipView) -> CGFloat {
        min(max(y, 0), max((textView?.frame.height ?? 0) - clipView.bounds.height, 0))
    }
}

/// A row a file pane was asked to show, and how its placement went so far.
struct RowPlacement {
    /// The most placements one request makes: its own, then those that follow rows moved by layout.
    static let passes = 4

    let row: Int
    let centered: Bool
    /// Where the row lay when last placed, in the text view.
    var top: CGFloat?
    var passes = 0
}
