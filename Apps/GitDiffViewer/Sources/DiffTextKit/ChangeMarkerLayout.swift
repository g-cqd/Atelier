package import CoreGraphics

/// Where the compact inline view's change markers sit in the gutter (book DIFF-04; `compact-inline-design.md`). Every
/// marker lies in the gutter's change layer, on its trailing side, between the line numbers and the scope ribbon, next
/// to the text (`scope-ribbon-design.md`): a bar with round ends down a change's rows, or, for a folded removal, a
/// wedge pointing into the text on the boundary where the lines were. Pure geometry, in the gutter's flipped
/// coordinates, from the change layer's leading edge `layerX`.
package enum ChangeMarkerLayout {
    /// A marker's shape: a bar over a change's rows, or a wedge for a folded removal.
    package enum Shape: Equatable {
        case bar(CGRect)
        /// The triangle's bounding box: its flat side on the left, its point in the middle of the right side.
        case wedge(CGRect)

        package var rect: CGRect {
            switch self {
                case .bar(let rect), .wedge(let rect): rect
            }
        }
    }

    /// Where a wedge sits against the boundary it marks.
    package enum WedgePlacement {
        /// Across the boundary, half above it and half below.
        case centred
        /// Just below it, inside the row after: at the top of the file, or under a gap's band.
        case below
        /// Just above it, inside the last row: at the end of the file.
        case above
    }

    /// The change layer's width: what takes the pointer for a marker.
    package static let hitWidth: CGFloat = 6
    /// The bar's distance from the change layer's leading edge.
    package static let barX: CGFloat = 1
    package static let barWidth: CGFloat = 3
    /// The bar under the pointer, a point wider.
    package static let hoveredBarWidth: CGFloat = 4
    package static let wedgeWidth: CGFloat = 5
    package static let wedgeHeight: CGFloat = 7
    /// The wedge's distance from the change layer's leading edge.
    package static let wedgeX: CGFloat = 0.5

    /// A bar from `top` to `bottom`, the change's first row's top and its last row's own bottom.
    package static func bar(top: CGFloat, bottom: CGFloat, isHovered: Bool, layerX: CGFloat) -> CGRect {
        CGRect(
            x: layerX + barX, y: top, width: isHovered ? hoveredBarWidth : barWidth, height: max(bottom - top, barWidth)
        )
    }

    /// A wedge on the boundary at `y`.
    package static func wedge(at y: CGFloat, placement: WedgePlacement, layerX: CGFloat) -> CGRect {
        let top: CGFloat =
            switch placement {
                case .centred: y - wedgeHeight / 2
                case .below: y
                case .above: y - wedgeHeight
            }
        return CGRect(x: layerX + wedgeX, y: top, width: wedgeWidth, height: wedgeHeight)
    }

    /// Where the pointer counts as over a marker: the change layer, across the bar and a point beyond its ends, or
    /// half a row either side of a wedge's middle.
    package static func hitArea(of shape: Shape, lineHeight: CGFloat, layerX: CGFloat) -> CGRect {
        switch shape {
            case .bar(let rect):
                CGRect(x: layerX, y: rect.minY - 1, width: hitWidth, height: rect.height + 2)
            case .wedge(let rect):
                CGRect(x: layerX, y: rect.midY - lineHeight / 2, width: hitWidth, height: lineHeight)
        }
    }
}
