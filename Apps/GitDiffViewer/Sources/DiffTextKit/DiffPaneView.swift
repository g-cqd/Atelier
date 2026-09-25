package import AppKit

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
