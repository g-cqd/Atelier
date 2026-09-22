package import AemiCore
package import AppKit
package import DiffRendering
import Foundation

/// Debounces pointer movement over a diff pane into a single documentation lookup, and shows the result in a
/// rich hover panel anchored to the hovered identifier.
///
/// Resolution is single-flight by construction: a new hit chains behind whatever resolution is already running
/// (sleeping or awaiting the resolver), so at most one call to ``resolve`` is ever in flight, and a stale one
/// that finishes late is discarded by a generation check before it can show anything.
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
    /// The hit the controller is currently tracking, whether its content is still loading or already shown.
    /// Repeated moves over the same identifier are no-ops as long as this stays set.
    private var currentHit: HoverHit?
    private var shownHit: HoverHit?
    private let panel = HoverDocPanel()

    /// Whether the documentation panel is currently on screen; for tests only.
    package var isPanelVisible: Bool { panel.isVisible }
    /// Kept alongside ``isPanelVisible`` for callers (and tests) still written against the popover-era name.
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
    /// popover.
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

    /// The clip view origin last acted on, so a bounds-changed notification that fires without an actual scroll
    /// (tracking-area churn, the panel's own child-window attach nudging layout) is a cheap no-op rather than a
    /// spurious recompute that can race the fragment ``HoverHitTester`` needs.
    private var lastScrollOrigin: NSPoint?

    /// Tracks the panel to its shown identifier as the clip view scrolls, rather than closing outright: a
    /// scroll-to-dismiss felt like a bug to users reading a doc panel while scrolling the pane under it. Recomputes
    /// the identifier's current on-screen rect from its document-absolute ``HoverHit/identifierRange`` (the
    /// row/column pair alone is not enough once ``NSTextLayoutManager``'s own viewport-based layout has discarded
    /// the fragment the original ``HoverHit/anchorRect`` was measured from); closes only when that recompute
    /// *succeeds* and lands outside the text view's own visible rect.
    ///
    /// A recompute that comes back `nil` is not itself grounds to close: a detached-storage pane (``EmbeddedDiffTextView``'s
    /// own ``StaticTextLayout``, laid out lazily against its own viewport) can fail to resolve a fragment for a
    /// range `NSTextLayoutManager` has not been asked to ensure yet, even though the identifier is still right
    /// there on screen -- closing a panel the user is still reading on a transient layout miss reads as a bug
    /// worse than the one this scroll-follow path fixed. The panel simply stays where it last was until a
    /// recompute either succeeds or the caller detaches/invalidates for some other reason.
    ///
    /// One `setFrameOrigin` per genuine scroll notification is cheap enough that no debounce or `CADisplayLink`
    /// coalescing is worth the complexity; revisit only if this is ever visibly janky.
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

    /// `NSTrackingArea` sends these directly to their owner by selector, not through the responder chain, so this
    /// need not subclass `NSResponder`. The explicit `@objc(...)` names are load-bearing: `DocHoverController` is
    /// a plain `NSObject`, not an `NSResponder` override, so Swift's default selector synthesis for a
    /// `with:`-labelled method produces `mouseMovedWith:` (etc), not the fixed `mouseMoved:` Cocoa's tracking-area
    /// dispatch actually sends -- silently losing every hover event to an "unrecognized selector" AppKit log
    /// rather than a crash, since `NSTrackingArea` dispatch degrades to a no-op when the owner does not respond.
    @objc(mouseMoved:) package func mouseMoved(with event: NSEvent) {
        guard let textView else { return }
        pointerMoved(to: textView.convert(event.locationInWindow, from: nil))
    }

    /// No-op: nothing shows until the pointer actually rests on an identifier, which `mouseMoved` alone detects.
    @objc(mouseEntered:) package func mouseEntered(with event: NSEvent) {}

    @objc(mouseExited:) package func mouseExited(with event: NSEvent) {
        // A move into the panel itself also fires this: the panel's own tracking area reports whether the
        // pointer actually landed there, so leaving for the panel (to click a link, or select its text) does not
        // dismiss what the pointer just entered.
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
            // Chaining behind the previous task, cancelled or not, keeps resolution single-flight: this task
            // never calls `resolve` while an earlier one still might be.
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
