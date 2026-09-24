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
///
/// It stays open while the pointer is on its way to it or rests over it, so it can be read and scrolled (HOVER-20):
/// a corridor bridges the identifier and the panel, and leaving the identifier, the corridor and the panel closes it
/// only after ``closeGraceDelay``, which coming back to any of them cancels. Escape, a click anywhere but the panel and
/// the pane's window resigning key close it at once; another identifier replaces it once its own lookup lands.
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
    /// The shown identifier's rect in the text view, as last measured, the scrolls it followed included.
    private var shownAnchor: NSRect?
    private let panel: HoverDocPanel
    /// Closes the panel once the grace delay passes; nil while nothing is to close it.
    private var closeTask: Task<Void, Never>?
    /// Bumped by every scheduled or cancelled close, so a close that wakes after its cancellation does nothing.
    private var closeGeneration = 0
    /// Watches for Escape and clicks while the panel shows.
    private var eventMonitor: Any?

    /// How long the panel stays once the pointer has left its identifier, the corridor and the panel: time to cross
    /// from one to another, or to come back.
    package static let closeGraceDelay: Duration = .milliseconds(300)
    /// The Escape key's virtual key code.
    private static let escapeKeyCode: UInt16 = 53

    /// Whether the documentation panel is currently on screen; for tests only.
    package var isPanelVisible: Bool { panel.isVisible }

    /// - Parameters:
    ///   - clock: Times the debounce.
    ///   - taskProvider: Spawns the lookups.
    ///   - debounce: How long the pointer rests on an identifier before it is looked up.
    ///   - panel: The panel documents show in; one that orders no window in, for tests.
    package init(
        clock: any Clock<Duration> = ContinuousClock(), taskProvider: any TaskProvider = .default,
        debounce: Duration = .milliseconds(300), panel: HoverDocPanel = HoverDocPanel()
    ) {
        self.clock = clock
        self.taskProvider = taskProvider
        self.debounce = debounce
        self.panel = panel
        super.init()
        panel.onPointerInsideChange = { [weak self] inside in self?.pointerOverPanelChanged(inside) }
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowDidResignKey(_:)), name: NSWindow.didResignKeyNotification, object: nil)
    }

    /// Removes the tracking area and observers from the previously attached view, if any, and closes any open
    /// panel.
    package func detach() {
        invalidate()
        if let trackingArea, let textView {
            textView.removeTrackingArea(trackingArea)
        }
        stopFollowingClipViews()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
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
    /// ``HoverHit/identifierRange``, and closes it once the identifier leaves the visible rect. A scroll drops any
    /// pending hover, shown panel or not: its identifier has moved from under the pointer.
    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView else { return }
        let key = ObjectIdentifier(clipView)
        guard scrollOrigins[key] != clipView.bounds.origin else { return }
        scrollOrigins[key] = clipView.bounds.origin
        dropPendingLookup()
        guard panel.isVisible, let shownHit, let textView else {
            invalidate()
            return
        }
        let anchorRect = HoverHitTester.anchorRect(for: shownHit.identifierRange, textView: textView)
        switch HoverScrollResponse(anchorRect: anchorRect, visibleRect: textView.visibleRect) {
            case .stay: break
            case .follow(let anchorRect):
                shownAnchor = anchorRect
                panel.reposition(anchorRect: anchorRect, in: textView)
            case .close: invalidate()
        }
    }

    /// The pane's window stopped being key: the panel over it closes.
    @objc private func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === textView?.window else { return }
        invalidate()
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
        pointerLeftTextView()
    }

    /// The testable core of ``mouseExited(with:)``: a shown panel closes after the grace delay unless the pointer is
    /// over it or comes back; anything still loading is dropped.
    package func pointerLeftTextView() {
        guard panel.isVisible else {
            invalidate()
            return
        }
        dropPendingLookup()
        // Leaving the pane for the panel keeps the panel open.
        guard !panel.pointerIsInside else { return }
        scheduleClose()
    }

    /// The testable core of ``mouseMoved(with:)``: hit-tests `point`, in the attached text view's own coordinate
    /// space, and schedules (or reuses, or cancels) a hover resolution. A shown panel stays while the pointer is on
    /// its identifier or the corridor to it, and closes after the grace delay once the pointer is off both.
    package func pointerMoved(to point: NSPoint) {
        guard isEnabled, let resolve, let textView, let rendered = renderedProvider?() else {
            invalidate()
            return
        }
        // Over the panel, the pointer is not over the text: nothing beneath it is looked up or re-anchored.
        guard !panel.pointerIsInside else { return }
        followEnclosingClipViews()
        let onBridge = isOnBridge(point, in: textView)
        guard let hit = HoverHitTester.hit(at: point, textView: textView, rendered: rendered) else {
            dropPendingLookup()
            if onBridge { cancelClose() } else { scheduleClose() }
            return
        }
        if let shownHit, shownHit.identifierRange == hit.identifierRange {
            // Back on the shown identifier: it stays, and is not looked up again.
            dropPendingLookup()
            currentHit = hit
            cancelClose()
            return
        }
        if let currentHit, currentHit.row == hit.row, currentHit.utf16Column == hit.utf16Column {
            return
        }
        // Another identifier: the shown panel, if any, stays until this one's document replaces it.
        cancelClose()
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
            let document = await resolve(hit)
            guard self.generation == myGeneration else { return }
            guard let document else {
                // Nothing to show here: the panel of the identifier the pointer left goes, after the grace delay.
                self.scheduleClose()
                return
            }
            self.show(document: document, for: hit)
        }
    }

    /// The testable core of the event monitor that runs while the panel shows: Escape closes the panel and is
    /// consumed; a click anywhere but the panel closes it and goes on to its target. Nil for a consumed event.
    package func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible else { return event }
        switch event.type {
            case .keyDown where event.keyCode == Self.escapeKeyCode:
                invalidate()
                return nil
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                if !panel.owns(event.window) { invalidate() }
                return event
            default:
                return event
        }
    }

    /// Over the panel, the reader is reading it: a lookup the path to it started, over another identifier, would
    /// replace it under the pointer, so it is dropped with the close.
    private func pointerOverPanelChanged(_ inside: Bool) {
        guard inside else {
            scheduleClose()
            return
        }
        dropPendingLookup()
        cancelClose()
    }

    /// Whether `point`, in the text view's coordinates, is on the shown identifier or the corridor to its panel.
    private func isOnBridge(_ point: NSPoint, in textView: NSTextView) -> Bool {
        guard panel.isVisible, let anchor = shownAnchor else { return false }
        if anchor.contains(point) { return true }
        guard let frame = panel.frameOnScreen, let window = textView.window else { return false }
        let panelRect = textView.convert(window.convertFromScreen(frame), from: nil)
        return HoverCorridor.rect(anchor: anchor, panel: panelRect).contains(point)
    }

    /// Stops whatever lookup is pending, leaving a shown panel as it is.
    private func dropPendingLookup() {
        generation += 1
        pendingTask?.cancel()
        currentHit = nil
    }

    /// Closes the shown panel once ``closeGraceDelay`` passes, unless something cancels it first; a no-op while a close
    /// is already pending or nothing shows.
    private func scheduleClose() {
        guard panel.isVisible, closeTask == nil else { return }
        closeGeneration += 1
        let myGeneration = closeGeneration
        closeTask = taskProvider.task { [weak self, clock] in
            try? await clock.sleep(for: Self.closeGraceDelay)
            guard let self, self.closeGeneration == myGeneration, !Task.isCancelled else { return }
            self.closeTask = nil
            self.closePanel()
        }
    }

    private func cancelClose() {
        closeGeneration += 1
        closeTask?.cancel()
        closeTask = nil
    }

    private func show(document: HoverDocument, for hit: HoverHit) {
        guard let textView else { return }
        cancelClose()
        shownHit = hit
        shownAnchor = hit.anchorRect
        panel.show(document: document, anchorRect: hit.anchorRect, in: textView)
        guard panel.isVisible, eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown
        ]) { [weak self] event in
            let passes = MainActor.assumeIsolated { self.map { $0.handleLocalEvent(event) != nil } ?? true }
            return passes ? event : nil
        }
    }

    private func closePanel() {
        cancelClose()
        panel.close()
        shownHit = nil
        shownAnchor = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
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

/// The invisible corridor between a hovered identifier and its panel, in the text view's flipped coordinates: across
/// the panel's width, from the identifier's middle to the panel's near edge and a little past it, so a pointer on its
/// way from one to the other, even aslant, never leaves the hover (HOVER-20).
package enum HoverCorridor {
    /// How far past the panel's near edge the corridor reaches, for the point or two rounding leaves between them.
    package static let slack: CGFloat = 4

    package static func rect(anchor: NSRect, panel: NSRect) -> NSRect {
        let minX = min(anchor.minX, panel.minX)
        let width = max(anchor.maxX, panel.maxX) - minX
        if panel.midY >= anchor.midY {
            // The panel lies below the identifier.
            return NSRect(x: minX, y: anchor.midY, width: width, height: max(panel.minY - anchor.midY, 0) + slack)
        }
        let top = panel.maxY - slack
        return NSRect(x: minX, y: top, width: width, height: max(anchor.midY - top, 0))
    }
}
