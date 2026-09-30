import AppKit
import DiffCore
import DiffRendering

/// The compact inline view's change markers in the gutter (book DIFF-04; `compact-inline-design.md`): drawn over the
/// rows, in the leading padding, clicked to disclose or fold their change.
extension DiffGutterView {
    /// Visits the markers of the changes near the rows intersecting `rect` of this view, each with its shape.
    ///
    /// A bar runs from its first row's top to its last row's own bottom, less the band of a gap after it; a bar that
    /// runs out of `rect` runs on well past its edge, so its round end is not drawn there. A folded removal's wedge
    /// sits across its boundary, below it at the top of the text or under a band, and above it at the end.
    /// - Complexity: O(rows in `rect` + log changes + changes returned), plus a lookup of the first fragment.
    func forEachChangeMarker(in rect: NSRect, _ body: (RenderedChange, ChangeMarkerLayout.Shape) -> Void) {
        guard let rendered, !rendered.changes.isEmpty else { return }
        var edges: [Int: (top: CGFloat, bottom: CGFloat)] = [:]
        // A wedge reaches half its height past its boundary: look a row further.
        forEachFragment(in: rect.insetBy(dx: 0, dy: -rendered.lineHeight)) { fragment, _, rowIndex, y in
            let height = fragment.layoutFragmentFrame.height - rendered.bandSpacing(afterRow: rowIndex)
            edges[rowIndex] = (y, y + height)
        }
        guard let first = edges.keys.min(), let last = edges.keys.max() else { return }
        let overrun = rect.insetBy(dx: 0, dy: -2 * ChangeMarkerLayout.barWidth)
        for change in rendered.changes(on: first ... (last + 1)) {
            if change.rows.isEmpty {
                guard let wedge = wedge(at: change.rows.lowerBound, edges: edges, in: rendered) else { continue }
                body(change, .wedge(wedge))
            } else {
                let top = edges[change.rows.lowerBound]?.top ?? overrun.minY
                let bottom = edges[change.rows.upperBound - 1]?.bottom ?? overrun.maxY
                let isHovered = change.key == hoveredChange
                body(change, .bar(ChangeMarkerLayout.bar(top: top, bottom: bottom, isHovered: isHovered)))
            }
        }
    }

    /// The wedge of a folded removal on `boundary`, from the edges of the rows around it; nil unless they are known.
    private func wedge(at boundary: Int, edges: [Int: (top: CGFloat, bottom: CGFloat)], in rendered: RenderedText)
        -> CGRect?
    {
        if boundary == 0 {
            return edges[0].map { ChangeMarkerLayout.wedge(at: $0.top, placement: .below) }
        }
        if boundary >= rendered.rows.count {
            return edges[boundary - 1].map { ChangeMarkerLayout.wedge(at: $0.bottom, placement: .above) }
        }
        guard let below = edges[boundary] else { return nil }
        // Where a gap's band lies on the boundary, with no context lines, the wedge keeps clear of its handle.
        let underBand = rendered.bandedGap(afterRow: boundary - 1) != nil
        return ChangeMarkerLayout.wedge(at: below.top, placement: underBand ? .below : .centred)
    }

    /// The change whose marker takes the pointer at `point`.
    func changeMarker(at point: NSPoint) -> RenderedChange? {
        guard point.x >= 0, point.x < ChangeMarkerLayout.hitWidth, let rendered else { return nil }
        var found: RenderedChange?
        forEachChangeMarker(in: NSRect(x: 0, y: point.y, width: 1, height: 1)) { change, shape in
            guard found == nil,
                ChangeMarkerLayout.hitArea(of: shape, lineHeight: rendered.lineHeight).contains(point)
            else { return }
            found = change
        }
        return found
    }

    /// The markers in view as buttons for VoiceOver: each names its change and whether it shows, and a press
    /// discloses or folds it, as a click does.
    func changeMarkerElements() -> [ChangeMarkerElement] {
        guard let rendered else { return [] }
        var elements: [ChangeMarkerElement] = []
        forEachChangeMarker(in: unobscuredRect(of: visibleRect)) { change, shape in
            let frame = ChangeMarkerLayout.hitArea(of: shape, lineHeight: rendered.lineHeight)
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
            addCursorRect(ChangeMarkerLayout.hitArea(of: shape, lineHeight: rendered.lineHeight), cursor: .pointingHand)
        }
    }

    /// Xcode's change bar beside every changed row near `rect`, with the Xcode diff colours (book D18): one solid bar
    /// in the leading padding, where the compact inline view draws its markers instead, down each row's own height, so
    /// that the rows of one change join into one bar and a gap's band breaks it.
    func drawChangeBars(in rect: NSRect) {
        guard let rendered, rendered.changes.isEmpty, let color = rendered.palette.changeBar else { return }
        color.setFill()
        forEachFragment(in: rect) { fragment, row, rowIndex, y in
            guard [.added, .removed, .modified].contains(row.kind) else { return }
            let height = fragment.layoutFragmentFrame.height - rendered.bandSpacing(afterRow: rowIndex)
            NSRect(x: ChangeMarkerLayout.barX, y: y, width: ChangeMarkerLayout.barWidth, height: height).fill()
        }
    }

    /// The markers near `rect`: a folded change's bar solid, a disclosed one's hollow over a faint fill, a folded
    /// removal's wedge solid; the marker under the pointer at full strength.
    func drawChangeMarkers(in rect: NSRect) {
        guard let rendered else { return }
        let palette = rendered.palette
        forEachChangeMarker(in: rect) { change, shape in
            let color = palette.changeMarker(for: change.kind)
            let strength: CGFloat = change.key == hoveredChange ? 1 : 0.8
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
