package import CoreGraphics
package import DiffRendering

/// Where a gap's handles sit in the gutter, after Xcode's (book DIFF-02): one rounded rectangle about 20 × 14 points,
/// centred across the gutter on the hairline that marks the gap on the boundary between two rows, and split by it
/// into two halves. Each half is a handle of its own, rounded toward the change it extends and flat on the hairline,
/// the side it is dragged toward: the upper half lies over the bottom of the row above and extends the change above,
/// the lower half over the top of the row below and extends the change below. A gap that grows from one side only
/// shows that side's half. Pure geometry, in the gutter's flipped coordinates.
package enum GapHandleLayout {
    /// One half of a gap's rectangle.
    package struct Half: Equatable {
        package let handle: GapHandle
        /// The half drawn, from the hairline to its rounded side.
        package let rect: CGRect
        /// Where the pointer counts as over it: `rect`, a little taller on its rounded side.
        package let hitArea: CGRect
    }

    package static let width: CGFloat = 20
    /// The height of each half, from the hairline: the rectangle is twice as tall.
    package static let halfHeight: CGFloat = 7
    package static let cornerRadius: CGFloat = 3.5
    /// How much taller than its half a half's hit area is, away from the hairline.
    package static let hitSlop: CGFloat = 3
    /// How far a half reaches from its hairline, hit area included: the band a redraw or a hit test looks around.
    package static let reach: CGFloat = halfHeight + hitSlop
    /// How deep, from the edge of what shows of the gutter, a held pointer starts to count as at the edge.
    package static let edgeZone: CGFloat = 16

    /// The halves `handles` asks for, on the hairline at `boundaryY` of a gutter `gutterWidth` wide, centred across it
    /// and narrowed to fit a gutter too narrow for them.
    package static func halves(_ handles: [GapHandle], boundaryY: CGFloat, gutterWidth: CGFloat) -> [Half] {
        let halfWidth = min(width, max(gutterWidth - 8, 8))
        let x = (gutterWidth - halfWidth) / 2
        return handles.map { handle in
            switch handle {
                case .extendsChangeAbove:
                    Half(
                        handle: handle,
                        rect: CGRect(x: x, y: boundaryY - halfHeight, width: halfWidth, height: halfHeight),
                        hitArea: CGRect(x: x, y: boundaryY - reach, width: halfWidth, height: reach))
                case .extendsChangeBelow:
                    Half(
                        handle: handle, rect: CGRect(x: x, y: boundaryY, width: halfWidth, height: halfHeight),
                        hitArea: CGRect(x: x, y: boundaryY, width: halfWidth, height: reach))
            }
        }
    }

    /// How far a pointer at `pointerY` sits into the edge zone of `visible`, what shows of the gutter, in the
    /// direction a handle reveals by: positive once within ``edgeZone`` of that edge, growing past it; zero or less
    /// while clear of it. What shows is the viewport or the card, whichever edge comes first.
    package static func edgeOvershoot(pointerY: CGFloat, visible: CGRect, direction: CGFloat) -> CGFloat {
        direction > 0 ? pointerY - (visible.maxY - edgeZone) : (visible.minY + edgeZone) - pointerY
    }
}
