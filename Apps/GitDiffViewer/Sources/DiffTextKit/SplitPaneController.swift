package import AemiCore
package import AppKit
import DiffCore
package import DiffRendering
import Foundation

/// Keeps the two panes of the split view in step: mirrored scrolling, and, when lines wrap, equal row heights.
@MainActor
package final class SplitPaneController: NSObject {
    private struct Member {
        let scrollView: NSScrollView?
        weak var textView: NSTextView?
        var rendered: RenderedText?
    }

    private var members: [Member] = []
    private var isSyncing = false
    private let clock: any Clock<Duration>
    private let taskProvider: any TaskProvider
    /// The debounced alignment pass in flight, if any; awaiting it observes the pass it will run.
    package private(set) var pendingAlignment: Task<Void, Never>?
    /// Long enough for a resize and both panes applying text to land in one alignment pass.
    package static let alignmentDebounce: Duration = .milliseconds(40)

    /// Takes the clock the debounce sleeps on and the provider its task is spawned through, so tests can drive
    /// the one with a virtual clock and await the other.
    package init(clock: any Clock<Duration> = ContinuousClock(), taskProvider: any TaskProvider = .default) {
        self.clock = clock
        self.taskProvider = taskProvider
        super.init()
    }

    package var wrapsLines = false {
        didSet { scheduleAlignment() }
    }

    /// Mirrors vertical scrolling between the panes; horizontal scrolling is always independent.
    package var syncsScrolling = true

    package func register(_ scrollView: NSScrollView?, textView: NSTextView) {
        guard !members.contains(where: { $0.textView === textView }) else { return }
        members.append(Member(scrollView: scrollView, textView: textView, rendered: nil))
        guard let scrollView else { return }
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    package func unregister(textView: NSTextView) {
        if let scrollView = members.first(where: { $0.textView === textView })?.scrollView {
            NotificationCenter.default.removeObserver(
                self, name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        }
        members.removeAll { $0.textView === textView }
    }

    package func update(_ rendered: RenderedText, for textView: NSTextView) {
        guard let index = members.firstIndex(where: { $0.textView === textView }) else { return }
        members[index].rendered = rendered
        scheduleAlignment()
    }

    /// Coalesces bursts of layout changes (a resize, two panes applying text) into one alignment pass.
    package func scheduleAlignment() {
        pendingAlignment?.cancel()
        pendingAlignment = taskProvider.task { [weak self, clock] in
            guard (try? await clock.sleep(for: Self.alignmentDebounce)) != nil else { return }
            self?.alignRows()
        }
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        guard syncsScrolling, !isSyncing, let clipView = notification.object as? NSClipView else { return }
        isSyncing = true
        defer { isSyncing = false }
        let y = clipView.bounds.origin.y
        for member in members {
            guard let scrollView = member.scrollView, scrollView.contentView !== clipView,
                scrollView.contentView.bounds.origin.y != y
            else { continue }
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    // MARK: Row alignment

    private func alignRows() {
        guard members.count == 2,
            let leftView = members[0].textView, let rightView = members[1].textView,
            let left = members[0].rendered, let right = members[1].rendered,
            left.rows.count == right.rows.count
        else { return }

        guard wrapsLines else {
            apply(spacing: [], to: leftView, rendered: left)
            apply(spacing: [], to: rightView, rendered: right)
            return
        }

        let spacing = RowAlignment.spacing(left: rowHeights(of: leftView), right: rowHeights(of: rightView))
        apply(spacing: spacing.left, to: leftView, rendered: left)
        apply(spacing: spacing.right, to: rightView, rendered: right)
    }

    private func rowHeights(of textView: NSTextView) -> [Double] {
        textView.textLayoutManager.map(RowSpacing.rowHeights(in:)) ?? []
    }

    private func apply(spacing: [Double], to textView: NSTextView, rendered: RenderedText) {
        guard let contentStorage = textView.textContentStorage else { return }
        // A pass that changes no row (the common case after a debounce burst) costs a full attribute walk otherwise.
        let key = ObjectIdentifier(textView)
        if appliedSpacing[key]?.rendered === rendered, appliedSpacing[key]?.spacing == spacing { return }
        RowSpacing.apply(spacing, to: contentStorage, rendered: rendered)
        appliedSpacing[key] = (rendered, spacing)
        textView.enclosingScrollView?.superview?.needsDisplay = true
    }

    /// The spacing last applied to each pane and the text it was applied to.
    private var appliedSpacing: [ObjectIdentifier: (rendered: RenderedText, spacing: [Double])] = [:]
}
