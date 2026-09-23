package import CoreGraphics
package import DiffRendering

/// Where a gap's handles sit in the gutter, after Xcode's (book DIFF-02): one rounded rectangle, 18 × 14 points,
/// centred on the hairline that marks the gap on the boundary between two rows, and split by it into two halves.
/// Each half is a handle of its own, rounded toward the change it extends and flat on the hairline, the side it is
/// dragged toward: the upper half lies over the bottom of the row above and extends the change above, the lower half
/// over the top of the row below and extends the change below. A gap that grows from one side only shows that side's
/// half. Pure geometry, in the gutter's flipped coordinates.
///
/// The rectangle is centred in a lane at the gutter's leading edge, clear of the line numbers: a hidden run takes no
/// row, so the halves lie over the rows around it, where those rows' numbers are.
package enum GapHandleLayout {
    /// One half of a gap's rectangle.
    package struct Half: Equatable {
        package let handle: GapHandle
        /// The half drawn, from the hairline to its rounded side.
        package let rect: CGRect
        /// Where the pointer counts as over it: `rect`, a little taller on its rounded side.
        package let hitArea: CGRect
    }

    /// The rectangle's width, as in Xcode.
    package static let width: CGFloat = 18
    /// The space on each side of the rectangle in its lane.
    package static let margin: CGFloat = 2
    /// The lane at the gutter's leading edge that holds the handles; the line numbers start after it.
    package static let laneWidth: CGFloat = width + 2 * margin
    /// The height of each half, from the hairline, among rows tall enough for it: the rectangle is twice as tall.
    package static let halfHeight: CGFloat = 7
    package static let cornerRadius: CGFloat = 3.5
    /// How much taller than its half a half's hit area is, away from the hairline.
    package static let hitSlop: CGFloat = 3
    /// How far a half reaches from its hairline, hit area included: the band a redraw or a hit test looks around.
    package static let reach: CGFloat = halfHeight + hitSlop
    /// How deep, from the edge of what shows of the gutter, a held pointer starts to count as at the edge.
    package static let edgeZone: CGFloat = 16

    /// The halves `handles` asks for on the hairline at `boundaryY`, centred in the lane, among rows `rowHeight`
    /// tall. Rows too short for the rectangle shorten its halves, so the halves of two boundaries a row apart never
    /// meet.
    package static func halves(_ handles: [GapHandle], boundaryY: CGFloat, rowHeight: CGFloat) -> [Half] {
        let height = max(min(halfHeight, ((rowHeight - 1) / 2).rounded(.down)), 1)
        return handles.map { handle in
            switch handle {
                case .extendsChangeAbove:
                    Half(
                        handle: handle, rect: CGRect(x: margin, y: boundaryY - height, width: width, height: height),
                        hitArea: CGRect(
                            x: margin, y: boundaryY - height - hitSlop, width: width, height: height + hitSlop))
                case .extendsChangeBelow:
                    Half(
                        handle: handle, rect: CGRect(x: margin, y: boundaryY, width: width, height: height),
                        hitArea: CGRect(x: margin, y: boundaryY, width: width, height: height + hitSlop))
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
