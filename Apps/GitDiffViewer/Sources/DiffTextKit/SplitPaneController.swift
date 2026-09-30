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
        /// Called once an alignment pass has changed the member's rows.
        let didAlign: (@MainActor () -> Void)?
    }

    private var members: [Member] = []
    private var isSyncing = false
    /// The clip view of the pane scrolled last, by the user or to place a row, which the other pane follows.
    private weak var leadingClip: NSClipView?
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

    /// How one pane follows the other's scrolling.
    package enum ScrollSync: Sendable {
        /// The other pane shows the row at this one's top, as far into it: each pane places that row after its own
        /// estimates of the rows above it, which differ between the sides while those rows are not laid out.
        case byRow
        /// The other pane takes this one's offset, which shows the same row in both only once each has laid out every
        /// row above it. `FirstChangePlacementBenchmark` compares it with ``byRow``.
        case byOffset
    }

    package var scrollSync = ScrollSync.byRow

    /// Whether a pane lays its text out down to a row it places, so the other pane, at the same offset, shows it at
    /// the same place.
    package var needsRowsAboveLaidOut: Bool { syncsScrolling && scrollSync == .byOffset }

    /// Keeps `textView`'s pane in step with the other; `didAlign` is called each time an alignment pass changes its rows.
    package func register(
        _ scrollView: NSScrollView?, textView: NSTextView, didAlign: (@MainActor () -> Void)? = nil
    ) {
        guard !members.contains(where: { $0.textView === textView }) else { return }
        members.append(Member(scrollView: scrollView, textView: textView, rendered: nil, didAlign: didAlign))
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
        leadingClip = clipView
        followLeader(clipView, byOffsetWithoutRow: true)
    }

    /// Keeps the panes on the row the pane scrolled last shows, once TextKit has laid out what shows in
    /// `textView`'s: laying it out moves the rows there, the row at the top among them, without scrolling the pane,
    /// and the other pane, which followed that row where it was, would show another.
    package func paneDidLayout(_ textView: NSTextView) {
        guard syncsScrolling, scrollSync == .byRow, !isSyncing, let leadingClip,
            members.contains(where: { $0.textView === textView })
        else { return }
        isSyncing = true
        defer { isSyncing = false }
        // No scroll moved the panes: without a row to follow, as while the two apply a new text in turn, they stay.
        followLeader(leadingClip, byOffsetWithoutRow: false)
    }

    /// Has every other pane follow the one `clipView` scrolls: to the row at its top when the panes sync by row and
    /// that row is found, else to its offset, when `byOffsetWithoutRow`.
    private func followLeader(_ clipView: NSClipView, byOffsetWithoutRow: Bool) {
        let source = members.first { $0.scrollView?.contentView === clipView }
        let anchor = scrollSync == .byRow ? source.flatMap { rowAnchor(in: $0, clipView: clipView) } : nil
        guard anchor != nil || byOffsetWithoutRow else { return }
        // The panes show the same row at their tops below whatever bars lie over each: stacked, only the upper one
        // runs beneath the tab bar (book TAB-09).
        // Read once the anchor is: laying out what shows in the pane can scroll it on.
        let top = clipView.bounds.origin.y + clipView.contentInsets.top
        for member in members {
            guard let scrollView = member.scrollView, scrollView.contentView !== clipView else { continue }
            follow(anchor, orOffset: top, in: member, scrollView: scrollView)
        }
    }

    /// Scrolls `member`'s pane to show `anchor`'s row as far below its top as the pane that scrolled shows it, or,
    /// without a row, to `top`, that pane's top below its bars.
    ///
    /// The row is laid out, not the rows above it, and TextKit moves it as it lays out what then shows around it: the
    /// pane is laid out and scrolled again until the row stays, as a placement is (see `RowPlacement`).
    private func follow(_ anchor: RowAnchor?, orOffset top: CGFloat, in member: Member, scrollView: NSScrollView) {
        let clip = scrollView.contentView
        for _ in 0 ..< RowPlacement.passes {
            let rowTop = anchor.flatMap { self.top(ofRow: $0.row, in: member) }
            let y = (rowTop.map { $0 + (anchor?.offset ?? 0) } ?? top) - clip.contentInsets.top
            let before = clip.bounds.origin.y
            guard before != y else { return }
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(clip)
            // A pane at the end of its scrolling goes no further, however often it is asked.
            guard rowTop != nil, clip.bounds.origin.y != before,
                let layoutManager = member.textView?.textLayoutManager
            else { return }
            layoutManager.textViewportLayoutController.layoutViewport()
        }
    }

    /// A row, and how far below its top a pane's top lies.
    private struct RowAnchor {
        let row: Int
        let offset: CGFloat
    }

    /// The row at the top of `member`'s pane, below its bars, from the fragment laid out there, as the pane lays out
    /// what shows; nil when the other side's rows do not match this one's, as while the two apply a new text in turn.
    private func rowAnchor(in member: Member, clipView: NSClipView) -> RowAnchor? {
        guard let textView = member.textView, let rendered = member.rendered, !rendered.rows.isEmpty,
            members.allSatisfy({ $0.rendered?.rows.count == rendered.rows.count }),
            let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager
        else { return nil }
        let inset = textView.textContainerInset.height
        let top = { clipView.bounds.origin.y + clipView.contentInsets.top }
        let point = { CGPoint(x: 0, y: max(top() - inset, 0)) }
        var fragment = layoutManager.textLayoutFragment(for: point())
        if fragment?.state != .layoutAvailable {
            // Scrolled where nothing is laid out yet: what shows there is laid out now rather than at the next pass,
            // and TextKit scrolls the pane on as far as laying it out moves its rows.
            layoutManager.textViewportLayoutController.layoutViewport()
            fragment = layoutManager.textLayoutFragment(for: point())
        }
        guard let fragment else { return nil }
        let row = rendered.rowIndex(
            containing: contentManager.offset(
                from: layoutManager.documentRange.location, to: fragment.rangeInElement.location))
        return RowAnchor(row: row, offset: top() - (fragment.layoutFragmentFrame.minY + inset))
    }

    /// The top of `row`'s line in `member`'s text view, the row laid out and the rows above it not.
    private func top(ofRow row: Int, in member: Member) -> CGFloat? {
        guard let textView = member.textView, let rendered = member.rendered, rendered.lineStarts.indices.contains(row),
            let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager,
            let location = contentManager.location(
                layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row])
        else { return nil }
        layoutManager.ensureLayout(for: NSTextRange(location: location))
        guard let fragment = layoutManager.textLayoutFragment(for: location) else { return nil }
        return fragment.layoutFragmentFrame.minY + textView.textContainerInset.height
    }

    // MARK: Row alignment

    private func alignRows() {
        guard members.count == 2,
            let leftView = members[0].textView, let rightView = members[1].textView,
            let left = members[0].rendered, let right = members[1].rendered,
            left.rows.count == right.rows.count
        else { return }

        let spacing =
            wrapsLines
            ? RowAlignment.spacing(left: rowHeights(of: leftView), right: rowHeights(of: rightView))
            : (left: [], right: [])
        let changedLeft = apply(spacing: spacing.left, to: leftView, rendered: left)
        let changedRight = apply(spacing: spacing.right, to: rightView, rendered: right)
        guard changedLeft || changedRight else { return }
        for member in members { member.didAlign?() }
    }

    private func rowHeights(of textView: NSTextView) -> [Double] {
        textView.textLayoutManager.map(RowSpacing.rowHeights(in:)) ?? []
    }

    /// Applies `spacing` to `textView`'s rows, and tells whether it changed them.
    private func apply(spacing: [Double], to textView: NSTextView, rendered: RenderedText) -> Bool {
        guard let contentStorage = textView.textContentStorage else { return false }
        // A pass that changes no row (the common case after a debounce burst) costs a full attribute walk otherwise.
        let key = ObjectIdentifier(textView)
        if appliedSpacing[key]?.rendered === rendered, appliedSpacing[key]?.spacing == spacing { return false }
        RowSpacing.apply(spacing, to: contentStorage, rendered: rendered)
        appliedSpacing[key] = (rendered, spacing)
        return true
    }

    /// The spacing last applied to each pane and the text it was applied to.
    private var appliedSpacing: [ObjectIdentifier: (rendered: RenderedText, spacing: [Double])] = [:]
}
