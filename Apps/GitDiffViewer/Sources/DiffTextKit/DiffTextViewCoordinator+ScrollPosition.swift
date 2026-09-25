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
    ///
    /// A position comes back as a row asked for does, at the end of the text view's next layout pass (see
    /// ``scroll(toRow:in:centered:)``): its row at the pane's top again, less how far into it the pane was scrolled.
    /// It wins over the first change, which the model does not ask for when a file comes back to its place, and it
    /// holds even in a file that fits its pane, which one that scrolls past its end can scroll.
    package func show(_ rendered: RenderedText, keepingScroll: Bool, key: PaneScrollMemory.Key?) {
        let isAnotherFile = key != memoryKey
        if isAnotherFile { rememberPosition() }
        memoryKey = key
        apply(rendered, keepingScroll: keepingScroll && !isAnotherFile)
        guard isAnotherFile, let key, let position = scrollMemory?.position(for: key), !rendered.rows.isEmpty
        else { return }
        let row = min(position.row, rendered.rows.count - 1)
        place(RowPlacement(row: row, anchor: .restored(offset: position.offset, x: position.x)))
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
        // The fragment at the pane's top is laid out, as all that shows is: its frame is read, and nothing above it is
        // laid out, which in a long file would cost as much as opening it at its end.
        guard let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: max(top - inset, 0))) else {
            return nil
        }
        let row = rendered.rowIndex(
            containing: contentManager.offset(
                from: layoutManager.documentRange.location, to: fragment.rangeInElement.location))
        let rowTop = fragment.layoutFragmentFrame.minY + inset
        return PaneScrollPosition(row: row, offset: Double(top - rowTop), x: Double(clipView.bounds.minX))
    }

    /// Brings `row` into view at the end of the text view's next layout pass: its top three lines below the pane's top,
    /// or its middle at the pane's middle when `centered`, as near as the pane scrolls. A text that fits the pane stays
    /// at its top, whole (book DIFF-08).
    ///
    /// The pass comes once the pane has its size, which a pane made in the same update has not, and once TextKit has
    /// laid out the text it shows, which a text applied in the same update has not: a row placed any earlier sat where
    /// the layout, the size or the text of the moment put it, and the pane showed it elsewhere.
    package func scroll(toRow row: Int, in scrollView: NSScrollView, centered: Bool = false) {
        place(RowPlacement(row: row, anchor: centered ? .centered : .nearTop))
    }

    /// Places `placement` at the end of the text view's next layout pass, in place of any placement pending.
    private func place(_ placement: RowPlacement) {
        pendingScroll = placement
        textView?.needsLayout = true
    }

    /// Draws the line numbers again where the split view's alignment moved their rows, and places the row placed last
    /// again, unless the pane has been scrolled since (book DIFF-06). The text redraws the rows it lays out again; the
    /// gutter beside it would keep the numbers where the rows were.
    package func rowsDidAlign() {
        gutterView?.needsDisplay = true
        placeAgainUnlessScrolled()
    }

    /// Places the row placed last again, where it was asked for, unless the pane has been scrolled since: the split
    /// view's alignment of the rows, and a new size of the pane, have TextKit lay the text out anew, from estimates of
    /// the rows above what shows, and the row moves with them.
    func placeAgainUnlessScrolled() {
        guard pendingScroll == nil, let placedRow, let clipView = textView?.enclosingScrollView?.contentView,
            abs(clipView.bounds.minY - placedRow.y) < 0.5
        else { return }
        place(RowPlacement(row: placedRow.placement.row, anchor: placedRow.placement.anchor))
    }

    /// Sizes the pane to what TextKit laid out in the pass that ended, then places a row asked for.
    func layoutDidEnd() {
        if let clipView = textView?.enclosingScrollView?.contentView { updateOverscroll(in: clipView) }
        placePendingScroll()
    }

    /// Places the row of ``scroll(toRow:in:centered:)``, if any, once the pane has a size, and checks it again until it
    /// stays in place.
    ///
    /// TextKit places a row after its estimates of the rows above it that it has not laid out, and moves it as it lays
    /// them out: the text is laid out down to the row first, unless that would take long (see ``top(ofRow:)``). Rows
    /// can still move once placed, as TextKit lays out what shows there, the rows above the row among it, and side by
    /// side as the other pane scrolls this one along: each placement lays the viewport out and reads the row again,
    /// within this pass. A check left for the next pass would not come: a view that asks for layout while it lays out
    /// is not laid out again for it.
    private func placePendingScroll() {
        guard let placement = pendingScroll, let textView, let rendered,
            let clipView = textView.enclosingScrollView?.contentView, clipView.bounds.height > 0
        else { return }
        pendingScroll = nil
        for _ in 0 ..< RowPlacement.passes {
            guard let top = top(ofRow: placement.row) else { return }
            updateOverscroll(in: clipView)
            let target: NSPoint
            switch placement.anchor {
                case .restored(let offset, let x):
                    target = NSPoint(x: max(0, x), y: clamped(top + offset, in: clipView))
                case .nearTop, .centered:
                    let margin =
                        placement.anchor == .centered
                        ? (clipView.bounds.height - rendered.lineHeight) / 2 : 3 * rendered.lineHeight
                    // A text that fits the pane shows whole, from its top.
                    let y = contentHeight() > clipView.bounds.height ? clamped(top - margin, in: clipView) : 0
                    target = NSPoint(x: clipView.bounds.minX, y: y)
            }
            guard abs(clipView.bounds.minY - target.y) >= 0.5 || abs(clipView.bounds.minX - target.x) >= 0.5 else {
                break
            }
            scroll(clipView, to: target)
            textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        }
        placedRow = (placement, clipView.bounds.minY)
    }

    /// The top of `row`'s line in the text view, laid out.
    ///
    /// The text is laid out from its start down to the row when that costs little, or when the pane scrolls in step
    /// with the other side, whose estimates differ from this one's while one scroll offset has to show the row at the
    /// same place in both. Otherwise the row alone is laid out, and TextKit places it after its estimates of the rows
    /// above it: laying out every row above a change near the end of a long file took hundreds of milliseconds, many
    /// times what the rest of opening it takes (`FirstChangePlacementBenchmark`). The text's height follows the same
    /// estimates until the rows above are laid out.
    private func top(ofRow row: Int) -> CGFloat? {
        guard let textView, let rendered, rendered.lineStarts.indices.contains(row),
            let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager,
            let location = contentManager.location(
                layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row])
        else { return nil }
        if rendered.lineStarts[row] <= RowPlacement.textLaidOutAbove || splitController?.syncsScrolling == true,
            let above = NSTextRange(location: layoutManager.documentRange.location, end: location)
        {
            layoutManager.ensureLayout(for: above)
        }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        return fragment.layoutFragmentFrame.minY + textView.textContainerInset.height
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

/// A row a file pane was asked to show, where in the pane, and how its placement went so far.
struct RowPlacement {
    /// Where the row goes in the pane.
    enum Anchor: Equatable {
        /// Its top three lines below the pane's top: a change, or a finding.
        case nearTop
        /// Its middle at the pane's middle: a click in the minimap.
        case centered
        /// Where a remembered position had it: the pane's top `offset` points below the row's top, and scrolled `x`
        /// points sideways (book TAB-10).
        case restored(offset: Double, x: Double)
    }

    /// The most placements one request makes: its own, then those that follow rows moved by layout.
    static let passes = 4
    /// The most text above a row, in UTF-16 units, that a placement lays out rather than place the row after TextKit's
    /// estimates of it: some 200 lines, which added 2.5 ms to opening a file in a release build.
    static let textLaidOutAbove = 8_192

    let row: Int
    let anchor: Anchor
}
