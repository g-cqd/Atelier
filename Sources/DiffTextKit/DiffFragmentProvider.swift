import AppKit
import DiffCore
import DiffRendering
import Foundation
import SwiftUI

/// Layout delegate that gives every paragraph a `DiffLayoutFragment` carrying its row's background and the pane's
/// viewport width. One implementation serves the scrolling panes, the embedded card panes and the detached
/// measuring layouts, so they all colour rows identically.
@MainActor
package final class DiffFragmentProvider: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
    package let metrics: ViewportMetrics
    package var rendered: RenderedText?

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
        guard let rendered, let contentManager = textLayoutManager.textContentManager else { return fragment }
        let offset = contentManager.offset(from: textLayoutManager.documentRange.location, to: location)
        if let row = rendered.row(containing: offset) {
            fragment.backgroundColor = rendered.palette.rowBackground(for: row.kind, side: rendered.side, isMoved: row.isMoved)
        }
        return fragment
    }
}
