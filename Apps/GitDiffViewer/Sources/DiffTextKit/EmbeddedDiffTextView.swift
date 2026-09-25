package import AppKit
package import AtelierDiagnostics
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
    /// What the documentation panel is made of, from the window's setting.
    package var hoverPanelMaterial: HoverPanelMaterial = .liquidGlass
    /// Whether the pane rubber-bands past its edges sideways; otherwise it stops at them. It never scrolls down or
    /// up: the card list does, with its own bounce.
    package var bouncesAtEdges = false
    /// Diagnostics drawn over this pane's rows, the same as ``DiffTextView``'s: a squiggle in the text, and a tinted
    /// line number in the gutter.
    package var diagnosticOverlay: DiagnosticOverlay?
    /// Bumped by the caller whenever `diagnosticOverlay`'s content changes in place.
    package var diagnosticsVersion = 0
    /// Called with a row's findings and the clicked line number's frame, in the gutter's coordinates.
    package var onDiagnosticClick:
        ((_ rowIndex: Int, _ findings: [Finding], _ anchorRect: NSRect, _ in: NSView) -> Void)?
    /// Colours a tier after the lexer found for the text's sides, drawn over the lexer's (``refined(with:)``).
    package var refinedSides: RefinedSides?

    package init(
        layouts: CardLayouts, side: RenderedSide, gutter: GutterStyle, width: CGFloat, wrapMode: WrapMode = .viewport,
        onGapDrag: ((GapDragEvent) -> Void)? = nil,
        onDisplayed: (() -> Void)? = nil, hoverEnabled: Bool = false,
        hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)? = nil,
        hoverPanelMaterial: HoverPanelMaterial = .liquidGlass, bouncesAtEdges: Bool = false,
        diagnosticOverlay: DiagnosticOverlay? = nil, diagnosticsVersion: Int = 0,
        onDiagnosticClick: ((_ rowIndex: Int, _ findings: [Finding], _ anchorRect: NSRect, _ in: NSView) -> Void)? =
            nil
    ) {
        self.bouncesAtEdges = bouncesAtEdges
        self.layouts = layouts
        self.side = side
        self.gutter = gutter
        self.width = width
        self.wrapMode = wrapMode
        self.onGapDrag = onGapDrag
        self.onDisplayed = onDisplayed
        self.hoverEnabled = hoverEnabled
        self.hoverResolver = hoverResolver
        self.hoverPanelMaterial = hoverPanelMaterial
        self.diagnosticOverlay = diagnosticOverlay
        self.diagnosticsVersion = diagnosticsVersion
        self.onDiagnosticClick = onDiagnosticClick
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
        // Down and up, the card list scrolls and bounces; the pane scrolls only sideways, bouncing as `update` sets.
        scrollView.verticalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        // Each row where the card measured it, and laid out once: see ContiguousTextContainer and
        // RetainingTextLayoutManager. The layout manager joins a layout's storage in `attach`.
        let container = ContiguousTextContainer(size: NSSize(width: 0, height: DiffPaneMetrics.unboundedExtent))
        let layoutManager = RetainingTextLayoutManager()
        layoutManager.textContainer = container
        context.coordinator.emptyStorage.addTextLayoutManager(layoutManager)
        let textView = DiffPaneTextView(frame: .zero, textContainer: container)
        textView.placesContainerAtInset = RetainingTextLayoutManager.retainsFragments
        // The card sizes the text view: see `size`.
        textView.sizesToFitText = false
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
        gutterView.overlay = context.coordinator.diagnostics.overlay
        let minimapView = MinimapView()
        minimapView.isHidden = true
        let pane = DiffPaneView(
            gutterView: gutterView, scrollView: nil, contentView: scrollView, minimapView: minimapView)
        context.coordinator.textView = textView
        context.coordinator.gutterView = gutterView
        if let layoutManager = textView.textLayoutManager {
            context.coordinator.refinedColors.install(on: layoutManager)
        }
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
        pane.gutterView.onDiagnosticClick = onDiagnosticClick
        let elasticity: NSScrollView.Elasticity = bouncesAtEdges ? .automatic : .none
        if let scrollView = pane.contentView as? NSScrollView, scrollView.horizontalScrollElasticity != elasticity {
            scrollView.horizontalScrollElasticity = elasticity
        }
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
        coordinator.hoverController.panelMaterial = hoverPanelMaterial
        coordinator.updateDiagnostics(diagnosticOverlay, version: diagnosticsVersion)
        coordinator.refinedColors.update(rendered: layout.rendered, sides: refinedSides, view: textView)
    }

    /// Sizes the text view to the layout. Lines that fit take the clip view's width exactly and follow it: the width
    /// the card measured can differ from the clip by a point or two, and a text view wider by that much would scroll
    /// sideways by that much. Before the pane has a width the clip has none either, and the text view starts at none
    /// too, so that following the clip as it widens leaves it exactly as wide.
    private func size(
        _ textView: NSTextView, in pane: DiffPaneView, for layout: StaticTextLayout, textWidth: CGFloat,
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
        }
        textView.autoresizingMask = fits ? [.width] : []
        textView.setFrameSize(frameSize)
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
        package weak var gutterView: DiffGutterView?
        package private(set) var layout: StaticTextLayout?
        package var appliedSize: NSSize?
        package var appliedMode: WrapMode?
        package let hoverController = DocHoverController()
        /// The storage the text view shows until it shows a layout's.
        let emptyStorage = NSTextContentStorage()
        /// The colours drawn over the lexer's once a later tier lands (PERF-11).
        package let refinedColors = RefinedColors()
        /// The diagnostics this pane draws, which its gutter and every fragment its text view lays out hold.
        package let diagnostics = PaneDiagnosticsDisplay()

        /// Moves the text view's layout manager onto the layout's content storage, leaving whichever storage it
        /// was on, so the view shows the measured text and its row spacing rather than a copy.
        package func attach(_ layout: StaticTextLayout) {
            guard let textView, let layoutManager = textView.textLayoutManager else { return }
            layoutManager.textContentManager?.removeTextLayoutManager(layoutManager)
            // Before the view lays anything out, so each fragment it makes draws this pane's diagnostics.
            layout.fragmentProvider.overlay = diagnostics.overlay
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

        /// Shows `overlay`'s rows, `nil` showing none, and redraws the rows whose diagnostics changed; nothing is laid
        /// out again. A no-op unless the overlay or its version changed since the last call.
        package func updateDiagnostics(_ overlay: DiagnosticOverlay?, version: Int) {
            let changed = diagnostics.update(from: overlay, version: version)
            guard !changed.isEmpty else { return }
            gutterView?.redrawDiagnostics(ofRows: changed)
            guard let layout else { return }
            textView?.redrawDiagnostics(ofRows: changed, in: layout.rendered)
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

/// A layout manager that keeps every row it laid out, where TextKit's viewport would drop what it no longer shows.
///
/// After each viewport pass, TextKit discards the layout of the rows outside the viewport, by sending
/// `flushTextLayoutFragmentsFromLocation:direction:` to a layout manager that responds to it. A card's container makes
/// TextKit lay out from the top (``ContiguousTextContainer``), so each scroll step typeset again every row above what
/// shows, up to a second a step deep in a 20,000-row card (CardScrollBenchmark). Declining that message keeps the rows
/// laid out, as the card's own measuring layout keeps them, so a step only walks the rows above. It holds the layout of
/// every row down to the deepest one shown, which the card's measuring layout already holds when it wraps.
///
/// Nothing private is called: the class only says it does not respond. If TextKit stops asking under that name,
/// ``retainsFragments`` turns false, and cards place their container as AppKit does, which lays the text out again as
/// before (``DiffPaneTextView/placesContainerAtInset``).
final class RetainingTextLayoutManager: NSTextLayoutManager {
    private static let flush = NSSelectorFromString("flushTextLayoutFragmentsFromLocation:direction:")

    /// Whether TextKit flushes under the name this class declines, so that its layout managers keep what they laid out.
    static let retainsFragments = NSTextLayoutManager.instancesRespond(to: flush)

    override func responds(to selector: Selector!) -> Bool {
        selector == Self.flush ? false : super.responds(to: selector)
    }
}
