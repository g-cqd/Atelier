import AppKit
import DiffCore
import DiffRendering

/// The compact inline view's change markers in the gutter (book DIFF-04, D43; `compact-inline-design.md`): drawn over
/// the rows, in the change layer back on the gutter's leading edge, before the numbers, clicked to disclose or fold
/// their change.
extension DiffGutterView {
    /// Visits the markers of the changes near the rows intersecting `rect` of this view, each with its shape.
    ///
    /// A bar runs from its first row's top to its last row's own bottom, less the band of a gap after it; a bar that
    /// runs out of `rect` runs on well past its edge, so its round end is not drawn there. A folded removal's wedge
    /// sits across its boundary, below it at the top of the text or under a band, and above it at the end; with no
    /// gap between it and the change beside it, it keeps to the side away from that change, so the two never overlap
    /// (book D43).
    /// - Complexity: O(rows in `rect` + log changes + changes returned), plus a lookup of the first fragment.
    func forEachChangeMarker(in rect: NSRect, _ body: (RenderedChange, ChangeMarkerLayout.Shape) -> Void) {
        guard let rendered, !rendered.changes.isEmpty else { return }
        var edges: [Int: (top: CGFloat, bottom: CGFloat)] = [:]
        // A wedge reaches half its height past its boundary: look a row further.
        forEachRow(in: rect.insetBy(dx: 0, dy: -rendered.lineHeight)) { frame, _, rowIndex, y, _ in
            let height = frame.height - rendered.bandSpacing(afterRow: rowIndex)
            edges[rowIndex] = (y, y + height)
        }
        guard let first = edges.keys.min(), let last = edges.keys.max() else { return }
        let overrun = rect.insetBy(dx: 0, dy: -2 * ChangeMarkerLayout.barWidth)
        let slice = rendered.changes(on: first ... (last + 1))
        for index in slice.indices {
            let change = rendered.changes[index]
            if change.rows.isEmpty {
                let previous = index > rendered.changes.startIndex ? rendered.changes[index - 1] : nil
                let next = index + 1 < rendered.changes.endIndex ? rendered.changes[index + 1] : nil
                guard
                    let wedge = wedge(
                        at: change.rows.lowerBound, edges: edges, in: rendered, previous: previous, next: next)
                else { continue }
                body(change, .wedge(wedge))
            } else {
                let top = edges[change.rows.lowerBound]?.top ?? overrun.minY
                let bottom = edges[change.rows.upperBound - 1]?.bottom ?? overrun.maxY
                let isHovered = change.key == hoveredChange
                let bar = ChangeMarkerLayout.bar(top: top, bottom: bottom, isHovered: isHovered, layerX: changeLayerX)
                body(change, .bar(bar))
            }
        }
    }

    /// The wedge of a folded removal on `boundary`, from the edges of the rows around it; nil unless they are known.
    /// Centred across the boundary when both neighbours leave a row of context around it; kept to the side away from
    /// a `previous` or `next` change that touches the boundary with none, so the wedge never overlaps its bar (book
    /// D43, R134).
    private func wedge(
        at boundary: Int, edges: [Int: (top: CGFloat, bottom: CGFloat)], in rendered: RenderedText,
        previous: RenderedChange?, next: RenderedChange?
    ) -> CGRect? {
        if boundary == 0 {
            return edges[0].map { ChangeMarkerLayout.wedge(at: $0.top, placement: .below, layerX: changeLayerX) }
        }
        if boundary >= rendered.rows.count {
            return edges[boundary - 1]
                .map {
                    ChangeMarkerLayout.wedge(at: $0.bottom, placement: .above, layerX: changeLayerX)
                }
        }
        guard let below = edges[boundary] else { return nil }
        let underBand = rendered.bandedGap(afterRow: boundary - 1) != nil
        let placement = Self.wedgePlacement(underBand: underBand, previous: previous, next: next, boundary: boundary)
        return ChangeMarkerLayout.wedge(at: below.top, placement: placement, layerX: changeLayerX)
    }

    /// Where a wedge on `boundary` sits: below it when a gap's band lies there, or a change touches it from above
    /// with no row between, so the wedge never overlaps that change's bar; above it when only the change after it
    /// touches; centred otherwise, as a row of context then separates it from its neighbours either way (book D43,
    /// R134).
    private static func wedgePlacement(
        underBand: Bool, previous: RenderedChange?, next: RenderedChange?, boundary: Int
    ) -> ChangeMarkerLayout.WedgePlacement {
        let touchesAbove = underBand || previous?.rows.upperBound == boundary
        let touchesBelow = next?.rows.lowerBound == boundary
        return touchesAbove ? .below : touchesBelow ? .above : .centred
    }

    /// The change whose marker takes the pointer at `point`, its shape found by looking up its own rows directly
    /// (``DiffGutterView/lineNumberRect(ofRow:)``) rather than guessed from a small window around `point`: a change
    /// that reaches well past a line height, common in isolated-changes mode and in a card of a whole file, is placed
    /// correctly regardless of how far its own rows lie from the one under the pointer (book D43, "hover hits the
    /// wrong row").
    func changeMarker(at point: NSPoint) -> RenderedChange? {
        guard point.x >= changeLayerX, point.x < changeLayerX + ChangeMarkerLayout.hitWidth, let rendered,
            let row = rowIndex(at: point)
        else { return nil }
        // A wedge reaches half a row either side of its boundary, so the row before and after are candidates too.
        let slice = rendered.changes(on: max(row - 1, 0) ... (row + 1))
        for index in slice.indices {
            let change = rendered.changes[index]
            guard let shape = exactShape(of: change, at: index, in: rendered) else { continue }
            if ChangeMarkerLayout.hitArea(of: shape, lineHeight: rendered.lineHeight, layerX: changeLayerX)
                .contains(point)
            {
                return change
            }
        }
        return nil
    }

    /// `change`'s own shape, its rows' or its boundary's edges looked up directly, so it is placed correctly wherever
    /// it lies, not only near wherever ``forEachChangeMarker(in:_:)`` last gathered edges for.
    private func exactShape(of change: RenderedChange, at index: Int, in rendered: RenderedText)
        -> ChangeMarkerLayout.Shape?
    {
        guard !change.rows.isEmpty else {
            let boundary = change.rows.lowerBound
            let previous = index > rendered.changes.startIndex ? rendered.changes[index - 1] : nil
            let next = index + 1 < rendered.changes.endIndex ? rendered.changes[index + 1] : nil
            guard let wedge = exactWedge(at: boundary, in: rendered, previous: previous, next: next) else {
                return nil
            }
            return .wedge(wedge)
        }
        guard let first = lineNumberRect(ofRow: change.rows.lowerBound),
            let last = lineNumberRect(ofRow: change.rows.upperBound - 1)
        else { return nil }
        let bar = ChangeMarkerLayout.bar(
            top: first.minY, bottom: last.minY + last.height, isHovered: change.key == hoveredChange,
            layerX: changeLayerX)
        return .bar(bar)
    }

    /// The wedge of a folded removal on `boundary`, its own row edges looked up directly: see
    /// ``wedge(at:edges:in:previous:next:)``, which this mirrors for a point rather than a drawn rect.
    private func exactWedge(
        at boundary: Int, in rendered: RenderedText, previous: RenderedChange?, next: RenderedChange?
    ) -> CGRect? {
        if boundary == 0 {
            return lineNumberRect(ofRow: 0)
                .map { ChangeMarkerLayout.wedge(at: $0.minY, placement: .below, layerX: changeLayerX) }
        }
        if boundary >= rendered.rows.count {
            return lineNumberRect(ofRow: boundary - 1)
                .map { ChangeMarkerLayout.wedge(at: $0.minY + $0.height, placement: .above, layerX: changeLayerX) }
        }
        guard let below = lineNumberRect(ofRow: boundary) else { return nil }
        let underBand = rendered.bandedGap(afterRow: boundary - 1) != nil
        let placement = Self.wedgePlacement(underBand: underBand, previous: previous, next: next, boundary: boundary)
        return ChangeMarkerLayout.wedge(at: below.minY, placement: placement, layerX: changeLayerX)
    }

    /// The markers in view as buttons for VoiceOver: each names its change and whether it shows, and a press
    /// discloses or folds it, as a click does.
    func changeMarkerElements() -> [ChangeMarkerElement] {
        guard let rendered else { return [] }
        var elements: [ChangeMarkerElement] = []
        forEachChangeMarker(in: unobscuredRect(of: visibleRect)) { change, shape in
            let frame = ChangeMarkerLayout.hitArea(of: shape, lineHeight: rendered.lineHeight, layerX: changeLayerX)
            elements.append(
                ChangeMarkerElement(change: change, frame: frame, parent: self) { [weak self] in
                    self?.onChangeToggle?(change.key)
                })
        }
        return elements
    }

    /// Highlights the marker of the change `key`, if any.
    func setHoveredChange(_ key: ChangeKey?) {
        guard key != hoveredChange else { return }
        hoveredChange = key
        needsDisplay = true
    }

    /// Each marker in view takes a pointing hand over its hit area.
    func addChangeMarkerCursorRects() {
        guard let rendered else { return }
        forEachChangeMarker(in: unobscuredRect(of: visibleRect)) { _, shape in
            let area = ChangeMarkerLayout.hitArea(of: shape, lineHeight: rendered.lineHeight, layerX: changeLayerX)
            addCursorRect(area, cursor: .pointingHand)
        }
    }

    /// Xcode's change bar beside every changed row near `rect`, with the Xcode diff colours (book D18): one solid bar
    /// in the change layer, right of the numbers as Xcode draws it, where the compact inline view draws its markers
    /// instead, down each row's own height, so
    /// that the rows of one change join into one bar and a gap's band breaks it.
    func drawChangeBars(in rect: NSRect) {
        guard let rendered, rendered.changes.isEmpty, let color = rendered.palette.changeBar else { return }
        color.setFill()
        forEachRow(in: rect) { frame, row, rowIndex, y, _ in
            guard [.added, .removed, .modified].contains(row.kind) else { return }
            let height = frame.height - rendered.bandSpacing(afterRow: rowIndex)
            NSRect(x: changeLayerX + ChangeMarkerLayout.barX, y: y, width: ChangeMarkerLayout.barWidth, height: height)
                .fill()
        }
    }

    /// The markers near `rect`: a folded change's bar solid, a disclosed one's hollow over a faint fill, a folded
    /// removal's wedge solid; the marker under the pointer at full strength. A disclosed or hovered bar also draws
    /// subtle separator lines on its own outer edges, and, disclosed with both removed and added rows, where the one
    /// gives way to the other (book D43).
    func drawChangeMarkers(in rect: NSRect) {
        guard let rendered else { return }
        let palette = rendered.palette
        forEachChangeMarker(in: rect) { change, shape in
            let color = palette.changeMarker(for: change.kind)
            let isHovered = change.key == hoveredChange
            let strength: CGFloat = isHovered ? 1 : 0.8
            switch shape {
                case .bar(let bar):
                    let radius = bar.width / 2
                    if change.isDisclosed {
                        color.withAlphaComponent(0.15).setFill()
                        NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()
                        let outline = NSBezierPath(
                            roundedRect: bar.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
                        outline.lineWidth = 1
                        color.withAlphaComponent(strength).setStroke()
                        outline.stroke()
                    } else {
                        color.withAlphaComponent(strength).setFill()
                        NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()
                    }
                    drawChangeSeparators(for: change, bar: bar, isHovered: isHovered, lineHeight: rendered.lineHeight)
                case .wedge(let wedge):
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: wedge.minX, y: wedge.minY))
                    path.line(to: NSPoint(x: wedge.maxX, y: wedge.midY))
                    path.line(to: NSPoint(x: wedge.minX, y: wedge.maxY))
                    path.close()
                    color.withAlphaComponent(strength).setFill()
                    path.fill()
            }
        }
    }

    /// Subtle separator lines on `bar`, cut in the gutter's own background (book D43): the change's outer edges,
    /// drawn once it is disclosed or hovered, and, disclosed with both removed and added rows, the seam where the one
    /// gives way to the other, at `change.removedLines` row heights down from the bar's top, since a change's own
    /// rows share one height.
    private func drawChangeSeparators(for change: RenderedChange, bar: CGRect, isHovered: Bool, lineHeight: CGFloat) {
        guard change.isDisclosed || isHovered else { return }
        let seam = palette.background.withAlphaComponent(0.6)
        seam.setFill()
        NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: 1).fill()
        NSRect(x: bar.minX, y: max(bar.maxY - 1, bar.minY), width: bar.width, height: 1).fill()
        guard change.isDisclosed, change.removedLines > 0, change.addedLines > 0 else { return }
        let boundary = bar.minY + CGFloat(change.removedLines) * lineHeight
        NSRect(x: bar.minX, y: boundary, width: bar.width, height: 1).fill()
    }
}

/// A change marker as VoiceOver finds it (book DIFF-04): a button named for its change, which a press discloses or
/// folds.
@MainActor
final class ChangeMarkerElement: NSAccessibilityElement {
    let key: ChangeKey
    private nonisolated let action: @MainActor @Sendable () -> Void

    init(change: RenderedChange, frame: NSRect, parent: NSView, action: @escaping @MainActor @Sendable () -> Void) {
        key = change.key
        self.action = action
        super.init()
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.label(of: change))
        setAccessibilityHelp(change.isDisclosed ? "Hides the change" : "Shows the change in place")
        setAccessibilityParent(parent)
        setAccessibilityFrameInParentSpace(frame)
    }

    /// AppKit declares the press nonisolated but sends it on the main thread, where the action runs.
    override func accessibilityPerformPress() -> Bool {
        let action = self.action
        MainActor.assumeIsolated { action() }
        return true
    }

    /// The change and whether it shows: "Modified, 2 lines removed, 3 added, hidden".
    static func label(of change: RenderedChange) -> String {
        func lines(_ count: Int) -> String { "\(count) \(count == 1 ? "line" : "lines")" }
        let what =
            switch change.kind {
                case .added: "Added, \(lines(change.addedLines))"
                case .removed: "Removed, \(lines(change.removedLines))"
                case .modified: "Modified, \(lines(change.removedLines)) removed, \(change.addedLines) added"
            }
        return "\(what), \(change.isDisclosed ? "shown" : "hidden")"
    }
}
