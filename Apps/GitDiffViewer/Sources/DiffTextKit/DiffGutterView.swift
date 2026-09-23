package import AppKit
package import AtelierDiagnostics
import DiffCore
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
            // Revealed rows move the boundaries after them, and the handles on them.
            window?.invalidateCursorRects(for: self)
            // A handle held at an edge reveals rows the pointer does not move for: follow them once laid out.
            if handleDrag?.isHeldAtEdge == true { needsLayout = true }
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

    /// Reports a gap handle's drag, from the press to the release. The gutter only measures the pointer; what it
    /// reveals is the model's to decide.
    package var onGapDrag: ((GapDragEvent) -> Void)?
    /// Called when a decorated line number is clicked, with its row, its findings, its frame in this view's
    /// coordinates, and this view, so a popover can anchor on the line.
    package var onDiagnosticClick:
        ((_ rowIndex: Int, _ findings: [Finding], _ anchorRect: NSRect, _ in: NSView) -> Void)?

    /// The text system whose rows are numbered; set together with `rendered`.
    package weak var source: (any GutterTextSource)?
    private weak var clipView: NSClipView?
    private nonisolated static let padding: CGFloat = 8
    private let columnGap: CGFloat = 10
    /// One handle of one gap, as the pointer finds it.
    private struct HandleID: Equatable {
        let key: GapKey
        let handle: GapHandle
    }

    /// A gap handle drag in progress: the handle, where the pointer went down in window coordinates, which scrolling
    /// never moves, and whether the pointer was last in an edge zone.
    private struct HandleDrag {
        let id: HandleID
        let startY: CGFloat
        var isHeldAtEdge = false
    }

    private var handleDrag: HandleDrag?
    /// The handle under the pointer, drawn highlighted.
    private var hoveredHandle: HandleID?
    private var hoverTracking: NSTrackingArea?

    /// The font, column width and number attributes of the current text, which every drawn row reuses, and where its
    /// number columns start.
    private struct Metrics {
        let font: NSFont
        let columnWidth: CGFloat
        let contextAttributes: [NSAttributedString.Key: Any]
        let changedAttributes: [NSAttributedString.Key: Any]
        /// The leading edge of the first number column: past the gap handles' lane when the text offers a handle.
        /// The halves lie over the rows around their hairline, where those rows' numbers are, and a handle centred in
        /// a gutter this narrow would cover them.
        let numbersLeft: CGFloat

        /// - Complexity: O(rows), for the widest line number, and O(gaps).
        init(rendered: RenderedText?) {
            let palette = rendered?.palette ?? .system
            font = palette.gutterFont
            let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
            let digits = max(String(rendered?.maximumLineNumber ?? 0).count, 2)
            columnWidth = CGFloat(digits) * digitWidth
            contextAttributes = [.font: font, .foregroundColor: palette.gutterText]
            changedAttributes = [.font: font, .foregroundColor: palette.gutterChangedText]
            let offersHandle = rendered?.gaps.contains { !$0.marker.handles.isEmpty } ?? false
            numbersLeft = offersHandle ? max(DiffGutterView.padding, GapHandleLayout.laneWidth) : DiffGutterView.padding
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
        return numbersLeft + columns * metrics.columnWidth + (columns - 1) * columnGap + Self.padding
    }

    /// Where the first number column starts: after the gap handles' lane when the text offers a handle.
    package var numbersLeft: CGFloat { metrics.numbersLeft }

    package override var intrinsicContentSize: NSSize {
        NSSize(width: thickness, height: NSView.noIntrinsicMetric)
    }

    private var palette: DiffPalette { rendered?.palette ?? .system }

    @objc private func clipViewDidScroll(_ notification: Notification) {
        // The row under a still pointer changed; the next move finds its handle again.
        hoveredHandle = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    package override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hoverTracking == nil else { return }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
    }

    package override func mouseMoved(with event: NSEvent) {
        let hit = gapHalf(at: convert(event.locationInWindow, from: nil))
        setHoveredHandle(hit.map { HandleID(key: $0.marker.key, handle: $0.handle) })
    }

    package override func mouseExited(with event: NSEvent) {
        setHoveredHandle(nil)
    }

    package override func layout() {
        super.layout()
        guard let handleDrag, handleDrag.isHeldAtEdge else { return }
        keepInView(handleDrag.id)
    }

    package override func scrollWheel(with event: NSEvent) {
        if let clipView {
            clipView.enclosingScrollView?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    /// Each half of a gap's handle shows the one direction it drags in, over its own hit area only.
    package override func resetCursorRects() {
        forEachGap(in: visibleRect.insetBy(dx: 0, dy: -GapHandleLayout.reach)) { gap, y in
            for half in halves(of: gap.marker, boundaryY: y) {
                addCursorRect(
                    half.hitArea, cursor: .rowResize(directions: half.handle == .extendsChangeAbove ? .down : .up))
            }
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
        // A handle lies over the rows around its hairline, their line numbers included, so it takes a press first;
        // the rest of those rows' gutter keeps its own clicks.
        if let hit = gapHalf(at: point) {
            if event.clickCount == 2 {
                onGapDrag?(.revealedAll(hit.marker, hit.handle))
                return
            }
            handleDrag = HandleDrag(
                id: HandleID(key: hit.marker.key, handle: hit.handle), startY: event.locationInWindow.y)
            needsDisplay = true
            let lineHeight = rendered?.lineHeight ?? palette.defaultLineHeight
            onGapDrag?(.began(hit.marker, hit.handle, lineHeight: max(lineHeight, 1)))
            return
        }
        if let (rowIndex, diagnostics, rect) = diagnosticHit(at: point) {
            onDiagnosticClick?(rowIndex, diagnostics.findings, rect, self)
            return
        }
        super.mouseDown(with: event)
    }

    package override func mouseDragged(with event: NSEvent) {
        guard var drag = handleDrag else { return }
        let overshoot = GapHandleLayout.edgeOvershoot(
            pointerY: convert(event.locationInWindow, from: nil).y, visible: visibleRect,
            direction: drag.id.handle.revealDirection)
        drag.isHeldAtEdge = overshoot > 0
        handleDrag = drag
        // Window coordinates grow upwards, and scrolling what shows the gutter never moves them.
        onGapDrag?(.moved(offset: drag.startY - event.locationInWindow.y, edgeOvershoot: overshoot))
    }

    package override func mouseUp(with event: NSEvent) {
        guard handleDrag != nil else { return super.mouseUp(with: event) }
        handleDrag = nil
        needsDisplay = true
        onGapDrag?(.ended)
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

    /// Visits the gaps on the boundaries of the rows intersecting `rect` of this view, each with its boundary's y in
    /// this view.
    /// - Complexity: O(rows in `rect` + log gaps), plus a lookup of the first fragment.
    func forEachGap(in rect: NSRect, _ body: (RenderedGap, CGFloat) -> Void) {
        guard let rendered, !rendered.gaps.isEmpty else { return }
        var boundaries: [Int: CGFloat] = [:]
        forEachFragment(in: rect) { fragment, _, rowIndex, y in
            // A row's top is its boundary with the row above. Its bottom stands for the next row's top until that row
            // is visited, and is the only boundary below the last row.
            boundaries[rowIndex] = y
            boundaries[rowIndex + 1] = y + fragment.layoutFragmentFrame.height
        }
        guard let first = boundaries.keys.min(), let last = boundaries.keys.max() else { return }
        for gap in rendered.gaps(on: first ... last) {
            guard let y = boundaries[gap.boundary] else { continue }
            body(gap, y)
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
                    metrics.numbersLeft + CGFloat(column) * (metrics.columnWidth + columnGap) + metrics.columnWidth
                    - size.width
                if let diagnostics {
                    drawUnderlay(severity: diagnostics.severity, x: x, top: top, size: size)
                }
                label.draw(at: NSPoint(x: x, y: top), withAttributes: attributes)
            }
        }
        drawGaps(in: dirtyRect)
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

// MARK: Gap handles

extension DiffGutterView {
    /// The halves `marker` offers on the hairline at `boundaryY`, in the lane before the numbers.
    private func halves(of marker: GapMarker, boundaryY: CGFloat) -> [GapHandleLayout.Half] {
        GapHandleLayout.halves(
            marker.handles, boundaryY: boundaryY, rowHeight: rendered?.lineHeight ?? palette.defaultLineHeight)
    }

    /// The half of a gap's handle whose hit area holds `point`, with its gap.
    private func gapHalf(at point: NSPoint) -> (marker: GapMarker, handle: GapHandle)? {
        guard point.x >= 0, point.x < bounds.width else { return nil }
        var found: (GapMarker, GapHandle)?
        let reach = GapHandleLayout.reach
        forEachGap(in: NSRect(x: 0, y: point.y - reach, width: 1, height: 2 * reach)) { gap, y in
            guard found == nil,
                let half = halves(of: gap.marker, boundaryY: y).first(where: { $0.hitArea.contains(point) })
            else { return }
            found = (gap.marker, half.handle)
        }
        return found
    }

    private func setHoveredHandle(_ id: HandleID?) {
        guard id != hoveredHandle else { return }
        hoveredHandle = id
        needsDisplay = true
    }

    /// The gaps whose halves reach into `rect`: a hairline across the gutter on each one's boundary, and the halves it
    /// offers over the rows on either side, highlighted under the pointer or while dragged. A gap offering none, a
    /// whole file without a change, leaves no trace.
    private func drawGaps(in rect: NSRect) {
        let width = bounds.width - 1
        forEachGap(in: rect.insetBy(dx: 0, dy: -GapHandleLayout.reach)) { gap, y in
            let halves = halves(of: gap.marker, boundaryY: y)
            guard let span = halves.first?.rect else { return }
            for half in halves {
                let id = HandleID(key: gap.marker.key, handle: half.handle)
                drawHalf(half, isActive: id == hoveredHandle || id == handleDrag?.id)
            }
            // The hairline, which is also the halves' flat side across their width: drawn once, the same whichever
            // half is active, so each half's highlight stays its own. It straddles its boundary, but lies inside the
            // first or the last row at the top or the end of the text, where a card's edge would cut it in half.
            let lineY: CGFloat =
                if gap.boundary == 0 {
                    y
                } else if gap.boundary == rendered?.rows.count {
                    y - 1
                } else {
                    y - 0.5
                }
            let line = NSRect(x: 0, y: lineY, width: width, height: 1)
            palette.textColor.withAlphaComponent(Self.hairlineAlpha).setFill()
            line.divided(atDistance: span.minX, from: .minXEdge).slice.fill()
            line.divided(atDistance: width - span.maxX, from: .maxXEdge).slice.fill()
            palette.gutterBackground.setFill()
            NSRect(x: span.minX, y: line.minY, width: span.width, height: 1).fill()
            palette.textColor.withAlphaComponent(Self.strokeAlpha(isActive: false)).setFill()
            NSRect(x: span.minX, y: line.minY, width: span.width, height: 1).fill()
        }
    }

    private static let hairlineAlpha: CGFloat = 0.1

    private static func strokeAlpha(isActive: Bool) -> CGFloat {
        isActive ? 0.5 : 0.22
    }

    /// One half of a gap's rectangle: rounded on the side of the change it extends and open on the hairline, which
    /// draws its flat side, with one grip line across it; drawn stronger while it is hovered or dragged.
    private func drawHalf(_ half: GapHandleLayout.Half, isActive: Bool) {
        let rect = half.rect
        let radius = min(GapHandleLayout.cornerRadius, rect.height - 1, rect.width / 2)
        let (flatY, roundY) =
            half.handle == .extendsChangeAbove ? (rect.maxY, rect.minY + 0.5) : (rect.minY, rect.maxY - 0.5)
        let left = rect.minX + 0.5
        let right = rect.maxX - 0.5
        // Its stroke lies inside the half, which ends on the boundary.
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: left, y: flatY))
        outline.appendArc(from: NSPoint(x: left, y: roundY), to: NSPoint(x: right, y: roundY), radius: radius)
        outline.appendArc(from: NSPoint(x: right, y: roundY), to: NSPoint(x: right, y: flatY), radius: radius)
        outline.line(to: NSPoint(x: right, y: flatY))
        palette.gutterBackground.setFill()
        outline.fill()
        palette.textColor.withAlphaComponent(isActive ? 0.12 : 0.04).setFill()
        outline.fill()
        palette.textColor.withAlphaComponent(Self.strokeAlpha(isActive: isActive)).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        palette.textColor.withAlphaComponent(Self.strokeAlpha(isActive: isActive)).setFill()
        let gripWidth = min(8, rect.width - 6)
        NSRect(x: rect.midX - gripWidth / 2, y: rect.midY - 0.5, width: gripWidth, height: 1).fill()
    }

    /// Scrolls whatever shows the gutter, the pane's clip view or the list around a card, so the boundary of the gap
    /// held open at an edge stays in view, with its handle, as rows open above it.
    private func keepInView(_ id: HandleID) {
        let visible = visibleRect
        guard !visible.isEmpty else { return }
        let reach = 4 * (rendered?.lineHeight ?? DiffPalette.system.defaultLineHeight)
        var target: NSRect?
        forEachGap(in: visible.insetBy(dx: 0, dy: -reach)) { gap, y in
            guard gap.marker.key == id.key else { return }
            let half = GapHandleLayout.halfHeight
            target = NSRect(x: 0, y: y - half, width: bounds.width, height: 2 * half)
        }
        guard let target, !visible.contains(target) else { return }
        guard let clipView else {
            scrollToVisible(target)
            return
        }
        // The pane's gutter stays put beside its scroll view: the text scrolls under it instead.
        let delta = target.maxY > visible.maxY ? target.maxY - visible.maxY : target.minY - visible.minY
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: clipView.bounds.origin.y + delta))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
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
