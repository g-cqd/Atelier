package import AemiCore
package import AppKit
package import DiffRendering
import Foundation

/// Debounces pointer movement over a diff pane into a single documentation lookup, and shows the result in a
/// rich hover panel anchored to the hovered identifier. At most one ``resolve`` call is in flight at a time, and a
/// superseded one never shows its result.
@MainActor
package final class DocHoverController: NSObject {
    package var isEnabled = true {
        didSet {
            guard !isEnabled else { return }
            invalidate()
        }
    }

    /// Resolves structured, colored documentation for a hit; `nil` means nothing to show.
    package var resolve: (@Sendable (HoverHit) async -> HoverDocument?)?
    package let debounce: Duration

    private let clock: any Clock<Duration>
    private let taskProvider: any TaskProvider
    private weak var textView: NSTextView?
    private var renderedProvider: (@MainActor () -> RenderedText?)?
    private var trackingArea: NSTrackingArea?
    private var generation = 0
    private var pendingTask: Task<Void, Never>?
    /// The hit being tracked, loading or shown; a move to the same row and column is a no-op while it is set.
    private var currentHit: HoverHit?
    private var shownHit: HoverHit?
    private let panel = HoverDocPanel()

    /// Whether the documentation panel is currently on screen; for tests only.
    package var isPanelVisible: Bool { panel.isVisible }
    /// The same as ``isPanelVisible``.
    package var isPopoverVisible: Bool { isPanelVisible }

    package init(
        clock: any Clock<Duration> = ContinuousClock(), taskProvider: any TaskProvider = .default,
        debounce: Duration = .milliseconds(300)
    ) {
        self.clock = clock
        self.taskProvider = taskProvider
        self.debounce = debounce
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Tracks pointer movement over `textView` and resolves hover content against whatever `rendered` currently
    /// shows. Detaches from any previously attached view first.
    package func attach(to textView: NSTextView, rendered: @escaping @MainActor () -> RenderedText?) {
        detach()
        self.textView = textView
        renderedProvider = rendered
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self,
            userInfo: nil)
        textView.addTrackingArea(area)
        trackingArea = area
        if let clipView = textView.enclosingScrollView?.contentView {
            clipView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrollViewBoundsDidChange(_:)), name: NSView.boundsDidChangeNotification,
                object: clipView)
        }
    }

    /// Removes the tracking area and observer from the previously attached view, if any, and closes any open
    /// panel.
    package func detach() {
        invalidate()
        if let trackingArea, let textView {
            textView.removeTrackingArea(trackingArea)
        }
        if let clipView = textView?.enclosingScrollView?.contentView {
            NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: clipView)
        }
        trackingArea = nil
        textView = nil
        renderedProvider = nil
    }

    /// Cancels any in-flight resolution and closes the panel, without detaching from the text view.
    package func invalidate() {
        generation += 1
        pendingTask?.cancel()
        pendingTask = nil
        currentHit = nil
        closePanel()
    }

    /// The clip view origin last acted on, so a bounds change without a scroll is a no-op.
    private var lastScrollOrigin: NSPoint?

    /// Keeps the panel on its identifier as the clip view scrolls, re-measured from ``HoverHit/identifierRange``,
    /// and closes it once the identifier leaves the visible rect. A failed re-measure leaves the panel in place: a
    /// lazily laid out pane can miss a fragment that is still on screen.
    @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
        guard panel.isVisible, let shownHit, let textView else {
            invalidate()
            return
        }
        if let clipView = notification.object as? NSClipView {
            let origin = clipView.bounds.origin
            guard lastScrollOrigin != origin else { return }
            lastScrollOrigin = origin
        }
        guard let anchorRect = HoverHitTester.anchorRect(for: shownHit.identifierRange, textView: textView) else {
            return
        }
        guard textView.visibleRect.intersects(anchorRect) else {
            invalidate()
            return
        }
        panel.reposition(anchorRect: anchorRect, in: textView)
    }

    /// `NSTrackingArea` calls its owner by selector, and Swift would name this `mouseMovedWith:`, so the selectors
    /// are pinned; a mismatch silently drops every event.
    @objc(mouseMoved:) package func mouseMoved(with event: NSEvent) {
        guard let textView else { return }
        pointerMoved(to: textView.convert(event.locationInWindow, from: nil))
    }

    /// No-op: nothing shows until the pointer actually rests on an identifier, which `mouseMoved` alone detects.
    @objc(mouseEntered:) package func mouseEntered(with event: NSEvent) {}

    @objc(mouseExited:) package func mouseExited(with event: NSEvent) {
        // Leaving the pane for the panel keeps the panel open.
        guard !panel.pointerIsInside else { return }
        invalidate()
    }

    /// The testable core of ``mouseMoved(with:)``: hit-tests `point`, in the attached text view's own coordinate
    /// space, and schedules (or reuses, or cancels) a hover resolution.
    package func pointerMoved(to point: NSPoint) {
        guard isEnabled, let resolve, let textView, let rendered = renderedProvider?() else {
            invalidate()
            return
        }
        guard let hit = HoverHitTester.hit(at: point, textView: textView, rendered: rendered) else {
            invalidate()
            return
        }
        if let currentHit, currentHit.row == hit.row, currentHit.utf16Column == hit.utf16Column {
            return
        }
        if let shownHit, !shownHit.anchorRect.contains(point) {
            closePanel()
        }
        generation += 1
        let myGeneration = generation
        let previous = pendingTask
        pendingTask?.cancel()
        currentHit = hit
        pendingTask = taskProvider.task { [weak self, clock, debounce] in
            // Waiting for the previous task, cancelled or not, keeps resolution single-flight.
            await previous?.value
            guard let self, self.generation == myGeneration, !Task.isCancelled else { return }
            try? await clock.sleep(for: debounce)
            guard self.generation == myGeneration, !Task.isCancelled else { return }
            guard let document = await resolve(hit) else { return }
            guard self.generation == myGeneration else { return }
            self.show(document: document, for: hit)
        }
    }

    private func show(document: HoverDocument, for hit: HoverHit) {
        guard let textView else { return }
        shownHit = hit
        lastScrollOrigin = textView.enclosingScrollView?.contentView.bounds.origin
        panel.show(document: document, anchorRect: hit.anchorRect, in: textView)
    }

    private func closePanel() {
        panel.close()
        shownHit = nil
        lastScrollOrigin = nil
    }
}
