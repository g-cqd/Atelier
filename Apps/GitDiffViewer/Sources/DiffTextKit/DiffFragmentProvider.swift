package import AppKit
import DiffCore
package import DiffRendering
import Foundation
import SwiftUI

/// Layout delegate that gives every paragraph a `DiffLayoutFragment` carrying its row's background and the pane's
/// viewport width. One implementation serves the scrolling panes, the embedded card panes and the detached
/// measuring layouts, so they all colour rows identically.
@MainActor
package final class DiffFragmentProvider: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
    package let metrics: ViewportMetrics
    package var rendered: RenderedText?
    /// Diagnostics for the pane's rows, which each fragment made here keeps and reads as it draws. TextKit keeps its
    /// fragments when this changes, even through a layout invalidation, so a pane sets it once and changes the
    /// overlay's content instead (``DiffTextViewCoordinator/diagnostics``).
    package var overlay: DiagnosticOverlay?
    /// Where the pane keeps the decorations of the text it shows, which each fragment made here reads as it draws.
    /// Set before the layout manager lays anything out, as ``overlay`` is.
    package var decorations: DecorationSnapshot?

    package init(rendered: RenderedText? = nil, metrics: ViewportMetrics = ViewportMetrics()) {
        self.rendered = rendered
        self.metrics = metrics
    }

    package func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = DiffLayoutFragment(textElement: textElement, range: textElement.elementRange)
        fragment.metrics = metrics
        fragment.baselineOffset = rendered?.baselineOffset ?? 0
        fragment.overlay = overlay
        fragment.decorations = decorations
        guard let rendered, let contentManager = textLayoutManager.textContentManager else { return fragment }
        let offset = contentManager.offset(from: textLayoutManager.documentRange.location, to: location)
        fragment.rendered = rendered
        fragment.row = rendered.row(containing: offset)
        if !rendered.rows.isEmpty {
            fragment.rowIndex = rendered.rowIndex(containing: offset)
            if let gap = rendered.bandedGap(afterRow: fragment.rowIndex) {
                fragment.bandBelow = rendered.gapBandHeight
                fragment.separatorColor = gap.hasSeparator ? rendered.palette.gapSeparator : nil
            }
        }
        return fragment
    }
}
