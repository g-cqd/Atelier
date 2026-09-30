package import AppKit
import AtelierTextRendering
import AtelierTextView

/// Where a CoreText pane's rows lie, read from its `TextCanvasView` (text-renderer.md §4.2).
@MainActor
package struct CoreTextRowGeometry: DiffRowGeometry {
    let canvasView: TextCanvasView

    package var documentHeight: CGFloat { CGFloat(canvasView.documentHeight) }

    package func forEachRow(in rect: CGRect, _ body: (_ row: Int, _ frame: CGRect, _ firstBaseline: CGFloat) -> Void) {
        canvasView.forEachRow(in: rect) { row, frame, baseline in body(row.index, frame, CGFloat(baseline)) }
    }

    package func visibleRows() -> Range<Int> {
        let range = canvasView.visibleRowRange()
        return range.lowerBound.index ..< range.upperBound.index
    }

    package func frame(ofRow row: Int) -> (frame: CGRect, firstBaseline: CGFloat)? {
        guard let (frame, baseline) = canvasView.frame(ofRow: RowIndex(row)) else { return nil }
        return (frame, CGFloat(baseline))
    }
}
