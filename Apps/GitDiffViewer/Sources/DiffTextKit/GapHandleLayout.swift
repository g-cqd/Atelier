package import CoreGraphics
package import DiffRendering

/// Where a gap row's handles sit in the gutter, after Xcode's (book DIFF-02): a rounded grabber about 20 × 14 points
/// with two lines, centred on a hairline across the gutter where the lines are hidden. A gap between two changes gets
/// two smaller grabbers, one on each side of the hairline, each against the change it extends; a gap at an end of
/// the file gets the one its change can use. Pure geometry, in the gutter's flipped coordinates.
package enum GapHandleLayout {
    /// One handle of a gap row.
    package struct Handle: Equatable {
        package let handle: GapHandle
        /// The grabber drawn for it.
        package let grabber: CGRect
        /// Where the pointer counts as over it: its side of the row, across the whole gutter.
        package let hitArea: CGRect
    }

    package static let grabberWidth: CGFloat = 20
    package static let grabberHeight: CGFloat = 14
    /// The height of each of two grabbers sharing a row; they reach a point past the row at most, short of the
    /// numbers of the rows around it, whose text sits at the floor of its row.
    package static let stackedGrabberHeight: CGFloat = 8
    /// The space between two stacked grabbers, where the hairline runs.
    package static let stackedGap: CGFloat = 1
    /// How deep, from the edge of what shows of the gutter, a held pointer starts to count as at the edge.
    package static let edgeZone: CGFloat = 16

    /// The hairline's height in the row starting at `rowY`: its middle.
    package static func hairlineY(rowY: CGFloat, rowHeight: CGFloat) -> CGFloat {
        rowY + rowHeight / 2
    }

    /// The handles of a gap offering `handles`, in a row `rowHeight` tall starting at `rowY`, in a gutter
    /// `gutterWidth` wide.
    package static func handles(
        _ handles: [GapHandle], rowY: CGFloat, rowHeight: CGFloat, gutterWidth: CGFloat
    ) -> [Handle] {
        let width = min(grabberWidth, max(gutterWidth - 8, 8))
        let x = (gutterWidth - width) / 2
        let middle = hairlineY(rowY: rowY, rowHeight: rowHeight)
        let row = CGRect(x: 0, y: rowY, width: gutterWidth, height: rowHeight)
        guard handles.count == 2 else {
            return handles.map { handle in
                let height = min(grabberHeight, max(rowHeight - 2, 6))
                return Handle(
                    handle: handle, grabber: CGRect(x: x, y: middle - height / 2, width: width, height: height),
                    hitArea: row)
            }
        }
        let half = stackedGap / 2
        return handles.map { handle in
            switch handle {
                case .extendsChangeAbove:
                    Handle(
                        handle: handle,
                        grabber: CGRect(
                            x: x, y: middle - half - stackedGrabberHeight, width: width, height: stackedGrabberHeight),
                        hitArea: CGRect(x: 0, y: rowY, width: gutterWidth, height: middle - rowY))
                case .extendsChangeBelow:
                    Handle(
                        handle: handle,
                        grabber: CGRect(x: x, y: middle + half, width: width, height: stackedGrabberHeight),
                        hitArea: CGRect(x: 0, y: middle, width: gutterWidth, height: row.maxY - middle))
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
