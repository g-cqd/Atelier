import AppKit
import DiffCore
import DiffRendering

/// A scope under the pointer (DIFF-03): the side whose scope it is, and its index among that side's scopes.
struct HoveredScope: Equatable {
    let isOld: Bool
    let index: Int
}

/// One row the ribbon samples to draw its capsules (book D43): its index, its own top and bottom in the gutter, and
/// how deeply it nests.
private struct RibbonRow {
    let rowIndex: Int
    let top: CGFloat
    let bottom: CGFloat
    let depth: Int
}

/// The scope ribbon in the gutter's trailing padding (DIFF-03, D43, `scope-ribbon-design.md`): capsule segments with
/// rounded ends, no stroke, each nested scope shaded darker than the one holding it, and the scope under the pointer
/// outlined with a light stroke, its braces lit in the text. It is drawn from the pane's decorations as the gutter
/// draws, so scopes that land lay nothing out.
extension DiffGutterView {
    /// The numbers to the gutter's trailing hairline: nothing beyond the hairline's own gap when the ribbon is off,
    /// so the gutter reclaims the ribbon's width (book D43, "the gutter's width follows what it shows"); otherwise 2
    /// pt of air, the ribbon, and 2 pt more to the hairline.
    var trailingPadding: CGFloat { Self.ribbonTrailingGap + (showsScopeRibbon ? Self.ribbonGap + Self.ribbonWidth : 0) }
    static let ribbonWidth: CGFloat = 8
    /// Air between the numbers and the ribbon.
    private static let ribbonGap: CGFloat = 2
    /// Past the ribbon, to the gutter's trailing hairline.
    private static let ribbonTrailingGap: CGFloat = 2
    /// How many levels of nesting the shading tells apart, and how much of the text colour each adds.
    static let ribbonLevels = 4
    static let ribbonLevelAlpha: CGFloat = 0.05
    /// The hovered scope's stroke: mostly white, with enough of the text colour blended in that it still shows
    /// against a light, barely shaded gutter background, so it sets the scope apart from its neighbours whichever
    /// appearance is active, not only a dark one (book D43).
    var hoverStrokeColor: NSColor {
        (NSColor.white.blended(withFraction: 0.25, of: palette.textColor) ?? .white).withAlphaComponent(0.7)
    }

    /// The ribbon's leading edge, before the gutter's trailing hairline; the hairline's own edge when the ribbon is
    /// off, since nothing draws left of it then.
    var ribbonX: CGFloat { bounds.width - Self.ribbonTrailingGap - (showsScopeRibbon ? Self.ribbonWidth : 0) }

    /// The decorations of the text on show; nil while none has landed.
    private var currentDecorations: DiffDecorations? {
        rendered.flatMap { decorations?.decorations(for: $0) }
    }

    /// Each scope near `rect` as a capsule spanning its rows, shaded by how deeply it nests: a scope inside another
    /// draws over it, darker, so the two read as nested pills, the outer one's rounded ends showing past the inner's
    /// (book D43). A row outside every scope, or whose side has no scopes yet, draws at no level. No stroke at rest;
    /// only the hovered scope gets one, in ``drawHoveredScope(in:)``.
    /// - Complexity: O(rows in `rect` × ``ribbonLevels``)
    func drawRibbon(in rect: NSRect) {
        guard let rendered, let decorations = currentDecorations else { return }
        // A line's margin either side tells a run that starts or ends at the sample's own edge from one that merely
        // continues past it, so only a confirmed boundary draws a rounded cap.
        var rows: [RibbonRow] = []
        forEachFragment(in: rect.insetBy(dx: 0, dy: -rendered.lineHeight)) { fragment, row, rowIndex, y in
            let height = fragment.layoutFragmentFrame.height - rendered.bandSpacing(afterRow: rowIndex)
            let depth: Int
            if let found = decorations.scopeLine(of: row, on: rendered.side) {
                depth = min(found.scopes.depth(ofLine: found.line), Self.ribbonLevels)
            } else {
                depth = 0
            }
            rows.append(RibbonRow(rowIndex: rowIndex, top: y, bottom: y + height, depth: depth))
        }
        guard !rows.isEmpty else { return }
        for level in 1 ... Self.ribbonLevels {
            var start: Int?
            for index in rows.indices {
                let inRun = rows[index].depth >= level
                if inRun, start == nil { start = index }
                if !inRun, let begin = start {
                    drawCapsule(rows[begin ..< index], of: rows.count, level: level)
                    start = nil
                }
            }
            if let begin = start { drawCapsule(rows[begin...], of: rows.count, level: level) }
        }
    }

    /// One depth level's capsule over `run`, of the `total` rows sampled with a line's margin either side of what
    /// shows: rounded on an edge the sample confirms is the scope's own — the row beyond it falls short of `level`, or
    /// the run reaches the text's first or last row — left open on an edge the sample only runs into, so its curve
    /// never shows within the drawn rect.
    private func drawCapsule(_ run: ArraySlice<RibbonRow>, of total: Int, level: Int) {
        guard let first = run.first, let last = run.last else { return }
        let overrun = Self.ribbonWidth * 2
        let topConfirmed = run.startIndex > 0 || first.rowIndex == 0
        let bottomConfirmed = run.endIndex < total || last.rowIndex == (rendered?.rows.count ?? 0) - 1
        let top = topConfirmed ? first.top : first.top - overrun
        let bottom = bottomConfirmed ? last.bottom : last.bottom + overrun
        let capsule = NSRect(x: ribbonX, y: top, width: Self.ribbonWidth, height: bottom - top)
        palette.textColor.withAlphaComponent(Self.ribbonLevelAlpha * CGFloat(level)).setFill()
        NSBezierPath(roundedRect: capsule, xRadius: Self.ribbonWidth / 2, yRadius: Self.ribbonWidth / 2).fill()
    }

    /// The row whose own height, less a band after it, holds `point`; nil over a band or past the text.
    func rowIndex(at point: NSPoint) -> Int? {
        guard point.x >= 0, point.x < bounds.width else { return nil }
        var found: Int?
        forEachFragment(in: NSRect(x: 0, y: point.y, width: 1, height: 1)) { fragment, _, rowIndex, y in
            let height = fragment.layoutFragmentFrame.height - (rendered?.bandSpacing(afterRow: rowIndex) ?? 0)
            if point.y >= y, point.y < y + height { found = rowIndex }
        }
        return found
    }

    /// The innermost scope holding the source line `rowIndex` shows; nil when none does, or no scope has landed.
    func scope(atRow rowIndex: Int) -> HoveredScope? {
        guard let rendered, rendered.rows.indices.contains(rowIndex), let decorations = currentDecorations,
            let found = decorations.scopeLine(of: rendered.rows[rowIndex], on: rendered.side),
            let index = found.scopes.innermostScope(atLine: found.line)
        else { return nil }
        return HoveredScope(isOld: found.isOld, index: index)
    }

    /// Outlines the scope holding `rowIndex`'s line, as a pointer over that row in the text does; nil outlines none.
    package func hoverScope(atRow rowIndex: Int?) {
        setHoveredScope(rowIndex.flatMap(scope(atRow:)))
    }

    /// Outlines `scope` in the ribbon and lights its braces in the text, putting out the ones lit before.
    func setHoveredScope(_ scope: HoveredScope?) {
        guard scope != hoveredScope else { return }
        hoveredScope = scope
        needsDisplay = true
        // The capsule's ends take a pointing hand.
        window?.invalidateCursorRects(for: self)
        decorationStore?.highlightBraces(at: scope.flatMap(braceOffsets(of:)) ?? [])
    }

    /// The hovered scope, the rows of its first and last lines, and the scope itself.
    func hoveredRows() -> (first: Int, last: Int, scope: ScopeLines.Scope)? {
        guard let hoveredScope, let rendered, let decorations = currentDecorations,
            let scopes = (hoveredScope.isOld ? decorations.old : decorations.new).scopes,
            scopes.scopes.indices.contains(hoveredScope.index)
        else { return nil }
        let scope = scopes.scopes[hoveredScope.index]
        guard let first = rendered.rowIndex(ofLine: scope.lines.lowerBound, old: hoveredScope.isOld),
            let last = rendered.rowIndex(ofLine: scope.lines.upperBound, old: hoveredScope.isOld)
        else { return nil }
        return (first, last, scope)
    }

    /// Where the braces of `scope` lie in the text on show, in UTF-16 offsets.
    private func braceOffsets(of scope: HoveredScope) -> [Int]? {
        guard scope == hoveredScope, let rendered, let rows = hoveredRows() else { return nil }
        return [
            rendered.lineStarts[rows.first] + rows.scope.openColumn,
            rendered.lineStarts[rows.last] + rows.scope.closeColumn
        ]
    }

    /// The hovered scope outlined over the ribbon, from its first row to its last, with a `⌄` on the first and a `⌃`
    /// on the last: a light stroke only, so its own depth shading stays and the stroke alone sets it apart from its
    /// neighbours (book D43; no stroke otherwise).
    func drawHoveredScope(in rect: NSRect) {
        guard let rendered, let rows = hoveredRows() else { return }
        var edges: [Int: (top: CGFloat, bottom: CGFloat)] = [:]
        forEachFragment(in: rect) { fragment, _, rowIndex, y in
            guard rowIndex >= rows.first, rowIndex <= rows.last else { return }
            edges[rowIndex] = (y, y + fragment.layoutFragmentFrame.height - rendered.bandSpacing(afterRow: rowIndex))
        }
        guard !edges.isEmpty else { return }
        // An end out of `rect` runs on past its edge, so its round end is not drawn there.
        let overrun = rect.insetBy(dx: 0, dy: -Self.ribbonWidth * 2)
        let top = edges[rows.first]?.top ?? overrun.minY
        let bottom = edges[rows.last]?.bottom ?? overrun.maxY
        let capsule = NSRect(x: ribbonX, y: top, width: Self.ribbonWidth, height: bottom - top)
            .insetBy(dx: 0.5, dy: 0.5)
        let radius = capsule.width / 2
        let outline = NSBezierPath(roundedRect: capsule, xRadius: radius, yRadius: radius)
        outline.lineWidth = 1
        hoverStrokeColor.setStroke()
        outline.stroke()
        if let first = edges[rows.first] { drawChevron(pointingDown: true, in: first) }
        if let last = edges[rows.last] { drawChevron(pointingDown: false, in: last) }
    }

    /// A small chevron centred on the ribbon in a row running from `edge.top` to `edge.bottom`, in the hovered
    /// scope's own stroke.
    private func drawChevron(pointingDown: Bool, in edge: (top: CGFloat, bottom: CGFloat)) {
        let midX = ribbonX + Self.ribbonWidth / 2
        let midY = min((edge.top + edge.bottom) / 2, edge.top + (rendered?.lineHeight ?? 0) / 2)
        let half: CGFloat = 1.5
        let rise: CGFloat = pointingDown ? -0.75 : 0.75
        let path = NSBezierPath()
        path.move(to: NSPoint(x: midX - half, y: midY + rise))
        path.line(to: NSPoint(x: midX, y: midY - rise))
        path.line(to: NSPoint(x: midX + half, y: midY + rise))
        path.lineWidth = 1
        path.lineCapStyle = .round
        hoverStrokeColor.setStroke()
        path.stroke()
    }
}
