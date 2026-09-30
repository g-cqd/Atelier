package import AppKit
import AtelierSyntaxModel
import AtelierTextRendering
import AtelierTextView
package import DiffRendering
import Foundation

/// A scrolling pane drawn by the CoreText renderer behind `DiffTextPane` (text-renderer.md §4.2): a `TextCanvasView`
/// beside the backend-neutral `DiffGutterView` and `MinimapView`, which this hand-back's seam migration lets a
/// non-TextKit pane reuse unchanged.
///
/// Drawing only (text-renderer.md §5 M1): `hoverHit`/`anchorRect` answer nothing yet, `setRowSpacing` is a no-op
/// (split alignment is a follow-up hand-back), and a decoration change rebuilds the shown `StyledText` to recolour
/// its runs — spec §3.2 wants colour to never force new layout, which needs `AtelierTextRendering` to separate
/// layout-affecting runs from colour-only ones; that split is a follow-up. Gap bands (the empty rows around a
/// revealed hunk) are not drawn yet either: they need a per-row trailing space in `LayoutConfiguration`/`HeightIndex`
/// that does not exist yet.
@MainActor
package final class CoreTextPane: DiffTextPane {
    private let scrollView: NSScrollView
    private let canvasView: TextCanvasView
    private let gutterView: DiffGutterView
    private let minimapView: MinimapView
    private let paneView: DiffPaneView
    private var rendered: RenderedText?

    package init(gutter: GutterStyle) {
        let configuration = LayoutConfiguration(
            wrap: .width(0), lineHeight: Double(DiffPalette.system.defaultLineHeight),
            padding: Double(DiffPaneMetrics.lineFragmentPadding))
        let canvasView = TextCanvasView(configuration: configuration)
        // Matches TextKit 2's own container inset (DiffTextView.swift's `apply(_:keepingScroll:)`), so a gutter or a
        // split view lines this pane's rows up with a TextKit 2 pane's.
        canvasView.topInset = Double(DiffPaneMetrics.containerInset)
        canvasView.tracksViewportWidth = true
        canvasView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = canvasView

        let gutterView = DiffGutterView(clipView: scrollView.contentView)
        gutterView.style = gutter
        gutterView.source = CoreTextRowGeometry(canvasView: canvasView)

        let minimapView = MinimapView()
        minimapView.scrollView = scrollView
        minimapView.visibleRows = { [weak canvasView] in
            guard let canvasView else { return 0 ..< 0 }
            let range = canvasView.visibleRowRange()
            return range.lowerBound.index ..< range.upperBound.index
        }
        scrollView.contentView.postsBoundsChangedNotifications = true

        self.scrollView = scrollView
        self.canvasView = canvasView
        self.gutterView = gutterView
        self.minimapView = minimapView
        paneView = DiffPaneView(
            gutterView: gutterView, scrollView: scrollView, contentView: scrollView, minimapView: minimapView)
        minimapView.onSelectRow = { [weak self] row in self?.scroll(toRow: row, centered: true) }
        NotificationCenter.default.addObserver(
            minimapView, selector: #selector(MinimapView.setNeedsDisplayOnScroll(_:)),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    // MARK: DiffTextPane

    package var view: NSView { paneView }
    package var clipView: NSClipView? { scrollView.contentView }

    package func show(_ rendered: RenderedText, keepingScroll: Bool) {
        self.rendered = rendered
        gutterView.rendered = rendered
        minimapView.rendered = rendered
        let (text, _) = Self.convert(rendered: rendered, decorations: nil)
        canvasView.show(text, keepingAnchor: keepingScroll)
    }

    package func setDecorations(_ decorations: DiffDecorations?) {
        guard let rendered else { return }
        let (text, layers) = Self.convert(rendered: rendered, decorations: decorations)
        canvasView.show(text, keepingAnchor: true)
        for layer in layers { canvasView.setDecorations(layer) }
        gutterView.needsDisplay = true
    }

    package func setWrapping(_ mode: WrapMode) {
        switch mode {
            case .none:
                canvasView.tracksViewportWidth = false
                canvasView.configuration.wrap = .none
            case .viewport:
                canvasView.tracksViewportWidth = true
                canvasView.configuration.wrap = .width(Double(canvasView.bounds.width))
            case .column(let column):
                canvasView.tracksViewportWidth = false
                canvasView.configuration.wrap = .columns(column)
        }
    }

    package var geometry: any DiffRowGeometry { CoreTextRowGeometry(canvasView: canvasView) }

    package func scroll(toRow row: Int, centered: Bool) {
        canvasView.scroll(toRow: RowIndex(row), centered: centered)
    }

    package func rowHeights() -> (heights: [Double], isExact: Bool) {
        canvasView.rowHeights()
    }

    package func setRowSpacing(_ spacing: [Double]) {
        // Split alignment is a follow-up hand-back (text-renderer.md §5 M1).
    }

    package func hoverHit(at point: NSPoint) -> HoverHit? { nil }
    package func anchorRect(for hit: HoverHit) -> NSRect? { nil }
}
