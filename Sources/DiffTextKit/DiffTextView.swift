package import AppKit
package import DiffCore
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
    package var onGapDrag: ((GapMarker, GapExpansion, Int) -> Void)?
    package var currentExpansion: ((GapKey) -> GapExpansion)?
    /// Called once the pane shows a new render.
    package var onDisplayed: (() -> Void)?

    package init(
        rendered: RenderedText, gutter: GutterStyle, keepsScrollPosition: Bool = false, wrapsLines: Bool = true, wrapColumn: Int = 0,
        showsMinimap: Bool = true, syncsScrolling: Bool = true, scrollRequest: ScrollRequest? = nil, splitController: SplitPaneController? = nil,
        onGapDrag: ((GapMarker, GapExpansion, Int) -> Void)? = nil, currentExpansion: ((GapKey) -> GapExpansion)? = nil, onDisplayed: (() -> Void)? = nil
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
        self.currentExpansion = currentExpansion
        self.onDisplayed = onDisplayed
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
        Coordinator.configureWrapping(wrapsLines, column: wrapColumn, font: rendered.palette.font, textView: textView, scrollView: scrollView)

        let gutterView = DiffGutterView(clipView: scrollView.contentView)
        gutterView.source = textView
        gutterView.style = gutter
        gutterView.onGapDrag = onGapDrag
        gutterView.currentExpansion = currentExpansion
        let minimapView = MinimapView()
        minimapView.scrollView = scrollView
        minimapView.isHidden = !showsMinimap
        minimapView.visibleRows = { [weak coordinator = context.coordinator] in coordinator?.visibleRows() ?? 0..<0 }
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
        return DiffPaneView(gutterView: gutterView, scrollView: scrollView, contentView: scrollView, minimapView: minimapView)
    }

    package func updateNSView(_ pane: DiffPaneView, context: Context) {
        let coordinator = context.coordinator
        guard let scrollView = pane.scrollView else { return }
        coordinator.metrics.width = max(scrollView.contentView.bounds.width, coordinator.textView?.frame.width ?? 0)
        if coordinator.wrapsLines != wrapsLines || coordinator.wrapColumn != wrapColumn, let textView = coordinator.textView {
            coordinator.wrapsLines = wrapsLines
            coordinator.wrapColumn = wrapColumn
            Coordinator.configureWrapping(wrapsLines, column: wrapColumn, font: rendered.palette.font, textView: textView, scrollView: scrollView)
            splitController?.wrapsLines = wrapsLines
        }
        if pane.minimapView.isHidden == showsMinimap {
            pane.minimapView.isHidden = !showsMinimap
            pane.needsLayout = true
        }
        coordinator.gutterView?.onGapDrag = onGapDrag
        coordinator.gutterView?.currentExpansion = currentExpansion
        splitController?.syncsScrolling = syncsScrolling
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
        NotificationCenter.default.removeObserver(coordinator)
    }

    @MainActor
    package final class Coordinator: NSObject {
        package let fragmentProvider = DiffFragmentProvider()
        package var metrics: ViewportMetrics { fragmentProvider.metrics }
        package weak var textView: NSTextView?
        package weak var gutterView: DiffGutterView?
        package weak var minimapView: MinimapView?
        package var splitController: SplitPaneController?
        package var wrapsLines = true
        package var wrapColumn = 0
        package private(set) var rendered: RenderedText?
        package var handledScrollRequest: UUID?

        package func apply(_ rendered: RenderedText, keepingScroll: Bool = false) {
            let paletteChanged = self.rendered?.palette.font != rendered.palette.font
            self.rendered = rendered
            fragmentProvider.rendered = rendered
            guard let textView, let contentStorage = textView.textContentStorage else { return }
            let previousOrigin = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
            textView.backgroundColor = rendered.palette.background
            textView.insertionPointColor = rendered.palette.textColor
            textView.selectedTextAttributes = [.backgroundColor: rendered.palette.selection]
            contentStorage.performEditingTransaction {
                contentStorage.textStorage?.setAttributedString(rendered.attributed)
            }
            if paletteChanged, let scrollView = textView.enclosingScrollView {
                Self.configureWrapping(wrapsLines, column: wrapColumn, font: rendered.palette.font, textView: textView, scrollView: scrollView)
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
        /// narrower; unwrapped panes grow with their longest line.
        package static func configureWrapping(_ wraps: Bool, column: Int, font: NSFont, textView: NSTextView, scrollView: NSScrollView) {
            guard let container = textView.textContainer else { return }
            let tracksViewport = wraps && column <= 0
            textView.isHorizontallyResizable = !tracksViewport
            textView.autoresizingMask = tracksViewport ? [.width] : []
            container.widthTracksTextView = tracksViewport
            let width: CGFloat = if !wraps {
                CGFloat.greatestFiniteMagnitude
            } else if column > 0 {
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
                  let location = contentManager.location(layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row])
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
            else { return 0..<0 }
            let inset = textView.textContainerInset.height
            let lastRow = rendered.rows.count - 1
            let contentBottom = layoutManager.usageBoundsForTextContainer.maxY + inset
            /// Points below the document, in the overscroll space, belong to the last row.
            func row(at y: CGFloat) -> Int {
                guard y < contentBottom,
                      let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: y - inset))
                else { return y >= contentBottom ? lastRow : 0 }
                return rendered.rowIndex(containing: contentManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location))
            }
            // TextKit 2 lays out lazily: a fragment the viewport reaches may not exist yet, and a row lookup that
            // fails answers 0, which put the bottom edge above the top edge and trapped on the range.
            layoutManager.ensureLayout(for: CGRect(x: 0, y: clipView.bounds.minY - inset, width: clipView.bounds.width, height: clipView.bounds.height))
            let first = min(row(at: max(clipView.bounds.minY, 0)), lastRow)
            let last = min(max(row(at: clipView.bounds.maxY), first), lastRow)
            return first..<(last + 1)
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

        /// Lets the last line scroll up to the top of the pane by giving the text view trailing space below its
        /// content. The space is part of the view, not a scroll inset, so nothing else has to account for it.
        package func updateOverscroll(in clipView: NSClipView) {
            guard let textView, let layoutManager = textView.textLayoutManager else { return }
            // The row's own height, not the font's: a taller line height would otherwise leave the last row short
            // of the top of the pane, half of it hidden under whatever sits above.
            let lineHeight = rendered?.lineHeight ?? DiffPalette.system.defaultLineHeight
            let contentHeight = layoutManager.usageBoundsForTextContainer.height + 2 * textView.textContainerInset.height
            let minimumHeight = (contentHeight + max(clipView.bounds.height - lineHeight, 0)).rounded(.up)
            let minimumWidth: CGFloat = if textView.textContainer?.widthTracksTextView == true {
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

        @objc package func textViewFrameDidChange(_ notification: Notification) {
            guard let textView, let clipView = textView.enclosingScrollView?.contentView else { return }
            metrics.width = max(clipView.bounds.width, textView.frame.width)
            updateOverscroll(in: clipView)
            updateHorizontalScrolling(in: clipView)
        }
    }
}
