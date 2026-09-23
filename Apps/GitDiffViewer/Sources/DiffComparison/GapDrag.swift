package import CoreGraphics
package import DiffCore
package import DiffRendering

/// A drag on one gap handle, as the rows it reveals from where it began (book DIFF-02). Pure, so the direction and
/// clamping rules and the edge-hold rate are tested without a view.
///
/// Travel along the handle's direction reveals rows, one per row height; travel back hides them again, down to the
/// state the drag began from and never past it, so a drag against the handle's direction discloses nothing. Held in
/// the edge zone of the viewport or the card, the handle keeps revealing, one row per ``holdInterval``.
package struct GapDrag: Equatable, Sendable {
    package let key: GapKey
    package let handle: GapHandle
    /// The gap's expansion when the drag began: the state it returns to, and never goes past.
    package let base: GapExpansion
    /// The rows the gap hid when the drag began: the most the drag reveals.
    package let limit: Int
    /// Points per row, which turn the pointer's travel into rows.
    package let lineHeight: CGFloat
    /// Rows the pointer's travel asks for, signed: positive along the handle's direction.
    private var travelled = 0
    /// Rows revealed while the pointer was held in an edge zone, on top of its travel.
    private var held = 0
    /// How far the pointer sits into the edge zone in the handle's direction, in points; zero or less when clear.
    private var edgeOvershoot: CGFloat = 0

    /// The pointer's depth into the edge zone at which the hold reaches its fastest rate.
    package static let rampDepth: CGFloat = 60
    /// One row every 200 ms where the edge zone begins,
    package static let slowestHold: Duration = .milliseconds(200)
    /// rising to one every 60 ms, about 16 rows a second, however far past the edge the pointer goes.
    package static let fastestHold: Duration = .milliseconds(60)

    package init(marker: GapMarker, handle: GapHandle, base: GapExpansion, lineHeight: CGFloat) {
        key = marker.key
        self.handle = handle
        self.base = base
        limit = max(marker.hiddenRows, 0)
        self.lineHeight = max(lineHeight, 1)
    }

    /// Rows revealed beyond ``base``: none for a drag against the handle's direction, at most what the gap hid.
    package var revealed: Int {
        min(max(travelled + held, 0), limit)
    }

    /// The gap's expansion for where the drag stands: the handle's own side grows, the other side stays as it was.
    package var expansion: GapExpansion {
        switch handle {
            case .extendsChangeAbove: GapExpansion(below: base.below + revealed, above: base.above)
            case .extendsChangeBelow: GapExpansion(below: base.below, above: base.above + revealed)
        }
    }

    /// How long to wait before the next row while the pointer stays where it is: nil unless it sits in an edge zone
    /// in the handle's direction and the gap still hides rows.
    package var holdInterval: Duration? {
        guard revealed < limit else { return nil }
        return Self.holdInterval(overshoot: edgeOvershoot)
    }

    /// Follows the pointer, `offset` points below where the drag began (negative above) and `edgeOvershoot` points
    /// into the edge zone in the handle's direction.
    package mutating func move(offset: CGFloat, edgeOvershoot: CGFloat) {
        travelled = Int((offset * handle.revealDirection / lineHeight).rounded())
        self.edgeOvershoot = edgeOvershoot
    }

    /// Reveals one more row for a pointer held in an edge zone; nothing once the gap is open.
    package mutating func hold() {
        guard travelled + held < limit else { return }
        held += 1
    }

    /// Reveals every row the gap hid.
    package mutating func revealAll() {
        travelled = 0
        held = limit
    }

    /// The wait between rows for a pointer `overshoot` points into the edge zone: from ``slowestHold`` where the zone
    /// begins, linearly down to ``fastestHold`` at ``rampDepth`` and beyond, so the rate stays bounded; nil outside.
    package static func holdInterval(overshoot: CGFloat) -> Duration? {
        guard overshoot > 0 else { return nil }
        let progress = Double(min(overshoot / rampDepth, 1))
        let slowest = slowestHold / .milliseconds(1)
        let fastest = fastestHold / .milliseconds(1)
        return .milliseconds(slowest - (slowest - fastest) * progress)
    }
}
