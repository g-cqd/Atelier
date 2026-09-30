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
            setHoveredScope(nil)
            invalidateIntrinsicContentSize()
            needsDisplay = true
            // Revealed rows move the boundaries after them, and the handles on them.
            window?.invalidateCursorRects(for: self)
            // A handle held at an edge reveals rows the pointer does not move for: follow them once laid out.
            if handleDrag?.isHeldAtEdge == true { needsLayout = true }
        }
    }

    /// What the pane's stages after the text found, which the scope ribbon reads as it draws (DIFF-03); nil draws no
    /// ribbon.
    package var decorations: DecorationSnapshot? { didSet { needsDisplay = true } }
    /// The pane's decoration store, which lights the braces of the scope under the pointer.
    package weak var decorationStore: DecorationStore?
    /// The scope under the pointer, in the gutter or the text, outlined in the ribbon.
    var hoveredScope: HoveredScope?
    /// Called when the ribbon, or a folding command in the pane, folds or unfolds scopes (DIFF-03).
    package var onScopeFold: ((ScopeFoldRequest) -> Void)?
    /// Whether the ribbon draws and takes the pointer's hover; the gutter keeps the width it takes either way, so
    /// turning it back on never shifts the text.
    package var showsScopeRibbon = true { didSet { needsDisplay = true } }

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
    /// Called with the change whose marker is clicked in the compact inline view (book DIFF-04).
    package var onChangeToggle: ((ChangeKey) -> Void)?
    /// The change whose marker is under the pointer, drawn highlighted.
    var hoveredChange: ChangeKey?
    /// The clip view of the list around an embedded gutter, which it follows: see ``followListScrolling()``.
    private weak var listClipView: NSClipView?
    /// Called when a decorated line number is clicked, with its row, its findings, its frame in this view's
    /// coordinates, and this view, so a popover can anchor on the line.
    package var onDiagnosticClick:
        ((_ rowIndex: Int, _ findings: [Finding], _ anchorRect: NSRect, _ in: NSView) -> Void)?

    /// The text system whose rows are numbered; set together with `rendered`.
    package weak var source: (any GutterTextSource)?
    private weak var clipView: NSClipView?
    /// The padding before the numbers: the change layer moved to their trailing side, next to the text.
    private let padding: CGFloat = 3
    private let columnGap: CGFloat = 10
    private var handleDrag: HandleDrag?
    /// The handle under the pointer, drawn highlighted. The view's tooltip tells its gap's hidden lines meanwhile.
    private var hoveredHandle: HandleID?
    private var hoverTracking: NSTrackingArea?

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

    /// The gutter's width, on a whole point: the text beside it starts on one, so its clip view is not scrolled
    /// sideways by the fraction AppKit aligns it by.
    package var thickness: CGFloat {
        let columns: CGFloat = style == .dual ? 2 : 1
        return (padding + Self.trailingPadding + columns * metrics.columnWidth + (columns - 1) * columnGap).rounded(.up)
    }

    package override var intrinsicContentSize: NSSize {
        NSSize(width: thickness, height: NSView.noIntrinsicMetric)
    }

    var palette: DiffPalette { rendered?.palette ?? .system }

    @objc private func clipViewDidScroll(_ notification: Notification) {
        // The row under a still pointer changed; the next move finds its handle or its marker again.
        updateHover(at: nil)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    package override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        followListScrolling()
    }

    package override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + changeMarkerElements()
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
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    package override func mouseExited(with event: NSEvent) {
        updateHover(at: nil)
    }

    /// Highlights the half of a gap's handle or the change marker under `point`, if any, and tells its help in the
    /// tooltip.
    private func updateHover(at point: NSPoint?) {
        // Nothing beneath the bars over a pane takes the pointer.
        let point = point.flatMap { $0.y >= obscuredTop ? $0 : nil }
        let handle = point.flatMap(gapHalf(at:))
        let change = handle == nil ? point.flatMap(changeMarker(at:)) : nil
        // A drag changes the count under a pointer that stays on the same half: the next move tells the new one.
        let help = handle?.marker.handleHelp ?? change?.help ?? (handle == nil ? point.flatMap(foldHelp(at:)) : nil)
        if toolTip != help { toolTip = help }
        setHoveredHandle(handle)
        setHoveredChange(change?.key)
        setHoveredScope(handle == nil ? point.flatMap(rowIndex(at:)).flatMap(scope(atRow:)) : nil)
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
        forEachGap(in: unobscuredRect(of: visibleRect)) { gap, band in
            for half in handle(of: gap.marker, in: band).halves {
                addCursorRect(
                    half.hitArea, cursor: .rowResize(directions: half.handle == .extendsChangeAbove ? .down : .up))
            }
        }
        addChangeMarkerCursorRects()
        if showsScopeRibbon { addFoldCursorRects() }
    }

    /// Marks for display the line numbers of `rows`, whose diagnostics changed. A gutter beside a clip view draws what
    /// shows only, and draws again on every scroll, so it marks the rows in view alone; an embedded gutter, as tall as
    /// its document, keeps what it drew of rows out of view, so it is marked whole.
    /// - Complexity: O(rows in view), plus a lookup of the first fragment.
    package func redrawDiagnostics(ofRows rows: [Int]) {
        guard clipView != nil else {
            needsDisplay = true
            return
        }
        let changed = Set(rows)
        forEachFragment(in: visibleRect) { fragment, _, rowIndex, y in
            guard changed.contains(rowIndex) else { return }
            // A number's underlay reaches past its row by a point or two.
            let row = NSRect(x: 0, y: y, width: bounds.width, height: fragment.layoutFragmentFrame.height)
            setNeedsDisplay(row.insetBy(dx: 0, dy: -Self.underlayOverhang))
        }
    }

    /// How far a line number's underlay may reach above or below its row.
    private static let underlayOverhang: CGFloat = 4

    package override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard point.y >= obscuredTop else { return super.mouseDown(with: event) }
        // A press in a gap's band belongs to its handle; the rows around it keep their own clicks.
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
        // A marker lies in the change layer after the numbers, which a line number's click does not reach for.
        if let change = changeMarker(at: point) {
            onChangeToggle?(change.key)
            return
        }
        if let request = foldRequest(at: point) {
            onScopeFold?(request)
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
            pointerY: convert(event.locationInWindow, from: nil).y, visible: unobscuredRect(of: visibleRect),
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
        // The pointer let go wherever the drag took it: the half under it now is the one hovered, if any, not the one
        // it pressed.
        updateHover(at: convert(event.locationInWindow, from: nil))
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

    /// Visits the gaps that take a band (book DIFF-02) near the rows intersecting `rect` of this view, each with its
    /// band in this view, across the gutter less its separator. A band ends where the row below it starts: above the
    /// first row, in the text's inset, or at the bottom of the row above it, as that row's paragraph spacing. Below
    /// the last row, it starts where the row ends.
    /// - Complexity: O(rows in `rect` + log gaps), plus a lookup of the first fragment.
    func forEachGap(in rect: NSRect, _ body: (RenderedGap, NSRect) -> Void) {
        guard let rendered, !rendered.gaps.isEmpty else { return }
        let height = rendered.gapBandHeight
        var edges: [Int: (top: CGFloat, bottom: CGFloat)] = [:]
        // A band lies outside the rows it runs between, above the first or below the last: look a band further.
        forEachFragment(in: rect.insetBy(dx: 0, dy: -height)) { fragment, _, rowIndex, y in
            edges[rowIndex] = (y, y + fragment.layoutFragmentFrame.height)
        }
        guard let first = edges.keys.min(), let last = edges.keys.max() else { return }
        let width = max(bounds.width - 1, 0)
        for gap in rendered.gaps(on: first ... (last + 1)) where gap.hasBand {
            let bandTop: CGFloat
            if gap.boundary == rendered.rows.count, let row = edges[gap.boundary - 1] {
                bandTop = row.bottom
            } else if let bottom = edges[gap.boundary]?.top ?? edges[gap.boundary - 1]?.bottom {
                bandTop = bottom - height
            } else {
                continue
            }
            body(gap, NSRect(x: 0, y: bandTop, width: width, height: height))
        }
    }

    package override func draw(_ dirtyRect: NSRect) {
        palette.gutterBackground.setFill()
        dirtyRect.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: dirtyRect.minY, width: 1, height: dirtyRect.height).fill()
        // Beneath the bars over a pane, the gutter keeps its background alone: the text's rows scroll there under the
        // system's edge effect, which the gutter, beside the scroll view, has none of (book TAB-09).
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        unobscuredRect(of: bounds).clip()

        if showsScopeRibbon { drawRibbon(in: dirtyRect) }
        let metrics = metrics
        forEachFragment(in: dirtyRect) { fragment, row, rowIndex, y in
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
            let top = numberTop(of: fragment, at: y)
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
        drawGaps(in: dirtyRect)
        drawChangeBars(in: dirtyRect)
        drawChangeMarkers(in: dirtyRect)
        drawHoveredScope(in: dirtyRect)
        drawFolds(in: dirtyRect)
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

// MARK: Nested types

extension DiffGutterView {
    /// One handle of one gap, as the pointer finds it.
    fileprivate struct HandleID: Equatable {
        let key: GapKey
        let handle: GapHandle
    }

    /// A gap handle drag in progress: the handle, where the pointer went down in window coordinates, which scrolling
    /// never moves, and whether the pointer was last in an edge zone.
    fileprivate struct HandleDrag {
        let id: HandleID
        let startY: CGFloat
        var isHeldAtEdge = false
    }

    /// The font, column width and number attributes of the current text, which every drawn row reuses.
    fileprivate struct Metrics {
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
}

// MARK: Beneath the bars

extension DiffGutterView {
    /// How far down the bars over a pane reach, the toolbar's and the tab bar's, which its text runs beneath and the
    /// gutter draws nothing under (book TAB-09); none for a card's gutter, whose list scrolls on its own.
    var obscuredTop: CGFloat {
        clipView?.contentInsets.top ?? 0
    }

    /// `rect` less what the bars over the pane cover.
    func unobscuredRect(of rect: NSRect) -> NSRect {
        let top = max(rect.minY, obscuredTop)
        return NSRect(x: rect.minX, y: top, width: rect.width, height: max(rect.maxY - top, 0))
    }
}

// MARK: Following the list

extension DiffGutterView {
    /// The list around an embedded gutter scrolled, which moved its rows under a still pointer: the next move finds
    /// the handle or the marker under it again.
    @objc private func listDidScroll(_ notification: Notification) {
        updateHover(at: nil)
    }

    /// An embedded gutter, a card's, has no clip view of its own and scrolls with the list around it: it follows that
    /// list's clip view while in a window, as a pane's gutter follows its own.
    private func followListScrolling() {
        let list = clipView == nil && window != nil ? enclosingScrollView?.contentView : nil
        guard list !== listClipView else { return }
        if let listClipView {
            NotificationCenter.default.removeObserver(
                self, name: NSView.boundsDidChangeNotification, object: listClipView)
        }
        listClipView = list
        guard let list else { return }
        list.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(listDidScroll(_:)), name: NSView.boundsDidChangeNotification, object: list)
    }
}

// MARK: Diagnostics

extension DiffGutterView {
    /// The row whose decorated line number sits under `point`, with its diagnostics and the number's frame.
    private func diagnosticHit(at point: NSPoint) -> (
        rowIndex: Int, diagnostics: DiagnosticOverlay.RowDiagnostics, rect: NSRect
    )? {
        guard overlay?.isEmpty == false, point.x >= 0, point.x < bounds.width else { return nil }
        var found: (Int, DiagnosticOverlay.RowDiagnostics, NSRect)?
        forEachFragment(in: Self.row(at: point)) { fragment, _, rowIndex, y in
            // The row's own height: the band of a gap after it holds no line number.
            let height = fragment.layoutFragmentFrame.height - (rendered?.bandSpacing(afterRow: rowIndex) ?? 0)
            guard point.y >= y, point.y < y + height, let diagnostics = overlay?.row(rowIndex) else { return }
            found = (rowIndex, diagnostics, NSRect(x: 0, y: y, width: bounds.width, height: height))
        }
        return found
    }

    /// Opens `findings` of `rowIndex` as a click on the row's decorated line number opens the row's own, anchored on
    /// that line number.
    /// - Returns: False when nothing takes the click or the row is not laid out, true otherwise.
    @discardableResult
    package func showFindings(_ findings: [Finding], ofRow rowIndex: Int) -> Bool {
        guard let onDiagnosticClick, let rect = lineNumberRect(ofRow: rowIndex) else { return false }
        onDiagnosticClick(rowIndex, findings, rect, self)
        return true
    }

    /// `rowIndex`'s line number in this view, as ``diagnosticHit(at:)`` measures it: the row's fragment, less the band
    /// of a gap after it.
    private func lineNumberRect(ofRow rowIndex: Int) -> NSRect? {
        guard let source, let rendered, rendered.lineStarts.indices.contains(rowIndex),
            let layoutManager = source.gutterLayoutManager, let contentManager = layoutManager.textContentManager,
            let location = contentManager.location(
                layoutManager.documentRange.location, offsetBy: rendered.lineStarts[rowIndex])
        else { return nil }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        let y = fragment.layoutFragmentFrame.minY + source.gutterInset - (clipView?.bounds.origin.y ?? 0)
        let height = fragment.layoutFragmentFrame.height - rendered.bandSpacing(afterRow: rowIndex)
        return NSRect(x: 0, y: y, width: bounds.width, height: height)
    }
}

// MARK: Line numbers

extension DiffGutterView {
    /// The top of the line number of the row `fragment` lays out, whose top is `y` in this view.
    ///
    /// Numbers sit on the same baseline as the row's first line of text, whatever the line height is, so they follow
    /// the text up when a taller line centres it: TextKit reports the baseline it laid out, which is not where a
    /// baseline offset then drew the glyphs.
    fileprivate func numberTop(of fragment: NSTextLayoutFragment, at y: CGFloat) -> CGFloat {
        let firstBaseline =
            fragment.textLineFragments.first.map { $0.typographicBounds.minY + $0.glyphOrigin.y }
            ?? fragment.layoutFragmentFrame.height * 0.75
        return y + firstBaseline - (rendered?.baselineOffset ?? 0) - metrics.font.ascender
    }

    /// Where the gutter draws the line number of each row intersecting `rect` of this view: across the gutter, from
    /// the number's ascender down to its descender, on its row's baseline (book DIFF-06).
    /// - Complexity: O(rows in `rect`), plus a lookup of the first fragment.
    func lineNumberFrames(in rect: NSRect) -> [Int: NSRect] {
        let font = metrics.font
        var frames: [Int: NSRect] = [:]
        forEachFragment(in: rect) { fragment, _, rowIndex, y in
            frames[rowIndex] = NSRect(
                x: 0, y: numberTop(of: fragment, at: y), width: bounds.width, height: font.ascender - font.descender)
        }
        return frames
    }
}

// MARK: Gap handles

extension DiffGutterView {
    /// The handle `marker` shows in its `band`.
    private func handle(of marker: GapMarker, in band: NSRect) -> GapHandleLayout.Handle {
        GapHandleLayout.handle(marker.handles, in: band)
    }

    /// The half of a gap's handle whose part of the band holds `point`, with its gap.
    private func gapHalf(at point: NSPoint) -> (marker: GapMarker, handle: GapHandle)? {
        guard point.x >= 0, point.x < bounds.width else { return nil }
        var found: (GapMarker, GapHandle)?
        forEachGap(in: NSRect(x: 0, y: point.y, width: 1, height: 1)) { gap, band in
            guard found == nil, band.contains(point),
                let half = handle(of: gap.marker, in: band).halves.first(where: { $0.hitArea.contains(point) })
            else { return }
            found = (gap.marker, half.handle)
        }
        return found
    }

    /// Highlights the half of a gap's handle under the pointer, if any.
    private func setHoveredHandle(_ hit: (marker: GapMarker, handle: GapHandle)?) {
        let id = hit.map { HandleID(key: $0.marker.key, handle: $0.handle) }
        guard id != hoveredHandle else { return }
        hoveredHandle = id
        needsDisplay = true
    }

    /// The bands of the gaps near `rect`, each with its handle: the halves the gap offers, highlighted under the
    /// pointer or while dragged, and between two of them the separator, whose part across the text the text draws.
    /// Nothing else is drawn in a band.
    private func drawGaps(in rect: NSRect) {
        forEachGap(in: rect) { gap, band in
            let handle = handle(of: gap.marker, in: band)
            if let separator = handle.separator {
                palette.gapSeparator.setFill()
                separator.fill()
            }
            for half in handle.halves {
                let id = HandleID(key: gap.marker.key, handle: half.handle)
                drawHalf(half, isActive: id == hoveredHandle || id == handleDrag?.id)
            }
            // The separator is the two halves' shared flat side, in the outline's colour whichever half is active, so
            // each half's highlight stays its own.
            guard let separator = handle.separator, let span = handle.halves.first?.rect else { return }
            let side = NSRect(x: span.minX, y: separator.minY, width: span.width, height: 1)
            palette.gutterBackground.setFill()
            side.fill()
            palette.textColor.withAlphaComponent(Self.outlineAlpha(isActive: false)).setFill()
            side.fill()
        }
    }

    /// Xcode's outline and grip: 221 on its white gutter; stronger under the pointer or while dragged.
    private static func outlineAlpha(isActive: Bool) -> CGFloat {
        isActive ? 0.4 : 0.135
    }

    /// One half of a gap's handle: rounded on the side of the change it extends, and open on its flat side, which the
    /// separator or the band's edge closes, with its grip line; drawn stronger while it is hovered or dragged.
    private func drawHalf(_ half: GapHandleLayout.Half, isActive: Bool) {
        let rect = half.rect
        // The outline lies inside the half, half a point in from its edges.
        let radius = min(GapHandleLayout.cornerRadius - 0.5, rect.height - 1, rect.width / 2)
        let isUpper = half.handle == .extendsChangeAbove
        let flatY = isUpper ? rect.maxY : rect.minY
        let roundY = isUpper ? rect.minY + 0.5 : rect.maxY - 0.5
        let left = rect.minX + 0.5
        let right = rect.maxX - 0.5
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: left, y: flatY))
        outline.appendArc(from: NSPoint(x: left, y: roundY), to: NSPoint(x: right, y: roundY), radius: radius)
        outline.appendArc(from: NSPoint(x: right, y: roundY), to: NSPoint(x: right, y: flatY), radius: radius)
        outline.line(to: NSPoint(x: right, y: flatY))
        palette.gutterBackground.setFill()
        outline.fill()
        palette.textColor.withAlphaComponent(isActive ? 0.1 : 0.04).setFill()
        outline.fill()
        palette.textColor.withAlphaComponent(Self.outlineAlpha(isActive: isActive)).setStroke()
        outline.lineWidth = 1
        outline.stroke()
        palette.textColor.withAlphaComponent(Self.outlineAlpha(isActive: isActive)).setFill()
        half.grip.fill()
    }

    /// Scrolls whatever shows the gutter, the pane's clip view or the list around a card, so the band of the gap held
    /// open at an edge stays in view, with its handle, as rows open above it.
    private func keepInView(_ id: HandleID) {
        let visible = unobscuredRect(of: visibleRect)
        guard !visible.isEmpty else { return }
        let reach = 4 * (rendered?.lineHeight ?? DiffPalette.system.defaultLineHeight)
        var target: NSRect?
        forEachGap(in: visible.insetBy(dx: 0, dy: -reach)) { gap, band in
            guard gap.marker.key == id.key else { return }
            target = band
        }
        guard let target, !visible.contains(target) else { return }
        guard let clipView else {
            scrollToVisible(target)
            return
        }
        // The pane's gutter stays put beside its scroll view: the text scrolls under it instead, never past its end,
        // where no text is drawn.
        let delta = target.maxY > visible.maxY ? target.maxY - visible.maxY : target.minY - visible.minY
        let highest = -obscuredTop
        let end = max((clipView.documentView?.frame.height ?? 0) - clipView.bounds.height, highest)
        let y = min(max(clipView.bounds.origin.y + delta, highest), end)
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: y))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }
}
