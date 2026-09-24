package import AppKit
import DiffCore
package import DiffRendering
package import Foundation
package import SwiftUI

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
    package var onGapDrag: ((GapDragEvent) -> Void)?
    /// Called once the pane shows a new render.
    package var onDisplayed: (() -> Void)?
    /// Shows documentation for the identifier under the pointer after it rests there, the same as ``DiffTextView``.
    package var hoverEnabled = false
    package var hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)?

    package init(
        layouts: CardLayouts, side: RenderedSide, gutter: GutterStyle, width: CGFloat, wrapMode: WrapMode = .viewport,
        onGapDrag: ((GapDragEvent) -> Void)? = nil,
        onDisplayed: (() -> Void)? = nil, hoverEnabled: Bool = false,
        hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)? = nil
    ) {
        self.layouts = layouts
        self.side = side
        self.gutter = gutter
        self.width = width
        self.wrapMode = wrapMode
        self.onGapDrag = onGapDrag
        self.onDisplayed = onDisplayed
        self.hoverEnabled = hoverEnabled
        self.hoverResolver = hoverResolver
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

        let textView = DiffPaneTextView(usingTextLayoutManager: true)
        // Each row where the card measured it: see ContiguousTextContainer.
        if let container = textView.textContainer {
            textView.replaceTextContainer(ContiguousTextContainer(size: container.size))
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 0, height: StaticTextLayout.verticalInset)
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
        let pane = DiffPaneView(
            gutterView: gutterView, scrollView: nil, contentView: scrollView, minimapView: minimapView)
        context.coordinator.textView = textView
        context.coordinator.hoverController.attach(to: textView) { [weak coordinator = context.coordinator] in
            coordinator?.layout?.rendered
        }
        update(pane, context: context)
        return pane
    }

    package func updateNSView(_ pane: DiffPaneView, context: Context) {
        update(pane, context: context)
    }

    package static func dismantleNSView(_ pane: DiffPaneView, coordinator: Coordinator) {
        coordinator.hoverController.detach()
        coordinator.detach()
    }

    /// Prepares the detached layout for the pane width, sizes the text view, then shows the layout in it: sized
    /// first, the text view never lays the text out for a stale frame.
    private func update(_ pane: DiffPaneView, context: Context) {
        pane.gutterView.onGapDrag = onGapDrag
        guard let layout, let textView = context.coordinator.textView, width > 0 else { return }
        let coordinator = context.coordinator
        let isNewLayout = coordinator.layout !== layout
        // The gutter's width follows the widest line number, which the text width depends on.
        if isNewLayout { pane.gutterView.rendered = layout.rendered }
        let textWidth = max(width - pane.gutterView.thickness, 1)
        prepare(layout, textWidth: textWidth)
        size(textView, in: pane, for: layout, textWidth: textWidth, coordinator: coordinator)
        if isNewLayout {
            coordinator.attach(layout)
            onDisplayed?()
        }
        coordinator.hoverController.isEnabled = hoverEnabled
        coordinator.hoverController.resolve = hoverResolver
    }

    /// Sizes the text view to the layout. Lines that fit take the clip view's width exactly and follow it: the width
    /// the card measured can differ from the clip by a point or two, and a text view wider by that much would scroll
    /// sideways by that much.
    private func size(
        _ textView: NSTextView, in pane: DiffPaneView, for layout: StaticTextLayout, textWidth: CGFloat,
        coordinator: Coordinator
    ) {
        let scrollView = pane.contentView as? NSScrollView
        let fits = layout.contentWidth <= textWidth + 0.5
        let viewWidth = fits ? max(scrollView?.contentView.bounds.width ?? textWidth, 1) : layout.contentWidth
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
        }
        textView.autoresizingMask = fits ? [.width] : []
        textView.setFrameSize(frameSize)
        // Sideways scrolling only for lines wider than the pane; a card whose lines fit must not catch the sideways
        // swipes meant for the list around it, nor rubber-band on them.
        scrollView?.horizontalScrollElasticity = fits ? .none : .automatic
        textView.needsDisplay = true
        pane.needsLayout = true
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
        package let hoverController = DocHoverController()

        /// Moves the text view's layout manager onto the layout's content storage, leaving whichever storage it
        /// was on, so the view shows the measured text and its row spacing rather than a copy.
        package func attach(_ layout: StaticTextLayout) {
            guard let textView, let layoutManager = textView.textLayoutManager else { return }
            layoutManager.textContentManager?.removeTextLayoutManager(layoutManager)
            layout.contentStorage.addTextLayoutManager(layoutManager)
            layoutManager.delegate = layout.fragmentProvider
            // The layout's space above its first row, the band of a gap at the top of the file among it.
            textView.textContainerInset = NSSize(width: 0, height: layout.inset)
            textView.backgroundColor = layout.rendered.palette.background
            textView.selectedTextAttributes = [.backgroundColor: layout.rendered.palette.selection]
            self.layout = layout
            // A hover over the old content points at nothing once the storage changes.
            hoverController.invalidate()
            // Joining another storage does not invalidate what the view last drew, so the viewport is laid out
            // afresh; off-window only by the coming layout pass, since a viewport there spans the whole document.
            if textView.window != nil { layoutManager.textViewportLayoutController.layoutViewport() }
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

/// A text container TextKit lays out from its top, so a card's text view places every row it shows after the rows
/// above it, where the card measured them (book DIFF-06, CARD-17).
///
/// TextKit 2 otherwise lays out only what shows and places it after estimates of the rows above that it has not laid
/// out, which take a line nearly as wide as the container for two. A card that never wraps measures its rows without
/// laying them out, and a new text, from a reveal or a reload, drops the text view's layout: the rows it then showed
/// sat away from where the card measured them, its gutter drew their numbers and separators elsewhere, and its last
/// rows fell past its end. A container that is not a simple rectangle turns that estimated layout off
/// (`NSTextLayoutManager.textContainer`). A card that wraps is laid out whole either way.
private final class ContiguousTextContainer: NSTextContainer {
    override var isSimpleRectangularTextContainer: Bool { false }
}
