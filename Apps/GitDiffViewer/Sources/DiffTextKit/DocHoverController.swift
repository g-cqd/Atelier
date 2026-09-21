package import AemiCore
package import AppKit
package import DiffRendering
import Foundation
package import SwiftUI

/// Documentation shown while the pointer rests on an identifier: SwiftUI markdown in a scrollable, selectable
/// popover.
package struct HoverDocView: View {
    package let content: AttributedString

    package init(content: AttributedString) {
        self.content = content
    }

    package var body: some View {
        ScrollView {
            Text(content)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: 480, maxHeight: 360, alignment: .topLeading)
    }
}

/// Debounces pointer movement over a diff pane into a single documentation lookup, and shows the result in a
/// popover anchored to the hovered identifier.
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

    /// Resolves markdown-rendered content for a hit; `nil` means nothing to show.
    package var resolve: (@Sendable (HoverHit) async -> AttributedString?)?
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
    private var popover: NSPopover?

    /// Whether the documentation popover is currently on screen; for tests only.
    package var isPopoverVisible: Bool { popover?.isShown ?? false }

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

    /// Cancels any in-flight resolution and closes the popover, without detaching from the text view.
    package func invalidate() {
        generation += 1
        pendingTask?.cancel()
        pendingTask = nil
        currentHit = nil
        closePopover()
    }

    @objc private func scrollViewBoundsDidChange(_ notification: Notification) {
        invalidate()
    }

    /// `NSTrackingArea` sends these directly to their owner by selector, not through the responder chain, so
    /// this need not subclass `NSResponder`; `@objc` alone makes the selectors visible to it.
    @objc package func mouseMoved(with event: NSEvent) {
        guard let textView else { return }
        pointerMoved(to: textView.convert(event.locationInWindow, from: nil))
    }

    /// No-op: nothing shows until the pointer actually rests on an identifier, which `mouseMoved` alone detects.
    @objc package func mouseEntered(with event: NSEvent) {}

    @objc package func mouseExited(with event: NSEvent) {
        // A move into the popover itself is indistinguishable from leaving the text view here; closing on every
        // exit is the simple, correct-enough v1 behaviour.
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
            closePopover()
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
            guard let content = await resolve(hit) else { return }
            guard self.generation == myGeneration else { return }
            self.show(content: content, for: hit)
        }
    }

    private func show(content: AttributedString, for hit: HoverHit) {
        guard let textView else { return }
        shownHit = hit
        let popover = self.popover ?? makePopover()
        self.popover = popover
        (popover.contentViewController as? NSHostingController<HoverDocView>)?.rootView = HoverDocView(content: content)
        if popover.isShown {
            popover.positioningRect = hit.anchorRect
        } else {
            popover.show(relativeTo: hit.anchorRect, of: textView, preferredEdge: .maxY)
        }
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: HoverDocView(content: AttributedString()))
        return popover
    }

    private func closePopover() {
        guard let popover else { return }
        popover.performClose(nil)
        shownHit = nil
    }
}
