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
}
