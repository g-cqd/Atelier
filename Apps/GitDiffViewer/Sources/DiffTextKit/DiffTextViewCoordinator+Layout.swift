package import AppKit
import AtelierDiagnostics
import DiffCore
import DiffRendering
package import Foundation
import SwiftUI

// Wrapping, the visible rows, overscroll and the content height; apart from the type's file, to keep it within the limits SwiftLint sets.
extension DiffTextViewCoordinator {
    /// Breaks lines as `wrapsLines` and `column` say, unless they already do, and sizes the pane again. Returns
    /// whether anything changed, for the split view to align the rows again.
    @discardableResult
    package func setWrapping(_ wrapsLines: Bool, column: Int, font: NSFont) -> Bool {
        guard self.wrapsLines != wrapsLines || wrapColumn != column, let textView,
            let scrollView = textView.enclosingScrollView
        else { return false }
        self.wrapsLines = wrapsLines
        wrapColumn = column
        Self.configureWrapping(wrapsLines, column: column, font: font, textView: textView, scrollView: scrollView)
        updateOverscroll(in: scrollView.contentView)
        return true
    }

    /// Wrapped panes track the viewport width, or wrap at a fixed column and scroll sideways when the viewport is
    /// narrower; unwrapped panes track a text view that ``updateOverscroll(in:)`` sizes to the longest line.
    package static func configureWrapping(
        _ wraps: Bool,
        column: Int,
        font: NSFont,
        textView: NSTextView,
        scrollView: NSScrollView
    ) {
        guard let container = textView.textContainer else { return }
        guard wraps else {
            // A container that tracks the view lets TextKit lay out the viewport only; a fixed one makes every frame
            // change lay out the whole document.
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = []
            container.widthTracksTextView = true
            scrollView.hasHorizontalScroller = true
            if let layoutManager = textView.textLayoutManager {
                layoutManager.invalidateLayout(for: layoutManager.documentRange)
            }
            textView.needsLayout = true
            textView.needsDisplay = true
            return
        }
        let tracksViewport = column <= 0
        textView.isHorizontallyResizable = !tracksViewport
        textView.autoresizingMask = tracksViewport ? [.width] : []
        container.widthTracksTextView = tracksViewport
        let width =
            if column > 0 {
                DiffPalette.wrapWidth(column: column, font: font, padding: container.lineFragmentPadding)
            } else {
                scrollView.contentView.bounds.width
            }
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        scrollView.hasHorizontalScroller = !tracksViewport
        if tracksViewport {
            textView.setFrameSize(NSSize(width: scrollView.contentView.bounds.width, height: textView.frame.height))
        }
        if let layoutManager = textView.textLayoutManager {
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
        }
        textView.sizeToFit()
        textView.needsLayout = true
        textView.needsDisplay = true
    }

    /// Rows intersecting the clip view, from the laid-out fragments at its top and bottom edges.
    package func visibleRows() -> Range<Int> {
        guard let textView, let rendered, !rendered.rows.isEmpty,
            let layoutManager = textView.textLayoutManager, let contentManager = layoutManager.textContentManager,
            let clipView = textView.enclosingScrollView?.contentView
        else { return 0 ..< 0 }
        let inset = textView.textContainerInset.height
        let lastRow = rendered.rows.count - 1
        let contentBottom = layoutManager.usageBoundsForTextContainer.maxY + inset
        /// Points below the document, in the overscroll space, belong to the last row.
        func row(at y: CGFloat) -> Int {
            guard y < contentBottom,
                let fragment = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: y - inset))
            else { return y >= contentBottom ? lastRow : 0 }
            return rendered.rowIndex(
                containing: contentManager.offset(
                    from: layoutManager.documentRange.location,
                    to: fragment.rangeInElement.location
                )
            )
        }
        // TextKit 2 lays out lazily: a fragment the viewport reaches may not exist yet, and a row lookup that
        // fails answers 0, which put the bottom edge above the top edge and trapped on the range.
        layoutManager.ensureLayout(
            for: CGRect(
                x: 0,
                y: clipView.bounds.minY - inset,
                width: clipView.bounds.width,
                height: clipView.bounds.height
            )
        )
        // What the bars above the pane cover does not show.
        let first = min(row(at: max(clipView.bounds.minY + clipView.contentInsets.top, 0)), lastRow)
        let last = min(max(row(at: clipView.bounds.maxY), first), lastRow)
        return first ..< (last + 1)
    }

    /// Follows TextKit's layout of the text view: sizes the pane each time TextKit's usage bounds change, as the layout
    /// manager's documentation asks of a view sized by them, and at the end of each layout pass, since TextKit lays out
    /// some of the text, the last row among it, without a change of its bounds to tell; and places a row asked for.
    ///
    /// ``updateOverscroll(in:)`` reads what TextKit laid out, and on a new pane it had laid out nothing each time that
    /// ran before this: when the text was applied, and when the clip view took its size, whose new width drops what
    /// TextKit had laid out. Only a resize of the text view or of its clip view sized the pane again, and TextKit
    /// resizes the text view only past the size the pane had: a pane could keep a size that its text had long outgrown.
    ///
    /// Sizing the pane reads TextKit's layout, which first carries out the invalidations TextKit has pending, and each
    /// fragment one of them drops changes the usage bounds again, within the read: a change that comes while the pane
    /// is being sized is left to that sizing, which reads the layout they leave. Sizing the pane for each of them in
    /// turn nested one call per fragment dropped, and a text laid out over some 1,800 rows, replaced, overflowed the
    /// stack.
    ///
    /// During an edit of the text, TextKit tells of a change of its usage bounds from within its invalidation of the
    /// edited range, as it drops that range's fragments one by one. Reading the layout there invalidates the range
    /// again, under the invalidation still going through its fragments, and that one then never ends: the row spacing
    /// that lines up side-by-side rows wrapped onto different numbers of lines froze the window so. A change that
    /// comes during an edit leaves the pane to be sized at the end of the next layout pass, once the edit is over.
    package func followLayout() {
        usageObservation = textView?.textLayoutManager?
            .observe(\.usageBoundsForTextContainer) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isFollowingUsage, let textView = self.textView,
                        let clipView = textView.enclosingScrollView?.contentView
                    else { return }
                    if textView.textLayoutManager?.textContentManager?.hasEditingTransaction == true {
                        textView.needsLayout = true
                        return
                    }
                    self.isFollowingUsage = true
                    defer { self.isFollowingUsage = false }
                    self.updateOverscroll(in: clipView)
                }
            }
        (textView as? DiffPaneTextView)?.onLayout = { [weak self] in self?.layoutDidEnd() }
    }

    @objc package func viewportDidResize(_ notification: Notification) {
        guard let clipView = notification.object as? NSClipView else { return }
        metrics.width = max(clipView.bounds.width, textView?.frame.width ?? 0)
        updateOverscroll(in: clipView)
        if pendingScroll != nil { textView?.needsLayout = true } else { placeAgainUnlessScrolled() }
        splitController?.scheduleAlignment()
    }

    /// Sizes the text view to its content and to how far the pane scrolls past it: by default to the last line at the
    /// bottom, the band of a gap at the end of the file and the pane's inset under it, a text shorter than the pane
    /// filling it; with ``scrollsPastEnd``, on until the last line reaches the top. The space is part of the view, not
    /// a scroll inset, so nothing else has to account for it.
    ///
    /// The text view's frame is also TextKit's to set, to the height it has laid out, which leaves out the space past
    /// the end and, early on, most of the text: every call sets the frame again, whether or not the size it computes
    /// changed.
    package func updateOverscroll(in clipView: NSClipView) {
        guard let textView else { return }
        // What shows of the pane: less what the bars above it cover, which the text starts below.
        let shown = clipView.bounds.height - clipView.contentInsets.top
        let height: CGFloat
        if scrollsPastEnd {
            // The row's own height, not the font's: a taller line height would otherwise leave the last row short of
            // the top of the pane, half of it hidden under whatever sits above. Less what lies below the text, which
            // the last line would otherwise scroll past the top by.
            let lineHeight = rendered?.lineHeight ?? DiffPalette.system.defaultLineHeight
            let below = (rendered?.bandBelow ?? 0) + DiffPaneMetrics.containerInset
            height = contentHeight() + max(shown - lineHeight - below, 0)
        } else {
            height = max(contentHeight(), shown)
        }
        let width: CGFloat =
            if !wrapsLines, let rendered {
                // One line per row: the width needs no layout.
                max(clipView.bounds.width, unwrappedWidth(of: rendered))
            } else if textView.textContainer?.widthTracksTextView == true {
                clipView.bounds.width
            } else if wrapColumn > 0 {
                max(clipView.bounds.width, textView.textContainer?.size.width ?? 0)
            } else {
                max(clipView.bounds.width, (rendered?.unwrappedWidth ?? 0).rounded(.up))
            }
        let size = NSSize(width: width, height: height.rounded(.up))
        guard textView.minSize != size || textView.frame.size != size else { return }
        textView.minSize = size
        textView.setFrameSize(size)
    }

    /// The text's height, with the pane's inset and any band of a gap at the top of the file above it, and any band at
    /// its end and the pane's inset below it.
    ///
    /// Once TextKit has laid out the last row, the text ends where it placed it. Until then its usage bounds end with
    /// what it did lay out, or hold nothing, as when a text was just applied: a pane sized from them ended above its
    /// text, which was cut off and could not be scrolled to. The rows at one line each are the floor until then: every
    /// row takes a line at least, wrapped or not. Past the rows, the text ends where TextKit places its last row, after
    /// its estimates of the rows above it that it has not laid out (book CARD-17), which the rows' height may not
    /// match: the pane ends with that row wherever it lies, with no room left below it and none missing.
    package func contentHeight() -> CGFloat {
        guard let textView, let layoutManager = textView.textLayoutManager else { return 0 }
        let below = (rendered?.bandBelow ?? 0) + DiffPaneMetrics.containerInset
        let usage = layoutManager.usageBoundsForTextContainer
        let text: CGFloat
        if let last = lastFragment(in: layoutManager), last.state == .layoutAvailable {
            text = last.layoutFragmentFrame.maxY
            if let rendered { laidOutTextHeight = (rendered.id, text) }
        } else if usage.isEmpty, let rendered, let known = laidOutTextHeight, known.id == rendered.id {
            // TextKit dropped all of its layout, as a change of the container's width does, and the rows at one line
            // each are far short of a wrapped text. A pane sized to them would fit its viewport and drop its vertical
            // scroller; a legacy scroller's width then goes back to the text, which wraps taller and brings the
            // scroller back, and so on without end. The pane keeps its height until the viewport is laid out again.
            text = max(known.height, rendered.unwrappedTextHeight)
        } else {
            text = max(usage.maxY, rendered?.unwrappedTextHeight ?? 0)
        }
        return textView.textContainerInset.height + text + below
    }

    /// The layout fragment of the last row, laid out or not.
    func lastFragment(in layoutManager: NSTextLayoutManager) -> NSTextLayoutFragment? {
        var last: NSTextLayoutFragment?
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.endLocation, options: [.reverse]) {
            last = $0
            return false
        }
        return last
    }

    func unwrappedWidth(of rendered: RenderedText) -> CGFloat {
        if let unwrappedWidth, unwrappedWidth.id == rendered.id { return unwrappedWidth.width }
        let width = rendered.measuredUnwrappedWidth()
        unwrappedWidth = (rendered.id, width)
        return width
    }

    @objc package func textViewFrameDidChange(_ notification: Notification) {
        guard let textView, let clipView = textView.enclosingScrollView?.contentView else { return }
        metrics.width = max(clipView.bounds.width, textView.frame.width)
        updateOverscroll(in: clipView)
    }
}
