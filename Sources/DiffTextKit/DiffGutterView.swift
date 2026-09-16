package import AppKit
package import DiffCore
package import DiffRendering
package import Foundation
import SwiftUI

package enum GutterStyle {
    case dual
    case old
    case new
}

/// What a gutter reads: a text system and the vertical inset its container sits at.
@MainActor
package protocol GutterTextSource: AnyObject {
    var gutterLayoutManager: NSTextLayoutManager? { get }
    var gutterInset: CGFloat { get }
}

extension NSTextView: GutterTextSource {
    package var gutterLayoutManager: NSTextLayoutManager? { textLayoutManager }
    package var gutterInset: CGFloat { textContainerInset.height }
}

extension StaticTextLayout: GutterTextSource {
    package var gutterLayoutManager: NSTextLayoutManager? { layoutManager }
    package var gutterInset: CGFloat { inset }
}

/// Line numbers drawn from the laid-out fragments of the visible viewport only, so cost is proportional to what is
/// on screen. Sits next to the scroll view and redraws when the clip view scrolls.
package final class DiffGutterView: NSView {
    package var rendered: RenderedText? {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    package var style: GutterStyle = .dual {
        didSet { invalidateIntrinsicContentSize() }
    }

    /// Called while a gap handle is dragged, with the expansion at the start of the drag and the rows dragged so far.
    package var onGapDrag: ((GapMarker, GapExpansion, Int) -> Void)?
    /// Expansion currently applied to a gap, captured when a drag starts.
    package var currentExpansion: ((GapKey) -> GapExpansion)?

    /// The text system whose rows are numbered; set together with `rendered`.
    package weak var source: (any GutterTextSource)?
    private weak var clipView: NSClipView?
    private let padding: CGFloat = 8
    private let columnGap: CGFloat = 10
    /// A gap handle drag in progress: the gap, the expansion it started from, and the geometry rows are counted in.
    private struct GapDrag {
        let marker: GapMarker
        let base: GapExpansion
        let startY: CGFloat
        let lineHeight: CGFloat
    }

    private var drag: GapDrag?

    /// Without a clip view the gutter belongs to an embedded pane that shows its whole document.
    package init(clipView: NSClipView?) {
        self.clipView = clipView
        super.init(frame: .zero)
        clipsToBounds = true
        guard let clipView else { return }
        clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    @available(*, unavailable)
    package required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    package override var isFlipped: Bool { true }

    package var thickness: CGFloat {
        let columns: CGFloat = style == .dual ? 2 : 1
        return padding * 2 + columns * columnWidth + (columns - 1) * columnGap
    }

    package override var intrinsicContentSize: NSSize {
        NSSize(width: thickness, height: NSView.noIntrinsicMetric)
    }

    private var palette: DiffPalette { rendered?.palette ?? .system }

    private var digitWidth: CGFloat {
        ("8" as NSString).size(withAttributes: [.font: palette.gutterFont]).width
    }

    private var digits: Int {
        max(String(rendered?.maximumLineNumber ?? 0).count, 2)
    }

    private var columnWidth: CGFloat { CGFloat(digits) * digitWidth }

    @objc private func clipViewDidScroll(_ notification: Notification) {
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Gap handles

    /// A grip on the gap row: the row's tint across the gutter and two bars in the middle.
    private func drawGapHandle(y: CGFloat, height: CGFloat) {
        if let background = palette.rowBackground(for: .gap, side: .unified) {
            background.setFill()
            NSRect(x: 0, y: y, width: bounds.width - 1, height: height).fill()
        }
        palette.textColor.withAlphaComponent(0.45).setFill()
        let gripWidth = min(bounds.width - 2 * padding, 18)
        let x = (bounds.width - gripWidth) / 2
        let middle = y + height / 2
        NSRect(x: x, y: middle - 3, width: gripWidth, height: 1.5).fill()
        NSRect(x: x, y: middle + 1.5, width: gripWidth, height: 1.5).fill()
    }

    package override func scrollWheel(with event: NSEvent) {
        if let clipView {
            clipView.enclosingScrollView?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    package override func resetCursorRects() {
        forEachVisibleFragment { fragment, row, y in
            guard row.kind == .gap else { return }
            addCursorRect(
                NSRect(x: 0, y: y, width: bounds.width, height: fragment.layoutFragmentFrame.height),
                cursor: .resizeUpDown)
        }
    }

    package override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var hit: (GapMarker, CGFloat)?
        forEachVisibleFragment { fragment, row, y in
            let frame = fragment.layoutFragmentFrame
            if let gap = row.gap, point.y >= y, point.y < y + frame.height {
                hit = (gap, fragment.textLineFragments.first?.typographicBounds.height ?? frame.height)
            }
        }
        guard let (marker, lineHeight) = hit else { return super.mouseDown(with: event) }
        let base = currentExpansion?(marker.key) ?? GapExpansion()
        if event.clickCount == 2 {
            // A double click reveals the whole gap: as many lines as it hides, in whichever direction it allows.
            onGapDrag?(marker, base, marker.hiddenRows)
            return
        }
        drag = GapDrag(marker: marker, base: base, startY: point.y, lineHeight: max(lineHeight, 1))
    }

    package override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let lines = Int(((point.y - drag.startY) / drag.lineHeight).rounded())
        onGapDrag?(drag.marker, drag.base, lines)
    }

    package override func mouseUp(with event: NSEvent) {
        drag = nil
    }

    /// Visits the laid-out fragments intersecting the clip view, with each row's metadata and its y in this view.
    private func forEachVisibleFragment(_ body: (NSTextLayoutFragment, RowMeta, CGFloat) -> Void) {
        guard let source, let rendered, let layoutManager = source.gutterLayoutManager,
            let contentManager = layoutManager.textContentManager
        else { return }
        let scrollOffset = clipView?.bounds.origin.y ?? 0
        let inset = source.gutterInset
        let visibleHeight = clipView?.bounds.height ?? bounds.height
        let start =
            clipView == nil
            ? layoutManager.documentRange.location
            : layoutManager.textViewportLayoutController.viewportRange?.location ?? layoutManager.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            let y = frame.minY + inset - scrollOffset
            if y > visibleHeight { return false }
            if y + frame.height < 0 { return true }
            let offset = contentManager.offset(
                from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
            guard let row = rendered.row(containing: offset) else { return true }
            body(fragment, row, y)
            return true
        }
    }

    package override func draw(_ dirtyRect: NSRect) {
        palette.gutterBackground.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: palette.gutterFont, .foregroundColor: palette.gutterText
        ]
        let changedAttributes: [NSAttributedString.Key: Any] = [
            .font: palette.gutterFont, .foregroundColor: palette.gutterChangedText
        ]

        forEachVisibleFragment { fragment, row, y in
            let frame = fragment.layoutFragmentFrame
            if row.kind == .gap {
                drawGapHandle(y: y, height: frame.height)
                return
            }
            let attributes = row.kind == .context ? baseAttributes : changedAttributes
            // A line numbered the same on both sides shows its number once, next to the text.
            let numbers: [Int?] =
                switch style {
                    case .dual: row.oldNumber == row.newNumber ? [nil, row.newNumber] : [row.oldNumber, row.newNumber]
                    case .old: [row.oldNumber]
                    case .new: [row.newNumber]
                }
            // Numbers sit on the same baseline as the row's first line of text, whatever the line height is, so
            // they follow the text up when a taller line centres it: TextKit reports the baseline it laid out,
            // which is not where a baseline offset then drew the glyphs.
            let firstLine = fragment.textLineFragments.first
            let baseline =
                y + (firstLine.map { $0.typographicBounds.minY + $0.glyphOrigin.y } ?? frame.height * 0.75)
                - (rendered?.baselineOffset ?? 0)
            let top = baseline - palette.gutterFont.ascender
            for (column, number) in numbers.enumerated() {
                guard let number else { continue }
                let label = String(number) as NSString
                let size = label.size(withAttributes: attributes)
                let x = padding + CGFloat(column) * (columnWidth + columnGap) + columnWidth - size.width
                label.draw(at: NSPoint(x: x, y: top), withAttributes: attributes)
            }
        }
    }
}

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
