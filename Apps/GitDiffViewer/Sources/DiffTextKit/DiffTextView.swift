package import AppKit
package import AtelierDiagnostics
import DiffCore
package import DiffRendering
package import Foundation
package import SwiftUI

/// A read-only TextKit 2 pane showing one rendered side of a diff.
package struct DiffTextView: NSViewRepresentable {
    package let rendered: RenderedText
    package let gutter: GutterStyle
    package var keepsScrollPosition = false
    package var wrapsLines = true
    /// Characters per line when wrapping; zero wraps at the viewport width.
    package var wrapColumn = 0
    package var showsMinimap = true
    package var syncsScrolling = true
    package var scrollRequest: ScrollRequest?
    package var splitController: SplitPaneController?
    /// Reports a gap handle's drag in the gutter.
    package var onGapDrag: ((GapDragEvent) -> Void)?
    /// Called with the change whose gutter marker is clicked in the compact inline view (book DIFF-04).
    package var onChangeToggle: ((ChangeKey) -> Void)?
    /// Called once the pane shows a new render, its first included.
    package var onDisplayed: (() -> Void)?
    /// Shows documentation for the identifier under the pointer after it rests there.
    package var hoverEnabled = false
    package var hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)?
    /// What the documentation panel is made of, from the window's setting.
    package var hoverPanelMaterial: HoverPanelMaterial = .liquidGlass
    /// Diagnostics drawn over this pane's rows: a squiggle in the text, and a tinted line number in the gutter.
    package var diagnosticOverlay: DiagnosticOverlay?
    /// Bumped by the caller whenever `diagnosticOverlay`'s content changes in place (`replace(_:)`), since the
    /// overlay is a reference type the representable otherwise cannot see change.
    package var diagnosticsVersion = 0
    /// Called with a row's findings and the clicked line number's frame, in the gutter's coordinates.
    package var onDiagnosticClick:
        ((_ rowIndex: Int, _ findings: [Finding], _ anchorRect: NSRect, _ in: NSView) -> Void)?
    /// Where the pane records its scroll position as its file leaves it, and finds it again when the file comes back
    /// (book TAB-10); nil remembers nothing.
    package var scrollMemory: PaneScrollMemory?
    /// The left-side path of the file shown, under which ``scrollMemory`` keeps this pane's position.
    package var scrollMemoryPath: String?
    /// Whether the pane scrolls past the end of its text until the last line reaches the top; otherwise it stops with
    /// the last line at the bottom.
    package var scrollsPastEnd = false
    /// Whether the pane rubber-bands past its edges, down, up and sideways; otherwise it stops at them.
    package var bouncesAtEdges = false
    /// The height of bars laid over the pane's top that AppKit does not know of, the tab bar, a SwiftUI bar: the pane
    /// takes it as safe area of its own, so its text starts below the bar, scrolls beneath it, and the system's scroll
    /// edge effect covers it as it covers the toolbar (book TAB-09).
    package var underBars: CGFloat = 0
    /// What the stages after the text found for its sides, drawn over it as they land (``decorated(with:viewport:)``).
    package var decorations: DiffDecorations?
    /// Where the pane reports the rows it shows, so they are decorated first.
    package var viewport: DecorationViewport?

    package init(
        rendered: RenderedText, gutter: GutterStyle, keepsScrollPosition: Bool = false, wrapsLines: Bool = true,
        wrapColumn: Int = 0,
        showsMinimap: Bool = true, syncsScrolling: Bool = true, scrollRequest: ScrollRequest? = nil,
        splitController: SplitPaneController? = nil,
        onGapDrag: ((GapDragEvent) -> Void)? = nil, onChangeToggle: ((ChangeKey) -> Void)? = nil,
        onDisplayed: (() -> Void)? = nil, hoverEnabled: Bool = false,
        hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)? = nil,
        hoverPanelMaterial: HoverPanelMaterial = .liquidGlass,
        diagnosticOverlay: DiagnosticOverlay? = nil, diagnosticsVersion: Int = 0,
        onDiagnosticClick: ((_ rowIndex: Int, _ findings: [Finding], _ anchorRect: NSRect, _ in: NSView) -> Void)? =
            nil,
        scrollMemory: PaneScrollMemory? = nil, scrollMemoryPath: String? = nil,
        scrollsPastEnd: Bool = false, bouncesAtEdges: Bool = false, underBars: CGFloat = 0
    ) {
        self.bouncesAtEdges = bouncesAtEdges
        self.underBars = underBars
        self.scrollMemory = scrollMemory
        self.scrollMemoryPath = scrollMemoryPath
        self.scrollsPastEnd = scrollsPastEnd
        self.rendered = rendered
        self.gutter = gutter
        self.keepsScrollPosition = keepsScrollPosition
        self.wrapsLines = wrapsLines
        self.wrapColumn = wrapColumn
        self.showsMinimap = showsMinimap
        self.syncsScrolling = syncsScrolling
        self.scrollRequest = scrollRequest
        self.splitController = splitController
        self.onGapDrag = onGapDrag
        self.onChangeToggle = onChangeToggle
        self.onDisplayed = onDisplayed
        self.hoverEnabled = hoverEnabled
        self.hoverResolver = hoverResolver
        self.hoverPanelMaterial = hoverPanelMaterial
        self.diagnosticOverlay = diagnosticOverlay
        self.diagnosticsVersion = diagnosticsVersion
        self.onDiagnosticClick = onDiagnosticClick
    }

    package func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    package func makeNSView(context: Context) -> DiffPaneView {
        let scrollView = DiffPaneTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // The safe area, the toolbar's and the bars' above the pane, insets the text, and sizes the edge effect.
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.additionalSafeAreaInsets = Self.insets(underBars: underBars)
        Self.setElasticity(of: scrollView, bouncing: bouncesAtEdges)

        let textView = scrollView.documentView as? NSTextView ?? DiffPaneTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textLayoutManager?.delegate = context.coordinator.fragmentProvider
        context.coordinator.wrapColumn = wrapColumn
        context.coordinator.scrollsPastEnd = scrollsPastEnd
        Coordinator.configureWrapping(
            wrapsLines, column: wrapColumn, font: rendered.palette.font, textView: textView, scrollView: scrollView)

        let gutterView = DiffGutterView(clipView: scrollView.contentView)
        gutterView.source = textView
        gutterView.style = gutter
        gutterView.onGapDrag = onGapDrag
        gutterView.onChangeToggle = onChangeToggle
        gutterView.overlay = context.coordinator.diagnostics
        gutterView.onDiagnosticClick = onDiagnosticClick
        gutterView.decorations = context.coordinator.decorationStore.snapshot
        gutterView.decorationStore = context.coordinator.decorationStore
        context.coordinator.decorationStore.gutter = gutterView
        context.coordinator.scopeHover.attach(to: textView, gutter: gutterView)
        context.coordinator.updateDiagnostics(diagnosticOverlay, version: diagnosticsVersion)
        let minimapView = makeMinimap(following: scrollView, coordinator: context.coordinator)

        context.coordinator.textView = textView
        context.coordinator.followLayout()
        context.coordinator.gutterView = gutterView
        context.coordinator.minimapView = minimapView
        context.coordinator.splitController = splitController
        context.coordinator.wrapsLines = wrapsLines
        splitController?
            .register(scrollView, textView: textView) { [weak coordinator = context.coordinator] in
                coordinator?.rowsDidAlign()
            }
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.viewportDidResize(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clipViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
        context.coordinator.scrollMemory = scrollMemory
        context.coordinator.show(rendered, keepingScroll: false, key: memoryKey)
        if let layoutManager = textView.textLayoutManager {
            context.coordinator.decorationStore.install(on: layoutManager)
        }
        context.coordinator.decorationStore.update(rendered: rendered, decorations: decorations, view: textView)
        context.coordinator.report(to: viewport)
        // A new pane shows its first render here, and `updateNSView` only reports the renders that replace it.
        onDisplayed?()
        context.coordinator.hoverController.attach(to: textView) { [weak coordinator = context.coordinator] in
            coordinator?.rendered
        }
        return DiffPaneView(
            gutterView: gutterView, scrollView: scrollView, contentView: scrollView, minimapView: minimapView)
    }

    /// The pane's minimap: it shows the rows `scrollView` shows, redraws as it scrolls, and scrolls it to a row
    /// clicked, centred.
    private func makeMinimap(following scrollView: NSScrollView, coordinator: Coordinator) -> MinimapView {
        let minimapView = MinimapView()
        minimapView.scrollView = scrollView
        minimapView.isHidden = !showsMinimap
        minimapView.visibleRows = { [weak coordinator] in coordinator?.visibleRows() ?? 0 ..< 0 }
        minimapView.onSelectRow = { [weak coordinator, weak scrollView] row in
            guard let scrollView else { return }
            coordinator?.scroll(toRow: row, in: scrollView, centered: true)
        }
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            minimapView,
            selector: #selector(MinimapView.setNeedsDisplayOnScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        return minimapView
    }

    package func updateNSView(_ pane: DiffPaneView, context: Context) {
        let coordinator = context.coordinator
        guard let scrollView = pane.scrollView else { return }
        coordinator.metrics.width = max(scrollView.contentView.bounds.width, coordinator.textView?.frame.width ?? 0)
        if coordinator.wrapsLines != wrapsLines || coordinator.wrapColumn != wrapColumn,
            let textView = coordinator.textView
        {
            coordinator.wrapsLines = wrapsLines
            coordinator.wrapColumn = wrapColumn
            Coordinator.configureWrapping(
                wrapsLines, column: wrapColumn, font: rendered.palette.font, textView: textView, scrollView: scrollView)
            coordinator.updateOverscroll(in: scrollView.contentView)
            splitController?.wrapsLines = wrapsLines
        }
        Self.setElasticity(of: scrollView, bouncing: bouncesAtEdges)
        if scrollView.additionalSafeAreaInsets.top != underBars {
            scrollView.additionalSafeAreaInsets = Self.insets(underBars: underBars)
            coordinator.updateOverscroll(in: scrollView.contentView)
            // The minimap gives up what the bars cover.
            pane.needsLayout = true
        }
        if coordinator.scrollsPastEnd != scrollsPastEnd {
            coordinator.scrollsPastEnd = scrollsPastEnd
            coordinator.updateOverscroll(in: scrollView.contentView)
        }
        if pane.minimapView.isHidden == showsMinimap {
            pane.minimapView.isHidden = !showsMinimap
            pane.needsLayout = true
        }
        coordinator.gutterView?.onGapDrag = onGapDrag
        coordinator.gutterView?.onChangeToggle = onChangeToggle
        coordinator.gutterView?.onDiagnosticClick = onDiagnosticClick
        splitController?.syncsScrolling = syncsScrolling
        coordinator.hoverController.isEnabled = hoverEnabled
        coordinator.hoverController.resolve = hoverResolver
        coordinator.hoverController.panelMaterial = hoverPanelMaterial
        coordinator.updateDiagnostics(diagnosticOverlay, version: diagnosticsVersion)
        coordinator.scrollMemory = scrollMemory
        if coordinator.rendered?.id != rendered.id {
            coordinator.show(rendered, keepingScroll: keepsScrollPosition, key: memoryKey)
            onDisplayed?()
        }
        coordinator.decorationStore.update(rendered: rendered, decorations: decorations, view: coordinator.textView)
        coordinator.report(to: viewport)
        if let scrollRequest, coordinator.handledScrollRequest != scrollRequest.id {
            coordinator.handledScrollRequest = scrollRequest.id
            coordinator.scroll(toRow: scrollRequest.row, in: scrollView)
        }
    }

    package static func dismantleNSView(_ pane: DiffPaneView, coordinator: Coordinator) {
        coordinator.rememberPosition()
        if let textView = coordinator.textView { coordinator.splitController?.unregister(textView: textView) }
        coordinator.hoverController.detach()
        coordinator.scopeHover.detach()
        coordinator.report(to: nil)
        coordinator.usageObservation = nil
        NotificationCenter.default.removeObserver(coordinator)
    }

    /// The safe area a pane beneath bars `underBars` tall that AppKit does not know of takes on top of its own.
    static func insets(underBars: CGFloat) -> NSEdgeInsets {
        NSEdgeInsets(top: underBars, left: 0, bottom: 0, right: 0)
    }

    /// Lets `scrollView` rubber-band past its edges as AppKit does by default, or stops it at them, on both axes.
    static func setElasticity(of scrollView: NSScrollView, bouncing: Bool) {
        let elasticity: NSScrollView.Elasticity = bouncing ? .automatic : .none
        if scrollView.verticalScrollElasticity != elasticity { scrollView.verticalScrollElasticity = elasticity }
        if scrollView.horizontalScrollElasticity != elasticity { scrollView.horizontalScrollElasticity = elasticity }
    }

    /// The coordinator, declared at file scope to keep this type under `type_body_length`.
    package typealias Coordinator = DiffTextViewCoordinator

    /// This pane's place in ``scrollMemory``: its file, and which of the file's panes it is.
    var memoryKey: PaneScrollMemory.Key? {
        let pane: PaneScrollMemory.Pane =
            switch gutter {
                case .dual: .unified
                case .old: .old
                case .new: .new
            }
        return scrollMemoryPath.map { PaneScrollMemory.Key(path: $0, pane: pane) }
    }
}

@MainActor
package final class DiffTextViewCoordinator: NSObject {
    package let fragmentProvider = DiffFragmentProvider()
    package let hoverController = DocHoverController()
    /// The decorations drawn over the plain text as the stages after it land (PERF-09).
    package let decorationStore = DecorationStore()
    /// Outlines the scope of the row under the pointer in the text (DIFF-03).
    package let scopeHover = ScopeHoverTracker()
    /// Where the pane reports its visible rows, and the text it reported them for.
    private var reported: (viewport: DecorationViewport, textID: UUID)?
    package var metrics: ViewportMetrics { fragmentProvider.metrics }
    package weak var textView: NSTextView?
    package weak var gutterView: DiffGutterView?
    package weak var minimapView: MinimapView?
    package var splitController: SplitPaneController?
    package var wrapsLines = true
    package var wrapColumn = 0
    package private(set) var rendered: RenderedText?
    package var handledScrollRequest: UUID?
    /// Where this pane records and finds its scroll position; nil remembers nothing.
    package var scrollMemory: PaneScrollMemory?
    /// The key the text on show is remembered under.
    var memoryKey: PaneScrollMemory.Key?
    /// The diagnostics this pane draws, which every fragment and the gutter hold.
    package let diagnosticsDisplay = PaneDiagnosticsDisplay()
    package var diagnostics: DiagnosticOverlay { diagnosticsDisplay.overlay }
    /// ``RenderedText/measuredUnwrappedWidth()`` of the text on show, measured once per render.
    private var unwrappedWidth: (id: UUID, width: CGFloat)?
    /// Sizes the pane again whenever TextKit's usage bounds change; see ``followLayout()``.
    fileprivate var usageObservation: NSKeyValueObservation?
    /// Whether the pane is being sized for a change of TextKit's usage bounds; see ``followLayout()``.
    private var isFollowingUsage = false
    /// Whether the pane scrolls past the end of its text until the last line reaches the top; otherwise it stops with
    /// the last line at the bottom. See ``updateOverscroll(in:)``.
    package var scrollsPastEnd = false
    /// The row asked for, or the position a file comes back to, placed at the end of the text view's next layout pass.
    var pendingScroll: RowPlacement?
    /// The row placed last, and where the pane was scrolled for it, placed again when the split view aligns the rows or
    /// the pane takes a new size, unless it has been scrolled since; see ``placeAgainUnlessScrolled()``.
    var placedRow: (placement: RowPlacement, y: CGFloat)?

    package override init() {
        super.init()
        fragmentProvider.overlay = diagnostics
        fragmentProvider.decorations = decorationStore.snapshot
    }

    /// Reports the rows the pane shows to `viewport`, read when asked, for the text on show; nil stops reporting.
    package func report(to viewport: DecorationViewport?) {
        let textID = rendered?.id
        guard reported?.viewport !== viewport || reported?.textID != textID else { return }
        if let reported { reported.viewport.unregister(reported.textID) }
        reported = nil
        guard let viewport, let textID else { return }
        viewport.register(textID) { [weak self] in
            guard let self, self.textView?.window != nil else { return nil }
            let rows = self.visibleRows()
            return rows.isEmpty ? nil : rows
        }
        reported = (viewport, textID)
    }

    /// Shows `overlay`'s rows, `nil` showing none, and redraws the rows whose diagnostics changed; nothing is laid out
    /// again. A no-op unless the overlay or its version changed since the last call.
    /// - Complexity: O(rows with diagnostics), plus ``NSTextView/redrawDiagnostics(ofRows:in:)``.
    package func updateDiagnostics(_ overlay: DiagnosticOverlay?, version: Int) {
        let changed = diagnosticsDisplay.update(from: overlay, version: version)
        guard !changed.isEmpty else { return }
        gutterView?.redrawDiagnostics(ofRows: changed)
        guard let rendered else { return }
        textView?.redrawDiagnostics(ofRows: changed, in: rendered)
    }

    package func apply(_ rendered: RenderedText, keepingScroll: Bool = false) {
        let paletteChanged = self.rendered?.palette.font != rendered.palette.font
        self.rendered = rendered
        fragmentProvider.rendered = rendered
        hoverController.invalidate()
        // A row asked for belongs to the text it was asked for; a new text starts at its top, or where it was.
        pendingScroll = nil
        placedRow = nil
        guard let textView, let contentStorage = textView.textContentStorage else { return }
        let previousOrigin = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
        textView.backgroundColor = rendered.palette.background
        // The band of a gap at the top of the file sits above the text, in place of the pane's own inset, so its
        // handle sticks to the pane's top edge.
        let inset = max(DiffPaneMetrics.containerInset, rendered.bandAbove)
        if textView.textContainerInset.height != inset { textView.textContainerInset = NSSize(width: 0, height: inset) }
        textView.insertionPointColor = rendered.palette.textColor
        textView.selectedTextAttributes = [.backgroundColor: rendered.palette.selection]
        contentStorage.performEditingTransaction {
            guard let storage = contentStorage.textStorage else { return }
            // TextKit replaces a large text in place in time quadratic in its length; emptying the storage first, in
            // the same transaction, avoids that (PaneStorageReplacementBenchmark).
            if storage.length > 0 { storage.setAttributedString(NSAttributedString()) }
            storage.setAttributedString(rendered.attributed)
            rendered.padEmptyLastRow(in: storage)
        }
        if paletteChanged, let scrollView = textView.enclosingScrollView {
            Self.configureWrapping(
                wrapsLines, column: wrapColumn, font: rendered.palette.font, textView: textView,
                scrollView: scrollView)
        }
        gutterView?.rendered = rendered
        minimapView?.rendered = rendered
        gutterView?.superview?.needsLayout = true
        if let scrollView = textView.enclosingScrollView {
            updateOverscroll(in: scrollView.contentView)
            let top = NSPoint(x: 0, y: -scrollView.contentView.contentInsets.top)
            scroll(scrollView.contentView, to: keepingScroll ? previousOrigin : top)
            splitController?.update(rendered, for: textView)
        }
        // Replacing the whole storage in one transaction does not always redraw the visible viewport until it
        // scrolls; lay it out and mark the pane for display explicitly.
        textView.textLayoutManager?.textViewportLayoutController.layoutViewport()
        textView.needsLayout = true
        textView.needsDisplay = true
        gutterView?.needsDisplay = true
        minimapView?.needsDisplay = true
    }

    /// Wrapped panes track the viewport width, or wrap at a fixed column and scroll sideways when the viewport is
    /// narrower; unwrapped panes track a text view that ``updateOverscroll(in:)`` sizes to the longest line.
    package static func configureWrapping(
        _ wraps: Bool, column: Int, font: NSFont, textView: NSTextView, scrollView: NSScrollView
    ) {
        guard let container = textView.textContainer else { return }
        guard wraps else {
            // A container that tracks the view lets TextKit lay out the viewport only; a fixed one makes every frame
            // change lay out the whole document.
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = []
            container.widthTracksTextView = true
            scrollView.hasHorizontalScroller = true
            if let layoutManager = textView.textLayoutManager {
                layoutManager.invalidateLayout(for: layoutManager.documentRange)
            }
            textView.needsLayout = true
            textView.needsDisplay = true
            return
        }
        let tracksViewport = column <= 0
        textView.isHorizontallyResizable = !tracksViewport
        textView.autoresizingMask = tracksViewport ? [.width] : []
        container.widthTracksTextView = tracksViewport
        let width =
            if column > 0 {
                DiffPalette.wrapWidth(column: column, font: font, padding: container.lineFragmentPadding)
            } else {
                scrollView.contentView.bounds.width
            }
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        scrollView.hasHorizontalScroller = !tracksViewport
        if tracksViewport {
            textView.setFrameSize(NSSize(width: scrollView.contentView.bounds.width, height: textView.frame.height))
        }
        if let layoutManager = textView.textLayoutManager {
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
        }
        textView.sizeToFit()
        textView.needsLayout = true
        textView.needsDisplay = true
    }

    /// Rows intersecting the clip view, from the laid-out fragments at its top and bottom edges.
    package func visibleRows() -> Range<Int> {
        guard let textView, let rendered, !rendered.rows.isEmpty,
            let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager,
            let clipView = textView.enclosingScrollView?.contentView
        else { return 0 ..< 0 }
        let inset = textView.textContainerInset.height
        let lastRow = rendered.rows.count - 1
        let contentBottom = layoutManager.usageBoundsForTextContainer.maxY + inset
        /// Points below the document, in the overscroll space, belong to the last row.
        func row(at y: CGFloat) -> Int {
            guard y < contentBottom,
                let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: y - inset))
            else { return y >= contentBottom ? lastRow : 0 }
            return rendered.rowIndex(
                containing: contentManager.offset(
                    from: layoutManager.documentRange.location, to: fragment.rangeInElement.location))
        }
        // TextKit 2 lays out lazily: a fragment the viewport reaches may not exist yet, and a row lookup that
        // fails answers 0, which put the bottom edge above the top edge and trapped on the range.
        layoutManager.ensureLayout(
            for: CGRect(
                x: 0, y: clipView.bounds.minY - inset, width: clipView.bounds.width, height: clipView.bounds.height)
        )
        // What the bars above the pane cover does not show.
        let first = min(row(at: max(clipView.bounds.minY + clipView.contentInsets.top, 0)), lastRow)
        let last = min(max(row(at: clipView.bounds.maxY), first), lastRow)
        return first ..< (last + 1)
    }

    /// Follows TextKit's layout of the text view: sizes the pane each time TextKit's usage bounds change, as the layout
    /// manager's documentation asks of a view sized by them, and at the end of each layout pass, since TextKit lays out
    /// some of the text, the last row among it, without a change of its bounds to tell; and places a row asked for.
    ///
    /// ``updateOverscroll(in:)`` reads what TextKit laid out, and on a new pane it had laid out nothing each time that
    /// ran before this: when the text was applied, and when the clip view took its size, whose new width drops what
    /// TextKit had laid out. Only a resize of the text view or of its clip view sized the pane again, and TextKit
    /// resizes the text view only past the size the pane had: a pane could keep a size that its text had long outgrown.
    ///
    /// Sizing the pane reads TextKit's layout, which first carries out the invalidations TextKit has pending, and each
    /// fragment one of them drops changes the usage bounds again, within the read: a change that comes while the pane
    /// is being sized is left to that sizing, which reads the layout they leave. Sizing the pane for each of them in
    /// turn nested one call per fragment dropped, and a text laid out over some 1,800 rows, replaced, overflowed the
    /// stack.
    ///
    /// During an edit of the text, TextKit tells of a change of its usage bounds from within its invalidation of the
    /// edited range, as it drops that range's fragments one by one. Reading the layout there invalidates the range
    /// again, under the invalidation still going through its fragments, and that one then never ends: the row spacing
    /// that lines up side-by-side rows wrapped onto different numbers of lines froze the window so. A change that
    /// comes during an edit leaves the pane to be sized at the end of the next layout pass, once the edit is over.
    package func followLayout() {
        usageObservation = textView?.textLayoutManager?
            .observe(\.usageBoundsForTextContainer) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isFollowingUsage, let textView = self.textView,
                        let clipView = textView.enclosingScrollView?.contentView
                    else { return }
                    if textView.textLayoutManager?.textContentManager?.hasEditingTransaction == true {
                        textView.needsLayout = true
                        return
                    }
                    self.isFollowingUsage = true
                    defer { self.isFollowingUsage = false }
                    self.updateOverscroll(in: clipView)
                }
            }
        (textView as? DiffPaneTextView)?.onLayout = { [weak self] in self?.layoutDidEnd() }
    }

    @objc package func viewportDidResize(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView else { return }
        metrics.width = max(clipView.bounds.width, textView?.frame.width ?? 0)
        updateOverscroll(in: clipView)
        if pendingScroll != nil { textView?.needsLayout = true } else { placeAgainUnlessScrolled() }
        splitController?.scheduleAlignment()
    }

    /// Sizes the text view to its content and to how far the pane scrolls past it: by default to the last line at the
    /// bottom, the band of a gap at the end of the file and the pane's inset under it, a text shorter than the pane
    /// filling it; with ``scrollsPastEnd``, on until the last line reaches the top. The space is part of the view, not
    /// a scroll inset, so nothing else has to account for it.
    ///
    /// The text view's frame is also TextKit's to set, to the height it has laid out, which leaves out the space past
    /// the end and, early on, most of the text: every call sets the frame again, whether or not the size it computes
    /// changed.
    package func updateOverscroll(in clipView: NSClipView) {
        guard let textView else { return }
        // What shows of the pane: less what the bars above it cover, which the text starts below.
        let shown = clipView.bounds.height - clipView.contentInsets.top
        let height: CGFloat
        if scrollsPastEnd {
            // The row's own height, not the font's: a taller line height would otherwise leave the last row short of
            // the top of the pane, half of it hidden under whatever sits above. Less what lies below the text, which
            // the last line would otherwise scroll past the top by.
            let lineHeight = rendered?.lineHeight ?? DiffPalette.system.defaultLineHeight
            let below = (rendered?.bandBelow ?? 0) + DiffPaneMetrics.containerInset
            height = contentHeight() + max(shown - lineHeight - below, 0)
        } else {
            height = max(contentHeight(), shown)
        }
        let width: CGFloat =
            if !wrapsLines, let rendered {
                // One line per row: the width needs no layout.
                max(clipView.bounds.width, unwrappedWidth(of: rendered))
            } else if textView.textContainer?.widthTracksTextView == true {
                textView.frame.width
            } else if wrapColumn > 0 {
                max(clipView.bounds.width, textView.textContainer?.size.width ?? 0)
            } else {
                max(clipView.bounds.width, (rendered?.unwrappedWidth ?? 0).rounded(.up))
            }
        let size = NSSize(width: width, height: height.rounded(.up))
        guard textView.minSize != size || textView.frame.size != size else { return }
        textView.minSize = size
        textView.setFrameSize(size)
    }

    /// The text's height, with the pane's inset and any band of a gap at the top of the file above it, and any band at
    /// its end and the pane's inset below it.
    ///
    /// Once TextKit has laid out the last row, the text ends where it placed it. Until then its usage bounds end with
    /// what it did lay out, or hold nothing, as when a text was just applied: a pane sized from them ended above its
    /// text, which was cut off and could not be scrolled to. The rows at one line each are the floor until then: every
    /// row takes a line at least, wrapped or not. Past the rows, the text ends where TextKit places its last row, after
    /// its estimates of the rows above it that it has not laid out (book CARD-17), which the rows' height may not
    /// match: the pane ends with that row wherever it lies, with no room left below it and none missing.
    package func contentHeight() -> CGFloat {
        guard let textView, let layoutManager = textView.textLayoutManager else { return 0 }
        let below = (rendered?.bandBelow ?? 0) + DiffPaneMetrics.containerInset
        let text =
            if let last = lastFragment(in: layoutManager), last.state == .layoutAvailable {
                last.layoutFragmentFrame.maxY
            } else {
                max(layoutManager.usageBoundsForTextContainer.maxY, rendered?.unwrappedTextHeight ?? 0)
            }
        return textView.textContainerInset.height + text + below
    }

    /// The layout fragment of the last row, laid out or not.
    private func lastFragment(in layoutManager: NSTextLayoutManager) -> NSTextLayoutFragment? {
        var last: NSTextLayoutFragment?
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.endLocation, options: [.reverse]) {
            last = $0
            return false
        }
        return last
    }

    private func unwrappedWidth(of rendered: RenderedText) -> CGFloat {
        if let unwrappedWidth, unwrappedWidth.id == rendered.id { return unwrappedWidth.width }
        let width = rendered.measuredUnwrappedWidth()
        unwrappedWidth = (rendered.id, width)
        return width
    }

    @objc package func textViewFrameDidChange(_ notification: Notification) {
        guard let textView, let clipView = textView.enclosingScrollView?.contentView else { return }
        metrics.width = max(clipView.bounds.width, textView.frame.width)
        updateOverscroll(in: clipView)
    }
}
