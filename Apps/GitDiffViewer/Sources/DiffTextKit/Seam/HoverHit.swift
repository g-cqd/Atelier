package import Foundation

/// Which side of a diff a hover hit falls on: the row's old line number, or its new one.
package enum HoverSide: Sendable, Equatable {
    case old
    case new
}

/// A point over an identifier, resolved to the source position it belongs to.
package struct HoverHit: Sendable, Equatable {
    package let fileIndex: Int
    package let side: HoverSide
    /// Zero-based source line: `(newNumber ?? oldNumber) - 1`.
    package let line: Int
    /// Zero-based UTF-16 column within the row's own text.
    package let utf16Column: Int
    /// The row index in `RenderedText.rows`/`lineStarts`.
    package let row: Int
    /// The hovered identifier run's bounds, in text-view coordinates, as laid out when the hit was made.
    package let anchorRect: NSRect
    /// The identifier's document-absolute UTF-16 range in `RenderedText.attributed`, to re-locate it after a scroll.
    package let identifierRange: NSRange
}
