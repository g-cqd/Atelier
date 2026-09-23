package import CoreGraphics
package import DiffRendering

/// Where a gap's handle sits in its band, after Xcode's (book DIFF-02). A gap offering a handle takes an empty band
/// between the rows around it, and its handle is one rounded rectangle, 18 points wide, centred across the gutter and
/// as tall as the band, split by a hairline that crosses the gutter. Each half is a handle of its own, rounded toward
/// the change it extends and flat on the hairline, the side it is dragged toward: the upper half extends the change
/// above, the lower half the change below. A gap that grows from one side only shows that side's half, taller, with
/// the hairline near the band's far edge. Xcode's two halves make 18 × 19 points and a lone half is 13 points tall,
/// against 18-point lines. Pure geometry, in the gutter's flipped coordinates.
package enum GapHandleLayout {
    /// One half of a gap's handle.
    package struct Half: Equatable {
        package let handle: GapHandle
        /// The half drawn, from the hairline to its rounded side.
        package let rect: CGRect
        /// The grip line across it.
        package let grip: CGRect
        /// Where the pointer counts as over it: its part of the band, across the gutter.
        package let hitArea: CGRect
    }

    /// A gap's handle in its band: the hairline across the gutter, and the halves the gap offers.
    package struct Handle: Equatable {
        package let hairline: CGRect
        package let halves: [Half]
    }

    package static let width: CGFloat = 18
    /// The radius of a half's rounded corners, to the outside of its outline.
    package static let cornerRadius: CGFloat = 4
    /// The length of the grip line across a half.
    package static let gripLength: CGFloat = 8
    /// A lone half's height, as a share of the line height: 13 points against Xcode's 18-point lines.
    package static let loneHalfShare: CGFloat = 13.0 / 18.0
    /// How deep, from the edge of what shows of the gutter, a held pointer starts to count as at the edge.
    package static let edgeZone: CGFloat = 16

    /// The handle a gap offering `handles` shows in its `band`, which spans the gutter less its separator, among rows
    /// `lineHeight` tall: centred across the band, to the nearest point.
    package static func handle(_ handles: [GapHandle], in band: CGRect, lineHeight: CGFloat) -> Handle {
        let halfWidth = min(width, max(band.width - 4, 4))
        // On whole points, so the outline's sides stay sharp in a gutter of fractional width.
        let x = (band.midX - halfWidth / 2).rounded()
        let hasAbove = handles.contains(.extendsChangeAbove)
        let hasBelow = handles.contains(.extendsChangeBelow)
        // Both halves share the band and the hairline across its middle; a lone half keeps its hairline near the
        // band's far edge and takes the rest.
        let lone = min((lineHeight * loneHalfShare).rounded(), band.height - 1)
        let hairlineY: CGFloat =
            switch (hasAbove, hasBelow) {
                case (true, false): band.minY + lone
                case (false, true): band.maxY - lone - 1
                default: band.minY + (band.height - 1) / 2
            }
        let hairline = CGRect(x: band.minX, y: hairlineY, width: band.width, height: 1)
        let halves = handles.map { handle in
            // Two halves split the band at the hairline's middle; a lone half has the whole band.
            let rect: CGRect
            let hitArea: CGRect
            let interior: ClosedRange<CGFloat>
            switch handle {
                case .extendsChangeAbove:
                    rect = CGRect(x: x, y: band.minY, width: halfWidth, height: hairline.minY - band.minY)
                    hitArea =
                        hasBelow ? band.divided(atDistance: hairline.midY - band.minY, from: .minYEdge).slice : band
                    // Inside its outline at the top, and down to the hairline, or to its own flat side when alone.
                    interior = (rect.minY + 1) ... (rect.maxY - (hasBelow ? 0 : 1))
                case .extendsChangeBelow:
                    rect = CGRect(x: x, y: hairline.maxY, width: halfWidth, height: band.maxY - hairline.maxY)
                    hitArea =
                        hasAbove ? band.divided(atDistance: band.maxY - hairline.midY, from: .maxYEdge).slice : band
                    interior = (rect.minY + (hasAbove ? 0 : 1)) ... (rect.maxY - 1)
            }
            // Centred in the half's interior, rounded to a whole point from the band's top, as Xcode's are.
            let gripY = band.minY + ((interior.lowerBound + interior.upperBound) / 2 - 0.5 - band.minY).rounded()
            let gripWidth = min(gripLength, max(halfWidth - 6, 2))
            return Half(
                handle: handle, rect: rect,
                grip: CGRect(x: rect.midX - gripWidth / 2, y: gripY, width: gripWidth, height: 1), hitArea: hitArea)
        }
        return Handle(hairline: hairline, halves: halves)
    }

    /// How far a pointer at `pointerY` sits into the edge zone of `visible`, what shows of the gutter, in the
    /// direction a handle reveals by: positive once within ``edgeZone`` of that edge, growing past it; zero or less
    /// while clear of it. What shows is the viewport or the card, whichever edge comes first.
    package static func edgeOvershoot(pointerY: CGFloat, visible: CGRect, direction: CGFloat) -> CGFloat {
        direction > 0 ? pointerY - (visible.maxY - edgeZone) : (visible.minY + edgeZone) - pointerY
    }
}
