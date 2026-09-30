import AppKit
import DiffCore
import DiffRendering

/// A scope under the pointer (DIFF-03): the side whose scope it is, and its index among that side's scopes.
struct HoveredScope: Equatable {
    let isOld: Bool
    let index: Int
}

/// The scope ribbon in the gutter's trailing padding (DIFF-03, `scope-ribbon-design.md`): each row shaded by how deeply
/// it nests, a hairline where a scope ends, and the scope under the pointer outlined, its braces lit in the text. It is
/// drawn from the pane's decorations as the gutter draws, so scopes that land lay nothing out.
extension DiffGutterView {
    /// The padding after the numbers, which holds the ribbon: 2 pt wider than the leading padding, the ribbon's whole
    /// cost, taken whether or not the text has scopes, so the gutter never changes width when they land.
    static let trailingPadding: CGFloat = 10
    static let ribbonWidth: CGFloat = 5
    /// How many levels of nesting the shading tells apart, and how much of the text colour each adds.
    static let ribbonLevels = 4
    static let ribbonLevelAlpha: CGFloat = 0.05

    /// The ribbon's leading edge: 1 pt before the gutter's trailing hairline.
    var ribbonX: CGFloat { bounds.width - 2 - Self.ribbonWidth }

    /// The decorations of the text on show; nil while none has landed.
    private var currentDecorations: DiffDecorations? {
        rendered.flatMap { decorations?.decorations(for: $0) }
    }

    /// Each row near `rect` shaded by its depth, with a hairline under a row where a scope ends. A row outside every
    /// scope, or whose side has no scopes yet, has none.
    /// - Complexity: O(rows in `rect`)
    func drawRibbon(in rect: NSRect) {
        guard let rendered, let decorations = currentDecorations else { return }
        let color = palette.textColor
        let x = ribbonX
        forEachFragment(in: rect) { fragment, row, rowIndex, y in
            guard let found = decorations.scopeLine(of: row, on: rendered.side) else { return }
            let depth = min(found.scopes.depth(ofLine: found.line), Self.ribbonLevels)
            guard depth > 0 else { return }
            let height = fragment.layoutFragmentFrame.height - rendered.bandSpacing(afterRow: rowIndex)
            color.withAlphaComponent(Self.ribbonLevelAlpha * CGFloat(depth)).setFill()
            NSRect(x: x, y: y, width: Self.ribbonWidth, height: height).fill()
            guard found.scopes.endsScope(atLine: found.line) else { return }
            color.withAlphaComponent(Self.ribbonLevelAlpha * CGFloat(Self.ribbonLevels)).setFill()
            NSRect(x: x, y: y + height - 1, width: Self.ribbonWidth, height: 1).fill()
        }
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
        decorationStore?.highlightBraces(at: scope.flatMap(braceOffsets(of:)) ?? [])
    }

    /// The hovered scope, the rows of its first and last lines, and the scope itself.
    private func hoveredRows() -> (first: Int, last: Int, scope: ScopeLines.Scope)? {
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

    /// The hovered scope as a rounded capsule over the ribbon, from its first row to its last, with a `⌄` on the
    /// first and a `⌃` on the last.
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
        let color = palette.textColor.withAlphaComponent(Self.capsuleAlpha)
        palette.gutterBackground.setFill()
        NSBezierPath(roundedRect: capsule, xRadius: radius, yRadius: radius).fill()
        let outline = NSBezierPath(roundedRect: capsule, xRadius: radius, yRadius: radius)
        outline.lineWidth = 1
        color.setStroke()
        outline.stroke()
        if let first = edges[rows.first] { drawChevron(pointingDown: true, in: first) }
        if let last = edges[rows.last] { drawChevron(pointingDown: false, in: last) }
    }

    /// A gap handle's outline under the pointer: the capsule's.
    static let capsuleAlpha: CGFloat = 0.4

    /// A small chevron centred on the ribbon in a row running from `edge.top` to `edge.bottom`.
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
        palette.textColor.withAlphaComponent(Self.capsuleAlpha).setStroke()
        path.stroke()
    }
}
