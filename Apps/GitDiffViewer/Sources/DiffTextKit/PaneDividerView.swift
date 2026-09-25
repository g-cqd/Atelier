package import AppKit
package import SwiftUI

/// The divider between a file's two panes (book DIFF-01): a separator line, one point thick, in the middle of a strip
/// ``PaneSplit/hitThickness`` across that takes the pointer over the panes' edges and draws nothing else.
///
/// Dragging it reports how far the pointer moved towards the new pane since the button went down; releasing it ends
/// the drag; a double click asks for an even split. It reads events itself rather than through a SwiftUI gesture, so
/// it can drag while its window is inactive, and so it takes the pointer before the text view beneath its edges.
package final class PaneDividerView: NSView {
    /// Whether the panes sit side by side (`.horizontal`) or one above the other (`.vertical`).
    package var axis: Axis = .horizontal {
        didSet {
            guard axis != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    /// Called as the divider is dragged, with how far the pointer has moved towards the new pane since it went down.
    package var onDrag: ((CGFloat) -> Void)?
    /// Called once the button is released after going down on the divider.
    package var onDragEnd: (() -> Void)?
    /// Called on a double click.
    package var onReset: (() -> Void)?

    /// Where in the window the button went down, while a drag lasts.
    private var dragOrigin: NSPoint?

    /// The pointer over the divider and while it is dragged.
    package var cursor: NSCursor { axis == .horizontal ? .columnResize : .rowResize }

    override package var isFlipped: Bool { true }
    override package var isOpaque: Bool { false }
    // It drags the divider, never the window.
    override package var mouseDownCanMoveWindow: Bool { false }

    override package func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override package func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        lineRect.fill()
    }

    /// The line drawn in the middle of the strip.
    package var lineRect: NSRect {
        let thickness = PaneSplit.dividerThickness
        return axis == .horizontal
            ? NSRect(x: (bounds.width - thickness) / 2, y: 0, width: thickness, height: bounds.height)
            : NSRect(x: 0, y: (bounds.height - thickness) / 2, width: bounds.width, height: thickness)
    }

    override package func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override package func mouseDown(with event: NSEvent) {
        guard event.clickCount < 2 else {
            dragOrigin = nil
            onReset?()
            return
        }
        dragOrigin = event.locationInWindow
    }

    override package func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        // The pointer may run ahead of the strip; it keeps the resize cursor until the button is released.
        cursor.set()
        let location = event.locationInWindow
        // Window coordinates grow upwards, and the new pane lies below the old one when stacked.
        onDrag?(axis == .horizontal ? location.x - dragOrigin.x : dragOrigin.y - location.y)
    }

    override package func mouseUp(with event: NSEvent) {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        onDragEnd?()
    }
}
