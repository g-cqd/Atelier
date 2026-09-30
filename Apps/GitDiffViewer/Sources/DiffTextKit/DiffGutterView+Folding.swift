package import AppKit
import DiffCore
package import DiffRendering

/// A folding command, as Xcode's Editor ▸ Code Folding has them (DIFF-03): ⌥⌘← and ⌥⌘→ on the innermost scope around
/// the insertion point, ⌥⌘⇧← on every function shown, and ⌥⌘⇧→ on every fold.
package enum ScopeFoldCommand: Sendable, Equatable {
    case foldInnermost
    case unfoldInnermost
    case foldAll
    case unfoldAll

    /// The command `event` presses; nil for any other key.
    package init?(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard flags.contains([.command, .option]), !flags.contains(.control) else { return nil }
        let all = flags.contains(.shift)
        switch event.keyCode {
            case 123: self = all ? .foldAll : .foldInnermost
            case 124: self = all ? .unfoldAll : .unfoldInnermost
            default: return nil
        }
    }
}

/// Folding from the ribbon (DIFF-03, `scope-ribbon-design.md`): the hovered capsule's `⌄` and `⌃` fold its scope, a
/// folded scope's `›` tab or its band unfolds it, and the pane's folding commands act on the insertion point's row.
extension DiffGutterView {
    /// How far left of the ribbon a click still takes it: the ribbon is narrow.
    private static let ribbonReach: CGFloat = 1

    /// What a click at `point` asks: to unfold the fold whose band it is on, or whose tab it is on in the ribbon, or
    /// to fold the hovered scope when it is on one of the capsule's ends; nil otherwise.
    func foldRequest(at point: NSPoint) -> ScopeFoldRequest? {
        guard let rendered, let row = rowIndex(at: point) else { return nil }
        let inRibbon = point.x >= ribbonX - Self.ribbonReach
        if let fold = rendered.fold(atRow: row), row == fold.bandRow || inRibbon {
            return .unfold([fold.key])
        }
        guard inRibbon, let rows = hoveredRows(), row == rows.first || row == rows.last,
            let hoveredScope, rendered.rows.indices.contains(rows.first)
        else { return nil }
        let key = ScopeFoldKey(
            fileIndex: rendered.rows[rows.first].fileIndex, isOld: hoveredScope.isOld,
            firstLine: rows.scope.lines.lowerBound)
        return .fold([key: rows.scope.lines.upperBound])
    }

    /// What a click at `point` would do, for the tooltip.
    func foldHelp(at point: NSPoint) -> String? {
        switch foldRequest(at: point) {
            case .fold?:
                let kind = hoveredRows().map { Self.name(of: $0.scope.kind) } ?? "block"
                return "Fold the \(kind) (⌥⌘←)"
            case .unfold?: return "Unfold (⌥⌘→)"
            case nil: return nil
        }
    }

    private static func name(of kind: SyntaxScope.Kind) -> String {
        switch kind {
            case .type: "type"
            case .function: "function"
            case .closure: "closure"
            case .controlFlow, .block: "block"
        }
    }

    /// Carries out `command` on the pane's row `row`, the insertion point's: folds or unfolds the innermost scope
    /// around it, folds every function the pane shows, or unfolds every fold. Returns false when it finds nothing to
    /// do, as where no scope is known yet.
    @discardableResult
    package func perform(_ command: ScopeFoldCommand, atRow row: Int?) -> Bool {
        guard let rendered, let request = request(for: command, atRow: row, in: rendered) else { return false }
        onScopeFold?(request)
        return true
    }

    private func request(for command: ScopeFoldCommand, atRow row: Int?, in rendered: RenderedText)
        -> ScopeFoldRequest?
    {
        switch command {
            case .foldInnermost:
                guard let row, let scope = scope(atRow: row), let decorations = currentScopes(isOld: scope.isOld),
                    decorations.scopes.indices.contains(scope.index)
                else { return nil }
                let lines = decorations.scopes[scope.index].lines
                let key = ScopeFoldKey(
                    fileIndex: rendered.rows[row].fileIndex, isOld: scope.isOld, firstLine: lines.lowerBound)
                return .fold([key: lines.upperBound])
            case .unfoldInnermost:
                return row.flatMap(rendered.fold(atRow:)).map { .unfold([$0.key]) }
            case .foldAll:
                let isOld = rendered.side == .old
                guard let scopes = currentScopes(isOld: isOld) else { return nil }
                var folds: [ScopeFoldKey: Int] = [:]
                for scope in scopes.scopes where scope.kind == .function {
                    guard let first = rendered.rowIndex(ofLine: scope.lines.lowerBound, old: isOld) else { continue }
                    let key = ScopeFoldKey(
                        fileIndex: rendered.rows[first].fileIndex, isOld: isOld, firstLine: scope.lines.lowerBound)
                    folds[key] = scope.lines.upperBound
                }
                return folds.isEmpty ? nil : .fold(folds)
            case .unfoldAll:
                return rendered.folds.isEmpty ? nil : .unfold(Set(rendered.folds.map(\.key)))
        }
    }

    /// The scopes of one side of the text on show; nil until they land.
    private func currentScopes(isOld: Bool) -> ScopeLines? {
        guard let rendered, let decorations = decorations?.decorations(for: rendered) else { return nil }
        return (isOld ? decorations.old : decorations.new).scopes
    }

    /// Each fold near `rect`: a dark tab with a `›` on its first row in the ribbon, and on its band, when the rows it
    /// hides hold a change, a dotted change bar in the change layer: a fold never hides that something changed.
    func drawFolds(in rect: NSRect) {
        guard let rendered, !rendered.folds.isEmpty else { return }
        var edges: [Int: (top: CGFloat, bottom: CGFloat)] = [:]
        forEachRow(in: rect) { frame, _, rowIndex, y, _ in
            edges[rowIndex] = (y, y + frame.height - rendered.bandSpacing(afterRow: rowIndex))
        }
        for fold in rendered.folds {
            if let first = edges[fold.firstRow] { drawTab(in: first) }
            if fold.holdsChange, let band = edges[fold.bandRow] { drawDottedBar(in: band) }
        }
    }

    /// The tab of a folded scope's first row, running from `edge.top` to `edge.bottom`.
    private func drawTab(in edge: (top: CGFloat, bottom: CGFloat)) {
        let height = min(edge.bottom - edge.top, rendered?.lineHeight ?? edge.bottom - edge.top)
        let tab = NSRect(x: ribbonX - 1, y: edge.top + 1, width: Self.ribbonWidth + 2, height: max(height - 2, 1))
        palette.textColor.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: tab, xRadius: 2, yRadius: 2).fill()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: tab.midX - 0.75, y: tab.midY - 1.5))
        path.line(to: NSPoint(x: tab.midX + 0.75, y: tab.midY))
        path.line(to: NSPoint(x: tab.midX - 0.75, y: tab.midY + 1.5))
        path.lineWidth = 1
        path.lineCapStyle = .round
        palette.gutterBackground.setStroke()
        path.stroke()
    }

    /// A dotted change bar down a band, where the change bar or a compact view's marker would run.
    private func drawDottedBar(in edge: (top: CGFloat, bottom: CGFloat)) {
        (palette.changeBar ?? palette.changeMarker(for: .modified)).setFill()
        var y = edge.top + 1
        while y + ChangeMarkerLayout.barWidth <= edge.bottom {
            let size = ChangeMarkerLayout.barWidth
            NSBezierPath(ovalIn: NSRect(x: changeLayerX + ChangeMarkerLayout.barX, y: y, width: size, height: size))
                .fill()
            y += 2 * ChangeMarkerLayout.barWidth
        }
    }

    /// A pointing hand over each fold's tab and band, and over the hovered capsule's ends.
    func addFoldCursorRects() {
        guard let rendered else { return }
        let hovered = hoveredRows()
        forEachRow(in: unobscuredRect(of: visibleRect)) { frame, _, rowIndex, y, _ in
            let height = frame.height - rendered.bandSpacing(afterRow: rowIndex)
            let ribbon = NSRect(
                x: ribbonX - Self.ribbonReach, y: y, width: bounds.width - ribbonX + Self.ribbonReach, height: height)
            if let fold = rendered.fold(atRow: rowIndex) {
                let area = rowIndex == fold.bandRow ? NSRect(x: 0, y: y, width: bounds.width, height: height) : ribbon
                addCursorRect(area, cursor: .pointingHand)
            } else if let hovered, rowIndex == hovered.first || rowIndex == hovered.last {
                addCursorRect(ribbon, cursor: .pointingHand)
            }
        }
    }
}

extension DiffTextView {
    /// This pane with its scopes folded and unfolded through `onScopeFold`, and its ribbon shown or hidden
    /// (DIFF-03).
    package func folding(
        showsRibbon: Bool = true, _ onScopeFold: @escaping (ScopeFoldRequest) -> Void
    ) -> DiffTextView {
        var pane = self
        pane.onScopeFold = onScopeFold
        pane.showsScopeRibbon = showsRibbon
        return pane
    }
}

extension EmbeddedDiffTextView {
    /// This card pane with its scopes folded and unfolded through `onScopeFold`, and its ribbon shown or hidden
    /// (DIFF-03).
    package func folding(
        showsRibbon: Bool = true, _ onScopeFold: @escaping (ScopeFoldRequest) -> Void
    ) -> EmbeddedDiffTextView {
        var pane = self
        pane.onScopeFold = onScopeFold
        pane.showsScopeRibbon = showsRibbon
        return pane
    }
}
