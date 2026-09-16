import AppKit
import DiffCore
import DiffRendering
import Foundation
import SwiftUI

/// A selectable pane that shows its whole document at the height it needs, for file cards inside a SwiftUI
/// scroll view. Measuring and row alignment use the card's detached text system; the card passes its width in,
/// so every change to the text view happens in the update pass and never inside SwiftUI's layout.
package struct EmbeddedDiffTextView: NSViewRepresentable {
    package let layouts: CardLayouts
    package let side: RenderedSide
    package let gutter: GutterStyle
    /// Width of the pane, measured by the card.
    package let width: CGFloat
    package var wrapMode: WrapMode = .viewport
    package var onGapDrag: ((GapMarker, GapExpansion, Int) -> Void)?
    package var currentExpansion: ((GapKey) -> GapExpansion)?
    /// Called once the pane shows a new render.
    package var onDisplayed: (() -> Void)?

    package init(
        layouts: CardLayouts, side: RenderedSide, gutter: GutterStyle, width: CGFloat, wrapMode: WrapMode = .viewport,
        onGapDrag: ((GapMarker, GapExpansion, Int) -> Void)? = nil, currentExpansion: ((GapKey) -> GapExpansion)? = nil, onDisplayed: (() -> Void)? = nil
    ) {
        self.layouts = layouts
        self.side = side
        self.gutter = gutter
        self.width = width
        self.wrapMode = wrapMode
        self.onGapDrag = onGapDrag
        self.currentExpansion = currentExpansion
        self.onDisplayed = onDisplayed
    }

    private var layout: StaticTextLayout? {
        switch side {
        case .unified: layouts.unified
        case .old: layouts.old
        case .new: layouts.new
        }
    }

    package func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    package func makeNSView(context: Context) -> DiffPaneView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = []
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        scrollView.documentView = textView

        let gutterView = DiffGutterView(clipView: nil)
        gutterView.source = textView
        gutterView.style = gutter
        let minimapView = MinimapView()
        minimapView.isHidden = true
        let pane = DiffPaneView(gutterView: gutterView, scrollView: nil, contentView: scrollView, minimapView: minimapView)
        context.coordinator.textView = textView
        update(pane, context: context)
        return pane
    }

    package func updateNSView(_ pane: DiffPaneView, context: Context) {
        update(pane, context: context)
    }

    package static func dismantleNSView(_ pane: DiffPaneView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// Prepares the detached layout for the pane width, then shows it in the text view at the size it measured.
    private func update(_ pane: DiffPaneView, context: Context) {
        pane.gutterView.onGapDrag = onGapDrag
        pane.gutterView.currentExpansion = currentExpansion
        guard let layout, let textView = context.coordinator.textView, width > 0 else { return }
        let textWidth = max(width - pane.gutterView.thickness, 1)
        prepare(layout, textWidth: textWidth)

        let coordinator = context.coordinator
        if coordinator.layout !== layout {
            coordinator.attach(layout)
            pane.gutterView.rendered = layout.rendered
            onDisplayed?()
        }
        // Lines that fit take the clip view's width exactly and follow it: the width the card measured can differ
        // from the clip by a point or two, and a text view wider by that much would scroll sideways by that much.
        let scrollView = pane.contentView as? NSScrollView
        let fits = layout.contentWidth <= textWidth + 0.5
        let width = fits ? max(scrollView?.contentView.bounds.width ?? textWidth, 1) : layout.contentWidth
        let size = NSSize(width: width, height: layout.height)
        if coordinator.appliedSize != size || coordinator.appliedMode != wrapMode {
            coordinator.appliedSize = size
            coordinator.appliedMode = wrapMode
            textView.textContainer?.size = NSSize(width: layout.width, height: DiffPaneMetrics.unboundedExtent)
            textView.autoresizingMask = fits ? [.width] : []
            textView.setFrameSize(size)
            // Sideways scrolling only for lines wider than the pane; a card whose lines fit must not catch the
            // sideways swipes meant for the list around it, nor rubber-band on them.
            scrollView?.horizontalScrollElasticity = fits ? .none : .automatic
            textView.needsDisplay = true
            pane.needsLayout = true
        }
    }

    private func prepare(_ layout: StaticTextLayout, textWidth: CGFloat) {
        if side == .unified {
            layout.layOut(mode: wrapMode, viewportWidth: textWidth)
        } else {
            layouts.prepareSplit(width: textWidth, mode: wrapMode)
        }
    }

    package func sizeThatFits(_ proposal: ProposedViewSize, nsView pane: DiffPaneView, context: Context) -> CGSize? {
        guard let layout, width > 0 else { return CGSize(width: 200, height: 0) }
        prepare(layout, textWidth: max(width - pane.gutterView.thickness, 1))
        return CGSize(width: proposal.width ?? width, height: layout.height)
    }

    @MainActor
    package final class Coordinator {
        package weak var textView: NSTextView?
        package private(set) var layout: StaticTextLayout?
        package var appliedSize: NSSize?
        package var appliedMode: WrapMode?

        /// Moves the text view's layout manager onto the layout's content storage, leaving whichever storage it
        /// was on, so the view shows the measured text and its row spacing rather than a copy.
        package func attach(_ layout: StaticTextLayout) {
            guard let textView, let layoutManager = textView.textLayoutManager else { return }
            layoutManager.textContentManager?.removeTextLayoutManager(layoutManager)
            layout.contentStorage.addTextLayoutManager(layoutManager)
            layoutManager.delegate = layout.fragmentProvider
            textView.backgroundColor = layout.rendered.palette.background
            textView.selectedTextAttributes = [.backgroundColor: layout.rendered.palette.selection]
            self.layout = layout
            // Joining another storage does not invalidate what the view last drew; lay the viewport out afresh.
            layoutManager.textViewportLayoutController.layoutViewport()
            textView.needsLayout = true
            textView.needsDisplay = true
        }

        /// Leaves the shared storage, which would otherwise keep a dismantled pane's layout manager alive and
        /// invalidate it on every spacing change.
        package func detach() {
            guard let layoutManager = textView?.textLayoutManager else { return }
            layoutManager.textContentManager?.removeTextLayoutManager(layoutManager)
            layout = nil
        }
    }
}
