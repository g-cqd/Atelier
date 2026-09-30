package import AppKit
import DiffRendering

/// Follows the pointer over a pane's text and has its gutter outline the scope of the row under it (DIFF-03), as a
/// pointer over the gutter does; carries the pane's folding commands out on the insertion point's row, and unfolds a
/// fold whose `•••` is clicked.
@MainActor
package final class ScopeHoverTracker: NSObject {
    private weak var textView: NSTextView?
    private weak var gutter: DiffGutterView?
    private var trackingArea: NSTrackingArea?
    private var click: NSClickGestureRecognizer?

    /// Starts following the pointer over `textView` for `gutter`, which shows the same text.
    package func attach(to textView: NSTextView, gutter: DiffGutterView) {
        detach()
        self.textView = textView
        self.gutter = gutter
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil)
        textView.addTrackingArea(area)
        trackingArea = area
        (textView as? DiffPaneTextView)?.onFoldCommand = { [weak self] command in self?.perform(command) ?? false }
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked(_:)))
        // The text keeps its own clicks, selection included.
        click.delaysPrimaryMouseButtonEvents = false
        textView.addGestureRecognizer(click)
        self.click = click
    }

    package func detach() {
        if let trackingArea, let textView { textView.removeTrackingArea(trackingArea) }
        if let click, let textView { textView.removeGestureRecognizer(click) }
        (textView as? DiffPaneTextView)?.onFoldCommand = nil
        trackingArea = nil
        click = nil
        textView = nil
        gutter = nil
    }

    /// `NSTrackingArea` calls its owner by selector: the selectors are pinned, as `DocHoverController`'s are.
    @objc(mouseMoved:) package func mouseMoved(with event: NSEvent) {
        guard let textView else { return }
        pointerMoved(to: textView.convert(event.locationInWindow, from: nil))
    }

    @objc(mouseEntered:) package func mouseEntered(with event: NSEvent) {}

    @objc(mouseExited:) package func mouseExited(with event: NSEvent) {
        gutter?.hoverScope(atRow: nil)
    }

    /// The testable core of ``mouseMoved(with:)``: outlines the scope of the row under `point`, in the text view's
    /// coordinates, or none past the text.
    package func pointerMoved(to point: NSPoint) {
        gutter?.hoverScope(atRow: row(at: point))
    }

    /// Carries `command` out on the row of the insertion point, or of the selection's start.
    package func perform(_ command: ScopeFoldCommand) -> Bool {
        guard let textView, let gutter, let rendered = gutter.rendered, !rendered.rows.isEmpty else { return false }
        return gutter.perform(command, atRow: rendered.rowIndex(containing: textView.selectedRange().location))
    }

    @objc private func clicked(_ recognizer: NSClickGestureRecognizer) {
        guard let textView else { return }
        unfoldMarker(at: recognizer.location(in: textView))
    }

    /// The testable core of a click: unfolds the fold whose `•••` lies under `point`, in the text view's coordinates.
    @discardableResult
    package func unfoldMarker(at point: NSPoint) -> Bool {
        guard let textView, let gutter, let rendered = gutter.rendered, !rendered.folds.isEmpty else { return false }
        let offset = textView.characterIndexForInsertion(at: point)
        guard let fold = rendered.folds.first(where: { $0.marker.contains(offset) || $0.marker.upperBound == offset })
        else { return false }
        gutter.onScopeFold?(.unfold([fold.key]))
        return true
    }

    /// The row whose fragment lies under `point`.
    private func row(at point: NSPoint) -> Int? {
        guard let textView, let rendered = gutter?.rendered, let layoutManager = textView.textLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return nil }
        let origin = textView.textContainerOrigin
        let inContainer = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        guard let fragment = layoutManager.textLayoutFragment(for: inContainer),
            inContainer.y < fragment.layoutFragmentFrame.maxY
        else { return nil }
        let offset = contentManager.offset(
            from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
        return rendered.rowIndex(containing: offset)
    }
}
