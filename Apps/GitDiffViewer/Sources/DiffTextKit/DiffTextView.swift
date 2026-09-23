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
    /// Called once the pane shows a new render.
    package var onDisplayed: (() -> Void)?
    /// Shows documentation for the identifier under the pointer after it rests there.
    package var hoverEnabled = false
    package var hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)?
    /// Diagnostics drawn over this pane's rows: a squiggle in the text, and a tinted line number in the gutter.
    package var diagnosticOverlay: DiagnosticOverlay?
    /// Bumped by the caller whenever `diagnosticOverlay`'s content changes in place (`replace(_:)`), since the
    /// overlay is a reference type the representable otherwise cannot see change.
    package var diagnosticsVersion = 0
    /// Called with a row's findings and the clicked line number's frame, in the gutter's coordinates.
    package var onDiagnosticClick:
        ((_ rowIndex: Int, _ findings: [Finding], _ anchorRect: NSRect, _ in: NSView) -> Void)?

    package init(
        rendered: RenderedText, gutter: GutterStyle, keepsScrollPosition: Bool = false, wrapsLines: Bool = true,
        wrapColumn: Int = 0,
        showsMinimap: Bool = true, syncsScrolling: Bool = true, scrollRequest: ScrollRequest? = nil,
        splitController: SplitPaneController? = nil,
        onGapDrag: ((GapDragEvent) -> Void)? = nil,
        onDisplayed: (() -> Void)? = nil, hoverEnabled: Bool = false,
        hoverResolver: (@Sendable (HoverHit) async -> HoverDocument?)? = nil,
        diagnosticOverlay: DiagnosticOverlay? = nil, diagnosticsVersion: Int = 0,
        onDiagnosticClick: ((_ rowIndex: Int, _ findings: [Finding], _ anchorRect: NSRect, _ in: NSView) -> Void)? = nil
    ) {
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
        self.onDisplayed = onDisplayed
        self.hoverEnabled = hoverEnabled
        self.hoverResolver = hoverResolver
        self.diagnosticOverlay = diagnosticOverlay
        self.diagnosticsVersion = diagnosticsVersion
        self.onDiagnosticClick = onDiagnosticClick
    }

    package func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    package func makeNSView(context: Context) -> DiffPaneView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = scrollView.documentView as? NSTextView ?? NSTextView(usingTextLayoutManager: true)
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
        Coordinator.configureWrapping(
            wrapsLines, column: wrapColumn, font: rendered.palette.font, textView: textView, scrollView: scrollView)

        let gutterView = DiffGutterView(clipView: scrollView.contentView)
        gutterView.source = textView
        gutterView.style = gutter
        gutterView.onGapDrag = onGapDrag
        gutterView.overlay = diagnosticOverlay
        gutterView.onDiagnosticClick = onDiagnosticClick
        context.coordinator.fragmentProvider.overlay = diagnosticOverlay
        context.coordinator.diagnosticsVersion = diagnosticsVersion
        let minimapView = MinimapView()
        minimapView.scrollView = scrollView
        minimapView.isHidden = !showsMinimap
        minimapView.visibleRows = { [weak coordinator = context.coordinator] in coordinator?.visibleRows() ?? 0 ..< 0 }
        minimapView.onSelectRow = { [weak coordinator = context.coordinator, weak scrollView] row in
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

        context.coordinator.textView = textView
        context.coordinator.gutterView = gutterView
        context.coordinator.minimapView = minimapView
        context.coordinator.splitController = splitController
        context.coordinator.wrapsLines = wrapsLines
        splitController?.register(scrollView, textView: textView)
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.viewportDidResize(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
        context.coordinator.apply(rendered)
        context.coordinator.hoverController.attach(to: textView) { [weak coordinator = context.coordinator] in
            coordinator?.rendered
        }
        return DiffPaneView(
            gutterView: gutterView, scrollView: scrollView, contentView: scrollView, minimapView: minimapView)
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
        if pane.minimapView.isHidden == showsMinimap {
            pane.minimapView.isHidden = !showsMinimap
            pane.needsLayout = true
        }
        coordinator.gutterView?.onGapDrag = onGapDrag
        coordinator.gutterView?.onDiagnosticClick = onDiagnosticClick
        splitController?.syncsScrolling = syncsScrolling
        coordinator.hoverController.isEnabled = hoverEnabled
        coordinator.hoverController.resolve = hoverResolver
        if coordinator.fragmentProvider.overlay !== diagnosticOverlay
            || coordinator.diagnosticsVersion != diagnosticsVersion
        {
            coordinator.fragmentProvider.overlay = diagnosticOverlay
            coordinator.gutterView?.overlay = diagnosticOverlay
            coordinator.diagnosticsVersion = diagnosticsVersion
            // Laid-out fragments cache what they drew, so a diagnostics change must invalidate them.
            if let textView = coordinator.textView, let layoutManager = textView.textLayoutManager {
                layoutManager.invalidateLayout(for: layoutManager.documentRange)
                textView.needsLayout = true
            }
            coordinator.textView?.needsDisplay = true
            coordinator.gutterView?.needsDisplay = true
        }
        if coordinator.rendered?.id != rendered.id {
            coordinator.apply(rendered, keepingScroll: keepsScrollPosition)
            onDisplayed?()
        }
        if let scrollRequest, coordinator.handledScrollRequest != scrollRequest.id {
            coordinator.handledScrollRequest = scrollRequest.id
            coordinator.scroll(toRow: scrollRequest.row, in: scrollView)
        }
    }

    package static func dismantleNSView(_ pane: DiffPaneView, coordinator: Coordinator) {
        if let textView = coordinator.textView { coordinator.splitController?.unregister(textView: textView) }
        coordinator.hoverController.detach()
        NotificationCenter.default.removeObserver(coordinator)
    }

    /// The coordinator, declared at file scope to keep this type under `type_body_length`.
    package typealias Coordinator = DiffTextViewCoordinator
}

@MainActor
package final class DiffTextViewCoordinator: NSObject {
    package let fragmentProvider = DiffFragmentProvider()
    package let hoverController = DocHoverController()
    package var metrics: ViewportMetrics { fragmentProvider.metrics }
    package weak var textView: NSTextView?
    package weak var gutterView: DiffGutterView?
    package weak var minimapView: MinimapView?
    package var splitController: SplitPaneController?
    package var wrapsLines = true
    package var wrapColumn = 0
    package private(set) var rendered: RenderedText?
    package var handledScrollRequest: UUID?
    /// The last `diagnosticsVersion` applied, so `updateNSView` can tell an in-place overlay mutation from a
    /// no-op re-render.
    package var diagnosticsVersion = -1
    /// ``RenderedText/measuredUnwrappedWidth()`` of the text on show, measured once per render.
    private var unwrappedWidth: (id: UUID, width: CGFloat)?

    package func apply(_ rendered: RenderedText, keepingScroll: Bool = false) {
        let paletteChanged = self.rendered?.palette.font != rendered.palette.font
        self.rendered = rendered
        fragmentProvider.rendered = rendered
        hoverController.invalidate()
        guard let textView, let contentStorage = textView.textContentStorage else { return }
        let previousOrigin = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
        textView.backgroundColor = rendered.palette.background
        // The band of a gap at the top of the file sits above the text, inside the pane's own inset.
        let inset = DiffPaneMetrics.containerInset + rendered.bandAbove
        if textView.textContainerInset.height != inset { textView.textContainerInset = NSSize(width: 0, height: inset) }
        textView.insertionPointColor = rendered.palette.textColor
        textView.selectedTextAttributes = [.backgroundColor: rendered.palette.selection]
        contentStorage.performEditingTransaction {
            guard let storage = contentStorage.textStorage else { return }
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
            scrollView.contentView.scroll(to: keepingScroll ? previousOrigin : .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
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

    package func scroll(toRow row: Int, in scrollView: NSScrollView, centered: Bool = false) {
        guard let textView, let rendered, row < rendered.lineStarts.count,
            let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager,
            let location = contentManager.location(
                layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row])
        else { return }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return }
        let frame = fragment.layoutFragmentFrame
        let margin = centered ? scrollView.contentView.bounds.height / 2 : 3 * frame.height
        let target = max(0, frame.minY + textView.textContainerInset.height - margin)
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: target))
        scrollView.reflectScrolledClipView(scrollView.contentView)
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
        let first = min(row(at: max(clipView.bounds.minY, 0)), lastRow)
        let last = min(max(row(at: clipView.bounds.maxY), first), lastRow)
        return first ..< (last + 1)
    }

    @objc package func viewportDidResize(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView else { return }
        metrics.width = max(clipView.bounds.width, textView?.frame.width ?? 0)
        updateOverscroll(in: clipView)
        updateHorizontalScrolling(in: clipView)
        splitController?.scheduleAlignment()
    }

    /// A pane scrolls sideways only while one of its own lines runs past its viewport. Otherwise a sideways
    /// swipe would only rubber-band, and in a split the narrower side would bounce while the wider one scrolls.
    package func updateHorizontalScrolling(in clipView: NSClipView) {
        guard let textView, let scrollView = textView.enclosingScrollView else { return }
        let scrollsSideways = textView.frame.width > clipView.bounds.width + 0.5
        scrollView.horizontalScrollElasticity = scrollsSideways ? .automatic : .none
    }

    /// Lets the last line scroll up to the top of the pane, and no further, by giving the text view trailing space
    /// below its content: scrolled to its end, the pane shows its last line whole at its top, and the band of a gap
    /// at the end of the file under it. The space is part of the view, not a scroll inset, so nothing else has to
    /// account for it.
    package func updateOverscroll(in clipView: NSClipView) {
        guard let textView, let layoutManager = textView.textLayoutManager else { return }
        // The row's own height, not the font's: a taller line height would otherwise leave the last row short
        // of the top of the pane, half of it hidden under whatever sits above.
        let lineHeight = rendered?.lineHeight ?? DiffPalette.system.defaultLineHeight
        // Above the text, the pane's inset and any band of a gap at the top of the file; below it, any band at the
        // end, then the pane's inset.
        let inset = textView.textContainerInset.height
        let below = (rendered?.bandBelow ?? 0) + DiffPaneMetrics.containerInset
        // Less what lies below the text, which the last line would otherwise scroll past the top by.
        let overscroll = max(clipView.bounds.height - lineHeight - below, 0)
        if !wrapsLines, let rendered {
            // One line per row: the document's size needs no layout.
            let contentHeight = inset + rendered.unwrappedTextHeight + below
            let size = NSSize(
                width: max(clipView.bounds.width, unwrappedWidth(of: rendered)),
                height: (contentHeight + overscroll).rounded(.up))
            guard textView.minSize != size || textView.frame.size != size else { return }
            textView.minSize = size
            textView.setFrameSize(size)
            return
        }
        let contentHeight = inset + layoutManager.usageBoundsForTextContainer.height + below
        let minimumHeight = (contentHeight + overscroll).rounded(.up)
        let minimumWidth: CGFloat =
            if textView.textContainer?.widthTracksTextView == true {
                0
            } else if wrapColumn > 0, wrapsLines {
                max(clipView.bounds.width, textView.textContainer?.size.width ?? 0)
            } else {
                max(clipView.bounds.width, (rendered?.unwrappedWidth ?? 0).rounded(.up))
            }
        let minimum = NSSize(width: minimumWidth, height: minimumHeight)
        guard textView.minSize != minimum else { return }
        textView.minSize = minimum
        textView.sizeToFit()
        if textView.frame.height < minimumHeight {
            textView.setFrameSize(NSSize(width: max(textView.frame.width, minimumWidth), height: minimumHeight))
        }
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
        updateHorizontalScrolling(in: clipView)
    }
}
