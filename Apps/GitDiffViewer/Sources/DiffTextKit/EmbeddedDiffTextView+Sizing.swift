import AppKit
import AtelierDiagnostics
import DiffCore
import DiffRendering
import Foundation
import SwiftUI

// Measuring and preparing the layout for a width; apart from the type's file, to keep it within the limits SwiftLint sets.
extension EmbeddedDiffTextView {
    /// Sizes the text view to the layout. Lines that fit take the clip view's width exactly and follow it: the width
    /// the card measured can differ from the clip by a point or two, and a text view wider by that much would scroll
    /// sideways by that much. Before the pane has a width the clip has none either, and the text view starts at none
    /// too, so that following the clip as it widens leaves it exactly as wide.
    func size(
        _ textView: NSTextView,
        in pane: DiffPaneView,
        for layout: StaticTextLayout,
        textWidth: CGFloat,
        coordinator: Coordinator
    ) {
        let scrollView = pane.contentView as? NSScrollView
        let fits = layout.contentWidth <= textWidth + 0.5
        let viewWidth = fits ? max(scrollView?.contentView.bounds.width ?? textWidth, 0) : layout.contentWidth
        let frameSize = NSSize(width: viewWidth, height: layout.height)
        guard coordinator.appliedSize != frameSize || coordinator.appliedMode != wrapMode else { return }
        coordinator.appliedSize = frameSize
        coordinator.appliedMode = wrapMode
        // Without wrapping, the container follows a view already as wide as the longest line, so TextKit lays out
        // only what shows: a container of fixed width makes every frame change lay out the whole document.
        let tracksView = wrapMode == .none
        textView.textContainer?.widthTracksTextView = tracksView
        if !tracksView {
            textView.textContainer?.size = NSSize(width: layout.width, height: DiffPaneMetrics.unboundedExtent)
        } else if layout.sharesLayout {
            // The layout's container follows the view from the next change of its frame, which may not come.
            textView.textContainer?.size = NSSize(width: frameSize.width, height: DiffPaneMetrics.unboundedExtent)
        }
        textView.autoresizingMask = fits ? [.width] : []
        textView.setFrameSize(frameSize)
        textView.needsDisplay = true
        pane.needsLayout = true
    }

    func prepare(_ layout: StaticTextLayout, textWidth: CGFloat) {
        if side == .unified {
            layout.layOut(mode: wrapMode, viewportWidth: textWidth)
        } else {
            layouts.prepareSplit(width: textWidth, mode: wrapMode)
        }
    }
}
