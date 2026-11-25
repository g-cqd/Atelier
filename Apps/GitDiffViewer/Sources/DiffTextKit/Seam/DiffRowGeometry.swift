package import CoreGraphics

/// Row positions in a pane's document coordinates, for the gutter, the minimap and the overscroll
/// (text-renderer.md §4.1).
@MainActor
package protocol DiffRowGeometry {
    /// The height of the rows, from the top of the first to the bottom of the last, in document coordinates.
    var documentHeight: CGFloat { get }

    /// Rows intersecting `rect`, top to bottom, with each row's frame and its first line's baseline, in document
    /// coordinates.
    /// - Complexity: O(log rows + rows in rect); never lays out rows outside `rect`.
    func forEachRow(in rect: CGRect, _ body: (_ row: Int, _ frame: CGRect, _ firstBaseline: CGFloat) -> Void)

    /// The rows intersecting the pane's visible rect.
    func visibleRows() -> Range<Int>

    /// `row`'s own frame and first-line baseline, laying it out first if it is not yet, direct rather than found by
    /// walking from a rect: for a jump to one row by index, such as a diagnostic's line number (`DiffGutterView`), not
    /// for a scan of what shows. Nil for a row that does not exist.
    func frame(ofRow row: Int) -> (frame: CGRect, firstBaseline: CGFloat)?
}
