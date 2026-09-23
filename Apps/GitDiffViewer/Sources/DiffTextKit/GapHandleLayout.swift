package import CoreGraphics
package import DiffRendering

/// Where a gap's handle sits in its band (book DIFF-02). A gap offering a handle takes an empty band exactly one row
/// tall, and its handle fits in it: one small rounded rectangle, centred across the gutter, split into two halves by
/// a separator across the band's middle. Each half is a handle of its own, rounded toward the change it extends and
/// flat on the side it is dragged toward: the upper half extends the change above, the lower half the change below.
/// At the top of a file the lower half shows alone, flat against the band's top edge; at the end of a file the upper
/// half shows alone, flat against its bottom edge; neither has a separator. Pure geometry, in the gutter's flipped
/// coordinates.
package enum GapHandleLayout {
    /// One half of a gap's handle.
    package struct Half: Equatable {
        package let handle: GapHandle
        /// The half drawn, from its flat side to its rounded one.
        package let rect: CGRect
        /// The grip line across it.
        package let grip: CGRect
        /// Where the pointer counts as over it: its part of the band, across the gutter.
        package let hitArea: CGRect
    }

    /// A gap's handle in its band: the halves the gap offers, and the separator between two of them, across the gutter.
    package struct Handle: Equatable {
        package let separator: CGRect?
        package let halves: [Half]
    }

    package static let width: CGFloat = 14
    /// The radius of a half's rounded corners, to the outside of its outline.
    package static let cornerRadius: CGFloat = 3
    /// The length of the grip line across a half.
    package static let gripLength: CGFloat = 6
    /// The space between a half's rounded side and the row it faces.
    package static let clearance: CGFloat = 1
    /// How deep, from the edge of what shows of the gutter, a held pointer starts to count as at the edge.
    package static let edgeZone: CGFloat = 16

    /// How far below its band's top the separator of a band `bandHeight` tall lies: across its middle. The gutter and
    /// the text draw it at the same height.
    package static func separatorOffset(bandHeight: CGFloat) -> CGFloat {
        (bandHeight - 1) / 2
    }

    /// The handle a gap offering `handles` shows in its `band`, which spans the gutter less its separator: centred
    /// across the band, to the nearest point.
    package static func handle(_ handles: [GapHandle], in band: CGRect) -> Handle {
        let halfWidth = min(width, max(band.width - 4, 4))
        // On whole points, so the outline's sides stay sharp in a gutter of fractional width.
        let x = (band.midX - halfWidth / 2).rounded()
        // Every half is the same size: half the band, less the separator and some clearance.
        let height = max(separatorOffset(bandHeight: band.height) - clearance, 2)
        let separator: CGRect? =
            handles.count == 2
            ? CGRect(
                x: band.minX, y: band.minY + separatorOffset(bandHeight: band.height), width: band.width, height: 1)
            : nil
        let halves = handles.map { handle in
            // Two halves split the band at the separator's middle; a lone half has the whole band.
            let rect: CGRect
            let hitArea: CGRect
            switch (handle, separator) {
                case (.extendsChangeAbove, let separator?):
                    rect = CGRect(x: x, y: separator.minY - height, width: halfWidth, height: height)
                    hitArea = band.divided(atDistance: separator.midY - band.minY, from: .minYEdge).slice
                case (.extendsChangeBelow, let separator?):
                    rect = CGRect(x: x, y: separator.maxY, width: halfWidth, height: height)
                    hitArea = band.divided(atDistance: band.maxY - separator.midY, from: .maxYEdge).slice
                case (.extendsChangeAbove, nil):
                    rect = CGRect(x: x, y: band.maxY - height, width: halfWidth, height: height)
                    hitArea = band
                case (.extendsChangeBelow, nil):
                    rect = CGRect(x: x, y: band.minY, width: halfWidth, height: height)
                    hitArea = band
            }
            // Inside the outline on the rounded side; the flat side lies on the separator or the band's edge.
            let isUpper = handle == .extendsChangeAbove
            let interior = isUpper ? (rect.minY + 1) ... rect.maxY : rect.minY ... (rect.maxY - 1)
            // Centred in the interior, rounded to a whole point from the band's top.
            let gripY = band.minY + ((interior.lowerBound + interior.upperBound) / 2 - 0.5 - band.minY).rounded()
            let gripWidth = min(gripLength, max(halfWidth - 6, 2))
            return Half(
                handle: handle, rect: rect,
                grip: CGRect(x: rect.midX - gripWidth / 2, y: gripY, width: gripWidth, height: 1), hitArea: hitArea)
        }
        return Handle(separator: separator, halves: halves)
    }

    /// How far a pointer at `pointerY` sits into the edge zone of `visible`, what shows of the gutter, in the
    /// direction a handle reveals by: positive once within ``edgeZone`` of that edge, growing past it; zero or less
    /// while clear of it. What shows is the viewport or the card, whichever edge comes first.
    package static func edgeOvershoot(pointerY: CGFloat, visible: CGRect, direction: CGFloat) -> CGFloat {
        direction > 0 ? pointerY - (visible.maxY - edgeZone) : (visible.minY + edgeZone) - pointerY
    }
}
