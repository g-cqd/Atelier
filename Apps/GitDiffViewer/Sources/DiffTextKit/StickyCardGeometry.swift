package import CoreGraphics

/// Where a sticky card's clip and header sit for one scroll position, in the card's flipped coordinates.
///
/// The clip's top follows the pin line down the card, so the header stays put while the body scrolls beneath it.
/// The clip stops once only the header is left, so the card's bottom then pushes the header out.
package struct StickyCardGeometry: Equatable, Sendable {
    /// The longest length a card accepts from a measurement. Far above any real card, and far below the lengths
    /// whose sums overflow to infinity and whose differences then turn into NaN.
    package static let maximumLength: CGFloat = 10_000_000

    /// How far the clip's top sits below the card's top: 0 at rest, at most the card's height less the header's.
    package let offset: CGFloat
    /// The visible card, `(0, offset, width, height - offset)`: the clip view's frame and the shadow's outline.
    package let clipFrame: CGRect
    /// The height of the body's clip below the header: the card's height less the header's, which a fold shrinks
    /// to zero and an unfold grows back while the body keeps its own height.
    package let bodyClipHeight: CGFloat
    /// The header's height, zero when the measured one is malformed.
    package let headerHeight: CGFloat

    /// - Parameters:
    ///   - pinY: The y the header's top sticks to; zero or less while the card's top is below it.
    ///   - size: The card's size, header included.
    ///   - headerHeight: The header's height.
    /// A NaN `pinY` counts as zero, and negative or non-finite lengths as zero.
    package init(pinY: CGFloat, size: CGSize, headerHeight: CGFloat) {
        let height = Self.sanitized(size.height)
        self.headerHeight = Self.sanitized(headerHeight)
        let travel = max(height - self.headerHeight, 0)
        offset = min(max(pinY.isNaN ? 0 : pinY, 0), travel)
        clipFrame = CGRect(x: 0, y: offset, width: Self.sanitized(size.width), height: height - offset)
        bodyClipHeight = travel
    }

    /// The origin, inside the body's clip, that keeps the body fixed to the card while the clip moves.
    package var bodyOrigin: CGPoint { CGPoint(x: 0, y: -offset) }

    /// Whether the header has left its resting place at the card's top.
    package var isPinned: Bool { offset > 0 }

    /// Whether any of the body shows: false once a fold has finished, and for a card only a header tall.
    package var showsBody: Bool { bodyClipHeight > 0 }

    /// The height the body is laid out at.
    /// - Parameter bodyHeight: The body's own height, as measured; a malformed one counts as zero.
    /// - Returns: The body's own height, so the card's moving edge clips the body rather than squeezing it, and never
    ///   less than its clip, so a body measured short still covers what shows.
    package func bodyFrameHeight(bodyHeight: CGFloat) -> CGFloat {
        max(Self.sanitized(bodyHeight), bodyClipHeight)
    }

    /// The height of a card part of the way through a fold. Malformed heights count as zero.
    /// - Parameters:
    ///   - headerHeight: The header's height.
    ///   - bodyHeight: The body's own height.
    ///   - foldProgress: 0 unfolded, 1 folded; values outside are clamped, and NaN counts as 0.
    /// - Returns: The header's height and the part of the body's the fold has not clipped away yet.
    package static func cardHeight(headerHeight: CGFloat, bodyHeight: CGFloat, foldProgress: CGFloat) -> CGFloat {
        let folded = foldProgress.isNaN ? 0 : min(max(foldProgress, 0), 1)
        return sanitized(headerHeight) + sanitized(bodyHeight) * (1 - folded)
    }

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

    /// A measured length a card can hand to AppKit and SwiftUI.
    /// - Parameters:
    ///   - length: The measured length.
    ///   - fallback: The length to use instead, such as the last one measured; itself clamped to the same range.
    /// - Returns: `length` when it is finite, non-negative and at most ``maximumLength``, `fallback` otherwise.
    package static func length(_ length: CGFloat, fallback: CGFloat) -> CGFloat {
        isAcceptable(length) ? length : min(sanitized(fallback), maximumLength)
    }

    /// Whether a measured length is finite, non-negative and at most ``maximumLength``.
    package static func isAcceptable(_ length: CGFloat) -> Bool {
        length.isFinite && length >= 0 && length <= maximumLength
    }

    private static func sanitized(_ length: CGFloat) -> CGFloat {
        length.isFinite ? max(length, 0) : 0
    }
}
