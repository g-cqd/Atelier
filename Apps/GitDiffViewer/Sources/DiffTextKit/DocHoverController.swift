package import AemiCore
package import AppKit
package import DiffRendering
import Foundation

/// Debounces pointer movement over a diff pane into a single documentation lookup, and shows the result in a
/// rich hover panel anchored to the hovered identifier. At most one ``resolve`` call is in flight at a time, and a
/// superseded one never shows its result.
///
/// The panel follows its identifier through every scroll view above the pane, the pane's own and, for a card pane,
/// the card list's, and closes once the identifier leaves the visible area (HOVER-09).
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
        followEnclosingClipViews()
    }

    /// Removes the tracking area and observers from the previously attached view, if any, and closes any open
    /// panel.
    package func detach() {
        invalidate()
        if let trackingArea, let textView {
            textView.removeTrackingArea(trackingArea)
        }
        stopFollowingClipViews()
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

    /// Every clip view above the text view, innermost first, as last followed.
    private var followedClipViews: [ObjectIdentifier] = []
    /// Each followed clip view's origin as last acted on, so a bounds change without a scroll is a no-op.
    private var scrollOrigins: [ObjectIdentifier: NSPoint] = [:]

    /// Follows the bounds of every clip view above the text view: a card pane scrolls sideways in its own scroll
    /// view and up and down with the card list's, which a card joins only once it is in the list, so the chain is
    /// looked up again on every move.
    private func followEnclosingClipViews() {
        guard let textView else { return }
        let clipViews = sequence(first: textView as NSView, next: \.superview).compactMap { $0 as? NSClipView }
        let identifiers = clipViews.map(ObjectIdentifier.init)
        guard identifiers != followedClipViews else { return }
        stopFollowingClipViews()
        followedClipViews = identifiers
        for clipView in clipViews {
            clipView.postsBoundsChangedNotifications = true
            scrollOrigins[ObjectIdentifier(clipView)] = clipView.bounds.origin
            NotificationCenter.default.addObserver(
                self, selector: #selector(clipViewBoundsDidChange(_:)), name: NSView.boundsDidChangeNotification,
                object: clipView)
        }
    }

    private func stopFollowingClipViews() {
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        followedClipViews = []
        scrollOrigins = [:]
    }

    /// Keeps the panel on its identifier as any clip view above the pane scrolls, re-measured from
    /// ``HoverHit/identifierRange``, and closes it once the identifier leaves the visible rect; a scroll before the
    /// panel shows drops the hover, whose identifier has moved from under the pointer.
    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView else { return }
        let key = ObjectIdentifier(clipView)
        guard scrollOrigins[key] != clipView.bounds.origin else { return }
        scrollOrigins[key] = clipView.bounds.origin
        guard panel.isVisible, let shownHit, let textView else {
            invalidate()
            return
        }
        let anchorRect = HoverHitTester.anchorRect(for: shownHit.identifierRange, textView: textView)
        switch HoverScrollResponse(anchorRect: anchorRect, visibleRect: textView.visibleRect) {
            case .stay: break
            case .follow(let anchorRect): panel.reposition(anchorRect: anchorRect, in: textView)
            case .close: invalidate()
        }
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
        followEnclosingClipViews()
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
        panel.show(document: document, anchorRect: hit.anchorRect, in: textView)
    }

    private func closePanel() {
        panel.close()
        shownHit = nil
    }
}

/// What a scroll does to a shown hover panel: it follows its identifier while any of it is visible and closes once
/// none is, as the requirement asks in both the single-file view and the card list (HOVER-09).
package enum HoverScrollResponse: Equatable {
    /// The identifier could not be measured, as in a pane laid out lazily; the panel stays where it is.
    case stay
    /// The identifier is still in view, at this rect in the text view's coordinates.
    case follow(NSRect)
    /// The identifier has left the view.
    case close

    /// - Parameters:
    ///   - anchorRect: The identifier's rect as measured after the scroll, in the text view's coordinates; nil when
    ///     it could not be measured.
    ///   - visibleRect: The part of the text view its scroll views and clips leave visible.
    package init(anchorRect: NSRect?, visibleRect: NSRect) {
        guard let anchorRect else {
            self = .stay
            return
        }
        self = visibleRect.intersects(anchorRect) ? .follow(anchorRect) : .close
    }
}
