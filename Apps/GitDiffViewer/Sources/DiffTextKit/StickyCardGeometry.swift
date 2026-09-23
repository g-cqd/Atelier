package import CoreGraphics

/// Where a sticky card's clip and header sit for one scroll position, in the card's flipped coordinates.
///
/// The clip's top follows the pin line down the card, so the header stays put while the body scrolls beneath it.
/// The clip stops once only the header is left, so the card's bottom then pushes the header out.
package struct StickyCardGeometry: Equatable, Sendable {
    /// How far the clip's top sits below the card's top: 0 at rest, at most the card's height less the header's.
    package let offset: CGFloat
    /// The visible card, `(0, offset, width, height - offset)`: the clip view's frame and the shadow's outline.
    package let clipFrame: CGRect

    /// - Parameters:
    ///   - pinY: The y the header's top sticks to; zero or less while the card's top is below it.
    ///   - size: The card's size, header included.
    ///   - headerHeight: The header's height.
    /// A NaN `pinY` counts as zero, and negative or non-finite sizes as zero.
    package init(pinY: CGFloat, size: CGSize, headerHeight: CGFloat) {
        let height = Self.sanitized(size.height)
        let travel = max(height - Self.sanitized(headerHeight), 0)
        offset = min(max(pinY.isNaN ? 0 : pinY, 0), travel)
        clipFrame = CGRect(x: 0, y: offset, width: Self.sanitized(size.width), height: height - offset)
    }

    /// The origin, inside the body's clip, that keeps the body fixed to the card while the clip moves.
    package var bodyOrigin: CGPoint { CGPoint(x: 0, y: -offset) }

    /// Whether the header has left its resting place at the card's top.
    package var isPinned: Bool { offset > 0 }

    /// The pin line in a scroll view's clip view coordinates: `gap` below the first row that the bars over the
    /// scroll view's top leave visible.
    /// - Parameters:
    ///   - clipBounds: The clip view's bounds, which scrolling moves.
    ///   - topInset: The clip view's top content inset: the height of the bars drawn over it.
    ///   - gap: The space kept between those bars and a sticking header.
    ///   - isFlipped: Whether the clip view's y axis points down.
    /// - Returns: The pin line's y in the clip view's coordinates.
    package static func pinY(clipBounds: CGRect, topInset: CGFloat, gap: CGFloat, isFlipped: Bool) -> CGFloat {
        isFlipped ? clipBounds.minY + topInset + gap : clipBounds.maxY - topInset - gap
    }

    private static func sanitized(_ length: CGFloat) -> CGFloat {
        length.isFinite ? max(length, 0) : 0
    }
}
