package import AppKit
import DiffCore
import Foundation
import SwiftUI

/// Geometry every diff pane shares, attached or detached, so a card measured by `StaticTextLayout` comes out the
/// same size as the text view that displays it.
package enum DiffPaneMetrics {
    package static let lineFragmentPadding: CGFloat = 6
    package static let containerInset: CGFloat = 4
    /// Container extent along an axis that must neither wrap nor clip. Finite because fragment surfaces derived
    /// from it must stay below the maximum layer size, or they draw nothing at all.
    package static let unboundedExtent: CGFloat = 1_000_000
}
