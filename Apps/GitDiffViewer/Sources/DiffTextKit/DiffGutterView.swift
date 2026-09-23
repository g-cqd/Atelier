package import AppKit
package import AtelierDiagnostics
package import DiffCore
package import DiffRendering
package import Foundation
import SwiftUI

package enum GutterStyle {
    case dual
    case old
    case new
}

/// What a gutter reads: a text system and the vertical inset its container sits at.
@MainActor
package protocol GutterTextSource: AnyObject {
    var gutterLayoutManager: NSTextLayoutManager? { get }
    var gutterInset: CGFloat { get }
}

extension NSTextView: GutterTextSource {
    package var gutterLayoutManager: NSTextLayoutManager? { textLayoutManager }
    package var gutterInset: CGFloat { textContainerInset.height }
}

extension StaticTextLayout: GutterTextSource {
    package var gutterLayoutManager: NSTextLayoutManager? { layoutManager }
    package var gutterInset: CGFloat { inset }
}

/// Line numbers drawn from the laid-out fragments of the visible viewport only, so cost is proportional to what is
/// on screen. Sits next to the scroll view and redraws when the clip view scrolls.
package final class DiffGutterView: NSView {
    package var rendered: RenderedText? {
        didSet {
            metrics = Metrics(rendered: rendered)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    package var style: GutterStyle = .dual {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// Diagnostics for the pane's rows: a row with one tints its line number over a faint underlay, without changing
    /// the gutter's width.
    package var overlay: DiagnosticOverlay? {
        didSet {
            needsDisplay = true
        }
    }

    /// Called while a gap handle is dragged, with the expansion at the start of the drag and the rows dragged so far.
    package var onGapDrag: ((GapMarker, GapExpansion, Int) -> Void)?
    /// Expansion currently applied to a gap, captured when a drag starts.
    package var currentExpansion: ((GapKey) -> GapExpansion)?
    /// Called when a decorated line number is clicked, with its row, its findings, its frame in this view's
    /// coordinates, and this view, so a popover can anchor on the line.
    package var onDiagnosticClick:
        ((_ rowIndex: Int, _ findings: [Finding], _ anchorRect: NSRect, _ in: NSView) -> Void)?

    /// The text system whose rows are numbered; set together with `rendered`.
    package weak var source: (any GutterTextSource)?
    private weak var clipView: NSClipView?
    private let padding: CGFloat = 8
    private let columnGap: CGFloat = 10
    /// A gap handle drag in progress: the gap, the expansion it started from, and the geometry rows are counted in.
    private struct GapDrag {
        let marker: GapMarker
        let base: GapExpansion
        let startY: CGFloat
        let lineHeight: CGFloat
    }

    private var drag: GapDrag?

    /// The font, column width and number attributes of the current text, which every drawn row reuses.
    private struct Metrics {
        let font: NSFont
        let columnWidth: CGFloat
        let contextAttributes: [NSAttributedString.Key: Any]
        let changedAttributes: [NSAttributedString.Key: Any]

        /// - Complexity: O(rows), for the widest line number.
        init(rendered: RenderedText?) {
            let palette = rendered?.palette ?? .system
            font = palette.gutterFont
            let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
            let digits = max(String(rendered?.maximumLineNumber ?? 0).count, 2)
            columnWidth = CGFloat(digits) * digitWidth
            contextAttributes = [.font: font, .foregroundColor: palette.gutterText]
            changedAttributes = [.font: font, .foregroundColor: palette.gutterChangedText]
        }
    }

    private var metrics = Metrics(rendered: nil)

    /// Without a clip view the gutter belongs to an embedded pane that shows its whole document.
    package init(clipView: NSClipView?) {
        self.clipView = clipView
        super.init(frame: .zero)
        clipsToBounds = true
        guard let clipView else { return }
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    @available(*, unavailable)
    package required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    package override var isFlipped: Bool { true }

    package var thickness: CGFloat {
        let columns: CGFloat = style == .dual ? 2 : 1
        return padding * 2 + columns * metrics.columnWidth + (columns - 1) * columnGap
    }

    package override var intrinsicContentSize: NSSize {
        NSSize(width: thickness, height: NSView.noIntrinsicMetric)
    }

    private var palette: DiffPalette { rendered?.palette ?? .system }

    @objc private func clipViewDidScroll(_ notification: Notification) {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Gap handles

    /// A grip on the gap row: the row's tint across the gutter and two bars in the middle.
    private func drawGapHandle(y: CGFloat, height: CGFloat) {
        if let background = palette.rowBackground(for: .gap, side: .unified) {
            background.setFill()
            NSRect(x: 0, y: y, width: bounds.width - 1, height: height).fill()
        }
        palette.textColor.withAlphaComponent(0.45).setFill()
        let gripWidth = min(bounds.width - 2 * padding, 18)
        let x = (bounds.width - gripWidth) / 2
        let middle = y + height / 2
        NSRect(x: x, y: middle - 3, width: gripWidth, height: 1.5).fill()
        NSRect(x: x, y: middle + 1.5, width: gripWidth, height: 1.5).fill()
    }

    package override func scrollWheel(with event: NSEvent) {
        if let clipView {
            clipView.enclosingScrollView?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    package override func resetCursorRects() {
        forEachFragment(in: visibleRect) { fragment, row, _, y in
            guard row.kind == .gap else { return }
            addCursorRect(
                NSRect(x: 0, y: y, width: bounds.width, height: fragment.layoutFragmentFrame.height),
                cursor: .resizeUpDown)
        }
    }

    /// The row whose decorated line number sits under `point`, with its diagnostics and the number's frame.
    private func diagnosticHit(at point: NSPoint) -> (
        rowIndex: Int, diagnostics: DiagnosticOverlay.RowDiagnostics, rect: NSRect
    )? {
        guard overlay?.isEmpty == false, point.x >= 0, point.x < bounds.width else { return nil }
        var found: (Int, DiagnosticOverlay.RowDiagnostics, NSRect)?
        forEachFragment(in: Self.row(at: point)) { fragment, row, rowIndex, y in
            let frame = fragment.layoutFragmentFrame
            guard row.kind != .gap, point.y >= y, point.y < y + frame.height, let diagnostics = overlay?.row(rowIndex)
            else { return }
            found = (rowIndex, diagnostics, NSRect(x: 0, y: y, width: bounds.width, height: frame.height))
        }
        return found
    }

    package override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let (rowIndex, diagnostics, rect) = diagnosticHit(at: point) {
            onDiagnosticClick?(rowIndex, diagnostics.findings, rect, self)
            return
        }
        var hit: (GapMarker, CGFloat)?
        forEachFragment(in: Self.row(at: point)) { fragment, row, _, y in
            let frame = fragment.layoutFragmentFrame
            if let gap = row.gap, point.y >= y, point.y < y + frame.height {
                hit = (gap, fragment.textLineFragments.first?.typographicBounds.height ?? frame.height)
            }
        }
        guard let (marker, lineHeight) = hit else { return super.mouseDown(with: event) }
        let base = currentExpansion?(marker.key) ?? GapExpansion()
        if event.clickCount == 2 {
            // A double click reveals the whole gap: as many lines as it hides, in whichever direction it allows.
            onGapDrag?(marker, base, marker.hiddenRows)
            return
        }
        drag = GapDrag(marker: marker, base: base, startY: point.y, lineHeight: max(lineHeight, 1))
    }

    package override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let lines = Int(((point.y - drag.startY) / drag.lineHeight).rounded())
        onGapDrag?(drag.marker, drag.base, lines)
    }

    package override func mouseUp(with event: NSEvent) {
        drag = nil
    }

    /// A one-point-tall band across the gutter at `point`, for hit tests.
    private static func row(at point: NSPoint) -> NSRect {
        NSRect(x: 0, y: point.y, width: 1, height: 1)
    }

    /// Visits the laid-out fragments intersecting `rect` of this view, with each row's metadata, its row index, and
    /// its y in this view.
    ///
    /// Starts at the fragment under `rect`'s top rather than at the document's start, so drawing one tile of a tall
    /// embedded gutter costs the rows in that tile, not the whole document. A top not laid out yet starts at the
    /// text's laid-out viewport when `rect` lies below that viewport's top, and at the document's start otherwise.
    /// - Complexity: O(rows in `rect`), plus a lookup of the first fragment.
    func forEachFragment(in rect: NSRect, _ body: (NSTextLayoutFragment, RowMeta, Int, CGFloat) -> Void) {
        guard let source, let rendered, !rendered.rows.isEmpty, let layoutManager = source.gutterLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        let scrollOffset = clipView?.bounds.origin.y ?? 0
        let inset = source.gutterInset
        let top = CGPoint(x: 0, y: max(rect.minY - inset + scrollOffset, 0))
        let viewport = layoutManager.textViewportLayoutController
        let start =
            layoutManager.textLayoutFragment(for: top)?.rangeInElement.location
            ?? viewport.viewportRange.flatMap { top.y >= viewport.viewportBounds.minY ? $0.location : nil }
            ?? layoutManager.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let y = frame.minY + inset - scrollOffset
            if y > rect.maxY { return false }
            if y + frame.height < rect.minY { return true }
            let offset = contentManager.offset(
                from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
            let rowIndex = rendered.rowIndex(containing: offset)
            body(fragment, rendered.rows[rowIndex], rowIndex, y)
            return true
        }
    }

    package override func draw(_ dirtyRect: NSRect) {
        palette.gutterBackground.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()

        let metrics = metrics
        forEachFragment(in: dirtyRect) { fragment, row, rowIndex, y in
            let frame = fragment.layoutFragmentFrame
            if row.kind == .gap {
                drawGapHandle(y: y, height: frame.height)
                return
            }
            let diagnostics = overlay?.row(rowIndex)
            let attributes: [NSAttributedString.Key: Any] =
                if let diagnostics {
                    [.font: metrics.font, .foregroundColor: severityColor(diagnostics.severity)]
                } else {
                    row.kind == .context ? metrics.contextAttributes : metrics.changedAttributes
                }
            // A line numbered the same on both sides shows its number once, next to the text.
            let numbers: [Int?] =
                switch style {
                    case .dual: row.oldNumber == row.newNumber ? [nil, row.newNumber] : [row.oldNumber, row.newNumber]
                    case .old: [row.oldNumber]
                    case .new: [row.newNumber]
                }
            // Numbers sit on the same baseline as the row's first line of text, whatever the line height is, so
            // they follow the text up when a taller line centres it: TextKit reports the baseline it laid out,
            // which is not where a baseline offset then drew the glyphs.
            let firstLine = fragment.textLineFragments.first
            let baseline =
                y + (firstLine.map { $0.typographicBounds.minY + $0.glyphOrigin.y } ?? frame.height * 0.75)
                - (rendered?.baselineOffset ?? 0)
            let top = baseline - metrics.font.ascender
            for (column, number) in numbers.enumerated() {
                guard let number else { continue }
                let label = String(number) as NSString
                let size = label.size(withAttributes: attributes)
                let x =
                    padding + CGFloat(column) * (metrics.columnWidth + columnGap) + metrics.columnWidth - size.width
                if let diagnostics {
                    drawUnderlay(severity: diagnostics.severity, x: x, top: top, size: size)
                }
                label.draw(at: NSPoint(x: x, y: top), withAttributes: attributes)
            }
        }
    }

    /// A faint rounded-rect wash in the severity's colour behind a diagnostic-carrying line number.
    private func drawUnderlay(severity: Finding.Severity, x: CGFloat, top: CGFloat, size: NSSize) {
        let inset: CGFloat = 2
        let rect = NSRect(x: x - inset, y: top - 1, width: size.width + 2 * inset, height: size.height + 2)
        severityColor(severity).withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3).fill()
    }

    private func severityColor(_ severity: Finding.Severity) -> NSColor {
        switch severity {
            case .error: .systemRed
            case .warning: .systemYellow
            case .note: .systemGray
        }
    }
}

/// Gutter on the left, the content (a scroll view, or a static text view when embedded) in the middle, optional
/// minimap on the right.
package final class DiffPaneView: NSView {
    package let gutterView: DiffGutterView
    package let scrollView: NSScrollView?
    package let contentView: NSView
    package let minimapView: MinimapView

    package init(gutterView: DiffGutterView, scrollView: NSScrollView?, contentView: NSView, minimapView: MinimapView) {
        self.gutterView = gutterView
        self.scrollView = scrollView
        self.contentView = contentView
        self.minimapView = minimapView
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(contentView)
        addSubview(gutterView)
        addSubview(minimapView)
    }

    @available(*, unavailable)
    package required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// A sideways scroll the pane cannot use ends here. Passed further up, it reaches controls that read a swipe
    /// as a choice, such as the layout picker; a vertical one still goes on to the list around a card.
    package override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaX) <= abs(event.scrollingDeltaY) else { return }
        super.scrollWheel(with: event)
    }

    package override func layout() {
        super.layout()
        let thickness = gutterView.thickness
        let minimapWidth = minimapView.isHidden ? 0 : MinimapView.width
        gutterView.frame = NSRect(x: 0, y: 0, width: thickness, height: bounds.height)
        contentView.frame = NSRect(
            x: thickness, y: 0, width: max(bounds.width - thickness - minimapWidth, 0), height: bounds.height)
        minimapView.frame = NSRect(x: bounds.width - minimapWidth, y: 0, width: minimapWidth, height: bounds.height)
    }
}
