package import AppKit
package import DiffRendering
import Foundation

/// The diagnostics one text pane draws: one overlay for the pane's lifetime, which every fragment and the gutter hold,
/// and into which ``update(from:version:)`` copies the caller's rows. A fragment keeps the overlay it was laid out
/// with, so an overlay passed in place of another would reach new fragments only. The scrolling panes and the card
/// panes both draw through one.
@MainActor
package final class PaneDiagnosticsDisplay {
    package let overlay = DiagnosticOverlay()
    /// The caller's overlay and version last applied, so an update pass can tell an in-place overlay mutation from a
    /// no-op re-render.
    private var source: DiagnosticOverlay?
    private var version = -1

    package init() {}

    /// Copies `overlay`'s rows, `nil` meaning none, unless neither the overlay nor its version changed since the last
    /// call.
    /// - Returns: The rows whose diagnostics changed, which the pane redraws; empty when none did.
    /// - Complexity: O(rows with diagnostics).
    package func update(from overlay: DiagnosticOverlay?, version: Int) -> [Int] {
        guard overlay !== source || version != self.version else { return [] }
        source = overlay
        self.version = version
        let rows = overlay?.snapshot() ?? [:]
        let shown = self.overlay.snapshot()
        var changed: [Int] = []
        for (row, rowDiagnostics) in rows where shown[row] != rowDiagnostics { changed.append(row) }
        for row in shown.keys where rows[row] == nil { changed.append(row) }
        guard !changed.isEmpty else { return [] }
        self.overlay.replace(rows)
        return changed
    }
}

extension NSTextView {
    /// Marks for display, across their width, the parts of this view's views that lie over `rows` of `rendered`.
    ///
    /// TextKit 2 draws each laid-out fragment into a view of its own and keeps that drawing: neither the text view's
    /// `needsDisplay` nor invalidating the layout redraws a fragment whose layout is unchanged
    /// (`DiagnosticRedrawPixelsTests`). Only the viewport's fragments have views; a row outside it is drawn afresh
    /// when it scrolls in.
    /// - Complexity: O(rows + views × rows in the viewport).
    package func redrawDiagnostics(ofRows rows: [Int], in rendered: RenderedText) {
        guard let layoutManager = textLayoutManager, let contentManager = layoutManager.textContentManager,
            let viewport = layoutManager.textViewportLayoutController.viewportRange
        else { return }
        let start = layoutManager.documentRange.location
        let laidOut =
            rendered.rowIndex(containing: contentManager.offset(from: start, to: viewport.location))
            ... rendered.rowIndex(containing: contentManager.offset(from: start, to: viewport.endLocation))
        // Each row's lines, top to bottom, in this view's coordinates.
        var bands: [ClosedRange<CGFloat>] = []
        for row in rows where laidOut.contains(row) && rendered.lineStarts.indices.contains(row) {
            guard let location = contentManager.location(start, offsetBy: rendered.lineStarts[row]),
                let fragment = layoutManager.textLayoutFragment(for: location)
            else { continue }
            let top = fragment.layoutFragmentFrame.minY + textContainerOrigin.y
            bands.append(top ... top + fragment.layoutFragmentFrame.height)
        }
        guard !bands.isEmpty else { return }
        var views: [NSView] = [self]
        while let view = views.popLast() {
            views.append(contentsOf: view.subviews)
            let frame = convert(view.bounds, from: view)
            for band in bands where band.lowerBound < frame.maxY && frame.minY < band.upperBound {
                let height = band.upperBound - band.lowerBound
                let dirty = NSRect(x: frame.minX, y: band.lowerBound, width: frame.width, height: height)
                view.setNeedsDisplay(view.convert(dirty, from: self).intersection(view.bounds))
            }
        }
    }
}
