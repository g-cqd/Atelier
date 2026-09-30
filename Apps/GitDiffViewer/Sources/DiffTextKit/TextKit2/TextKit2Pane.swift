package import AppKit
package import DiffRendering
import Foundation

/// A scrolling pane drawn by TextKit 2 behind ``DiffTextPane`` (text-renderer.md §4.2): the text view, its gutter and
/// its minimap, and the coordinator that keeps them in step, as ``DiffTextView`` shows them.
@MainActor
package final class TextKit2Pane: DiffTextPane {
    /// What a pane is built with; the text, its decorations and its callbacks come afterwards.
    package struct Options {
        package var gutter: GutterStyle
        /// The font lines are wrapped at a column of, until a text brings its own.
        package var font: NSFont = DiffPalette.system.font
        package var wrapsLines = true
        /// Characters per line when wrapping; zero wraps at the viewport width.
        package var wrapColumn = 0
        package var scrollsPastEnd = false
        package var bouncesAtEdges = false
        /// The height of bars laid over the pane's top that AppKit does not know of (see ``DiffTextView/underBars``).
        package var underBars: CGFloat = 0
        package var showsMinimap = true
        /// Whether the gutter's scope ribbon draws and takes the pointer's hover (DIFF-03).
        package var showsScopeRibbon = true
        /// The split view the pane scrolls and aligns its rows with, if any.
        package var splitController: SplitPaneController?

        package init(gutter: GutterStyle) {
            self.gutter = gutter
        }
    }

    package let coordinator: DiffTextViewCoordinator
    package let paneView: DiffPaneView
    package let scrollView: NSScrollView
    package let textView: NSTextView
    package let gutterView: DiffGutterView

    /// Builds the pane's views and wires them to `coordinator`; the pane shows no text until ``show(_:keepingScroll:)``
    /// or the coordinator's own `show`.
    package init(options: Options, coordinator: DiffTextViewCoordinator) {
        self.coordinator = coordinator
        let scrollView = DiffPaneTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        // The safe area, the toolbar's and the bars' above the pane, insets the text, and sizes the edge effect.
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.additionalSafeAreaInsets = DiffTextView.insets(underBars: options.underBars)
        DiffTextView.setElasticity(of: scrollView, bouncing: options.bouncesAtEdges)

        let textView = scrollView.documentView as? NSTextView ?? DiffPaneTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        DiffTextView.configurePanels(of: textView)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textLayoutManager?.delegate = coordinator.fragmentProvider
        coordinator.wrapColumn = options.wrapColumn
        coordinator.scrollsPastEnd = options.scrollsPastEnd
        DiffTextViewCoordinator.configureWrapping(
            options.wrapsLines, column: options.wrapColumn, font: options.font, textView: textView,
            scrollView: scrollView)

        let gutterView = DiffGutterView(clipView: scrollView.contentView)
        gutterView.source = TextKit2RowGeometry(textView: textView, coordinator: coordinator)
        gutterView.style = options.gutter
        gutterView.overlay = coordinator.diagnostics
        gutterView.decorations = coordinator.decorationStore.snapshot
        gutterView.decorationStore = coordinator.decorationStore
        coordinator.decorationStore.gutter = gutterView
        gutterView.showsScopeRibbon = options.showsScopeRibbon
        if options.showsScopeRibbon { coordinator.scopeHover.attach(to: textView, gutter: gutterView) }
        let minimapView = Self.makeMinimap(
            following: scrollView, coordinator: coordinator, showing: options.showsMinimap)

        coordinator.textView = textView
        coordinator.followLayout()
        coordinator.gutterView = gutterView
        coordinator.minimapView = minimapView
        coordinator.splitController = options.splitController
        coordinator.wrapsLines = options.wrapsLines
        options.splitController?
            .register(scrollView, textView: textView) { [weak coordinator] in
                coordinator?.rowsDidAlign()
            }
        Self.observe(scrollView, textView: textView, for: coordinator)

        self.scrollView = scrollView
        self.textView = textView
        self.gutterView = gutterView
        paneView = DiffPaneView(
            gutterView: gutterView, scrollView: scrollView, contentView: scrollView, minimapView: minimapView)
    }

    /// Makes the pane's decoration store colour the text as TextKit lays it out.
    package func installDecorations() {
        guard let layoutManager = textView.textLayoutManager else { return }
        coordinator.decorationStore.install(on: layoutManager)
    }

    /// Sizes and places the text again as the pane's clip view resizes or scrolls, and as the text view resizes.
    private static func observe(
        _ scrollView: NSScrollView, textView: NSTextView, for coordinator: DiffTextViewCoordinator
    ) {
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(DiffTextViewCoordinator.viewportDidResize(_:)),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(DiffTextViewCoordinator.clipViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(DiffTextViewCoordinator.textViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )
    }

    /// The pane's minimap: it shows the rows `scrollView` shows, redraws as it scrolls, and scrolls it to a row
    /// clicked, centred.
    private static func makeMinimap(
        following scrollView: NSScrollView, coordinator: DiffTextViewCoordinator, showing: Bool
    ) -> MinimapView {
        let minimapView = MinimapView()
        minimapView.scrollView = scrollView
        minimapView.isHidden = !showing
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

    // MARK: DiffTextPane

    package var view: NSView { paneView }
    package var clipView: NSClipView? { scrollView.contentView }

    package func show(_ rendered: RenderedText, keepingScroll: Bool) {
        coordinator.decorationStore.willShow(rendered, decorations: nil)
        coordinator.show(rendered, keepingScroll: keepingScroll, key: coordinator.memoryKey)
    }

    package func setDecorations(_ decorations: DiffDecorations?) {
        coordinator.decorationStore.update(rendered: coordinator.rendered, decorations: decorations, view: textView)
    }

    package func setWrapping(_ mode: WrapMode) {
        let font = coordinator.rendered?.palette.font ?? DiffPalette.system.font
        let (wraps, column) =
            switch mode {
                case .none: (false, 0)
                case .viewport: (true, 0)
                case .column(let column): (true, column)
            }
        if coordinator.setWrapping(wraps, column: column, font: font) {
            coordinator.splitController?.wrapsLines = wraps
        }
    }

    package var geometry: any DiffRowGeometry {
        TextKit2RowGeometry(textView: textView, coordinator: coordinator)
    }

    package func scroll(toRow row: Int, centered: Bool) {
        coordinator.scroll(toRow: row, in: scrollView, centered: centered)
    }

    package func rowHeights() -> (heights: [Double], isExact: Bool) {
        guard let layoutManager = textView.textLayoutManager else { return ([], true) }
        return (RowSpacing.rowHeights(in: layoutManager), true)
    }

    package func setRowSpacing(_ spacing: [Double]) {
        guard let rendered = coordinator.rendered, let contentStorage = textView.textContentStorage else { return }
        RowSpacing.apply(spacing, to: contentStorage, rendered: rendered)
    }

    package func hoverHit(at point: NSPoint) -> HoverHit? {
        guard let rendered = coordinator.rendered else { return nil }
        return HoverHitTester.hit(at: point, textView: textView, rendered: rendered)
    }

    package func anchorRect(for hit: HoverHit) -> NSRect? {
        HoverHitTester.anchorRect(for: hit.identifierRange, textView: textView)
    }
}
