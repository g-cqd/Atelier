import AppKit
import DiffRendering
import Foundation

/// The body's scrolling document view: flipped, so the discussion's first block sits at the top and a scroll view
/// opens on it.
final class HoverFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The spacing between a discussion's blocks.
enum HoverBlockMetrics {
    static let blockSpacing: CGFloat = 8
    /// Above a heading, wider than ``blockSpacing`` so a section reads as starting.
    static let beforeHeading: CGFloat = 14
    /// Below a heading, tighter than ``blockSpacing`` so the heading reads as attached to what follows.
    static let afterHeading: CGFloat = 4
    static let itemSpacing: CGFloat = 4
    /// The column a list item's marker takes before its content.
    static let markerWidth: CGFloat = 18
    static let quoteBarWidth: CGFloat = 3
    static let quoteGap: CGFloat = 8
}

// MARK: - The discussion's blocks

/// The last block shown, which sets the spacing above the next.
typealias HoverBuiltBlock = (view: NSView, isHeading: Bool)

/// A discussion's blocks still to build, with what building them takes.
struct PendingDiscussion {
    var blocks: ArraySlice<HoverDocument.Block>
    let width: CGFloat
    let chipBackground: NSColor?
    var last: HoverBuiltBlock?
    /// The code block shown last, when some of its lines are still to show.
    var openCode: OpenCodeBlock?
}

/// A code block shown in part: measuring a long one whole on a throwaway stack took hundreds of milliseconds, so its
/// lines are measured and shown a chunk at a time, as the body scrolls to them.
struct OpenCodeBlock {
    let code: NSAttributedString
    /// Where the lines shown end: at the newline before the first line still to show.
    var shownEnd: Int
    let slot: HoverBlockSlot

    var isComplete: Bool { shownEnd == code.length }
}

/// Where a long code block's chunks end.
enum HoverCodeChunks {
    /// The lines a chunk holds: at the panel's code sizes, their height is past the panel's own.
    static let lines = 100

    /// The end of the chunk of `text` that starts at `start`: after ``lines`` lines, or at the text's end when half a
    /// chunk or less would be left after them, so that the last chunk is never short and a short code block is a
    /// single chunk.
    static func end(of text: NSString, from start: Int) -> Int {
        let end = lineEnd(of: text, from: start, lines: lines)
        guard end < text.length, lineEnd(of: text, from: end + 1, lines: lines / 2) < text.length else {
            return text.length
        }
        return end
    }

    /// The offset of the newline that ends the `lines`th line from `start`, or the text's length when fewer are left.
    private static func lineEnd(of text: NSString, from start: Int, lines: Int) -> Int {
        var location = start
        for _ in 0 ..< lines {
            let newline = text.range(
                of: "\n", options: .literal, range: NSRange(location: location, length: text.length - location))
            guard newline.location != NSNotFound else { return text.length }
            location = newline.location + 1
        }
        return location - 1
    }
}

/// A top-level block's view, with what showing another block of its kind in it takes.
struct HoverBlockSlot {
    /// The views a block needs: a paragraph and a heading share one, a text view.
    enum Kind: Equatable {
        case text
        case code
        case rule
        case list
        case quote

        init(_ block: HoverDocument.Block) {
            switch block {
                case .paragraph, .heading: self = .text
                case .code: self = .code
                case .list: self = .list
                case .quote: self = .quote
                case .rule: self = .rule
            }
        }

        /// Whether a view of this kind can show another block of it: a list's or a quote's is built of its blocks.
        var isReusable: Bool { self == .text || self == .code || self == .rule }
    }

    let kind: Kind
    let view: NSView
    /// The width the view is built at.
    let width: CGFloat
    /// The text view a text or a code block shows its text in; nil for the other kinds.
    let textView: NSTextView?
    /// Sets the view's height to its text's; nil for the kinds whose height follows their content.
    let height: NSLayoutConstraint?
    /// Places the view's top in the body's document; nil until the view is in the body.
    var top: NSLayoutConstraint?

    /// The view's height as shown: its text's, or what its content lays out to.
    var shownHeight: CGFloat { height?.constant ?? view.fittingSize.height }
}

/// The body's top-level block views, top to bottom: the first ``shown`` show the discussion, and the rest, hidden,
/// wait for a later block of their kind.
///
/// Each view is pinned to the document by its own top, not arranged in a stack view: a stack of a few hundred views
/// took 60 to 360 ms to remove them from, and as long to lay out once they were hidden, which detaches them from it.
/// Pinned apart, a view is hidden, moved or removed without touching the others.
struct HoverBlockSlots {
    var slots: [HoverBlockSlot] = []
    var shown = 0
    /// Where the last view shown ends, and the document with it.
    var contentHeight: CGFloat = 0
}

extension HoverDocPanel {
    /// Shows `blocks` in ``bodyDocument``, under an Overview heading, each block its own view `width` wide. Only the
    /// blocks the panel can show at once are built: every block is a view measured and laid out, and a discussion of
    /// a few hundred of them took seconds (`HoverBuildBenchmark`). The rest are built as the body scrolls towards
    /// them, in ``bodyDidScroll()``. Each block takes the view the last discussion had at its place when its kind
    /// matches, and the views left over are hidden.
    func renderDiscussion(_ blocks: [HoverDocument.Block], chipBackground: NSColor?, width: CGFloat) {
        // Dropped first, so the scroll back to the top builds nothing of the discussion shown before.
        pendingDiscussion = nil
        bodyScrollView.contentView.scroll(to: .zero)
        let shownBefore = blockSlots.shown
        blockSlots.shown = 0
        blockSlots.contentHeight = 0
        if !blocks.isEmpty {
            let overview = NSAttributedString(
                string: "Overview",
                attributes: [
                    .font: Self.headingFont(level: 2), .foregroundColor: NSColor.labelColor
                ])
            pendingDiscussion = PendingDiscussion(
                blocks: ArraySlice([.heading(level: 2, text: overview)] + blocks), width: width,
                chipBackground: chipBackground)
            buildPendingBlocks()
        }
        for slot in blockSlots.slots[blockSlots.shown ..< max(shownBefore, blockSlots.shown)] {
            slot.view.isHidden = true
        }
    }

    /// Builds the next blocks once the body's visible end comes within a panel's height of the built ones' end, and
    /// grows the scrolling document to their end. Nothing is laid out or measured whole here: with every block built so
    /// far in it, each scroll would cost more than the last.
    func bodyDidScroll() {
        guard pendingDiscussion != nil,
            bodyScrollView.contentView.bounds.maxY >= bodyDocument.frame.height - HoverPanelSizing.maxHeight
        else { return }
        buildPendingBlocks()
        bodyDocument.setFrameSize(NSSize(width: bodyDocument.frame.width, height: blockSlots.contentHeight))
        bodyScrollView.reflectScrolledClipView(bodyScrollView.contentView)
    }

    /// Shows pending blocks, spaced wider above a heading and tighter below it, until they add up to the panel's
    /// greatest height, which leaves the body scrolling while any remain, or until none is left; returns the height
    /// they add, their spacing included.
    @discardableResult
    private func buildPendingBlocks() -> CGFloat {
        guard var pending = pendingDiscussion else { return 0 }
        var filled: CGFloat = 0
        while filled < HoverPanelSizing.maxHeight {
            if var open = pending.openCode {
                filled += showNextChunk(of: &open)
                pending.openCode = open.isComplete ? nil : open
                continue
            }
            guard let block = pending.blocks.popFirst() else { break }
            let isHeading = if case .heading = block { true } else { false }
            let spacing = pending.last.map { Self.spacing(after: $0, beforeHeading: isHeading) } ?? 0
            let top = blockSlots.contentHeight + spacing
            let (slot, open) = showNext(block, at: top, width: pending.width, chipBackground: pending.chipBackground)
            let height = slot.shownHeight
            blockSlots.contentHeight = top + height
            filled += spacing + height
            pending.last = (slot.view, isHeading)
            pending.openCode = open
        }
        pendingDiscussion = pending.blocks.isEmpty && pending.openCode == nil ? nil : pending
        return filled
    }

    /// Shows `block` at the body's next place, `top` points down the document: in the view already there when it is
    /// of the block's kind and width, and otherwise in a new view that takes its place. Returns the view's slot, and a
    /// long code block's lines still to show.
    private func showNext(
        _ block: HoverDocument.Block, at top: CGFloat, width: CGFloat, chipBackground: NSColor?
    ) -> (slot: HoverBlockSlot, openCode: OpenCodeBlock?) {
        let index = blockSlots.shown
        blockSlots.shown += 1
        let kind = HoverBlockSlot.Kind(block)
        if index < blockSlots.slots.count {
            let existing = blockSlots.slots[index]
            if existing.kind == kind, kind.isReusable, existing.width == width {
                let open = configure(existing, with: block, chipBackground: chipBackground, lazily: true)
                existing.top?.constant = top
                existing.view.isHidden = false
                return (existing, open)
            }
            existing.view.removeFromSuperview()
        }
        let made = makeSlot(for: block, width: width, chipBackground: chipBackground, lazily: true)
        var slot = made.slot
        bodyDocument.addSubview(slot.view)
        let pin = slot.view.topAnchor.constraint(equalTo: bodyDocument.topAnchor, constant: top)
        NSLayoutConstraint.activate([pin, slot.view.leadingAnchor.constraint(equalTo: bodyDocument.leadingAnchor)])
        slot.top = pin
        if index < blockSlots.slots.count { blockSlots.slots[index] = slot } else { blockSlots.slots.append(slot) }
        return (slot, made.openCode)
    }

    /// Shows the next chunk of `open`'s lines under those it shows, and returns the height they add.
    private func showNextChunk(of open: inout OpenCodeBlock) -> CGFloat {
        let start = open.shownEnd + 1
        let end = HoverCodeChunks.end(of: open.code.string as NSString, from: start)
        let lines = open.code.attributedSubstring(from: NSRange(location: start, length: end - start))
        let height = Self.measuredHeight(
            of: lines, width: open.slot.width - 2 * HoverPanelMetrics.chipHorizontalPadding)
        // From the newline that ends the lines shown, which the chunk measured alone does without.
        let added = open.code.attributedSubstring(from: NSRange(location: open.shownEnd, length: end - open.shownEnd))
        open.slot.textView?.textStorage?.append(added)
        open.slot.height?.constant += height
        open.shownEnd = end
        blockSlots.contentHeight += height
        return height
    }

    /// The space between `previous` and the block after it: wider above a heading and tighter below one.
    private static func spacing(after previous: HoverBuiltBlock, beforeHeading isHeading: Bool) -> CGFloat {
        if previous.isHeading { return HoverBlockMetrics.afterHeading }
        return isHeading ? HoverBlockMetrics.beforeHeading : HoverBlockMetrics.blockSpacing
    }

    /// Adds a view per block to `stack`, as an item's or a quote's content, spaced as the body's blocks are.
    private func fill(
        _ stack: NSStackView, with blocks: [HoverDocument.Block], width: CGFloat, chipBackground: NSColor?
    ) {
        var previous: HoverBuiltBlock?
        for block in blocks {
            let (slot, _) = makeSlot(for: block, width: width, chipBackground: chipBackground, lazily: false)
            let isHeading = if case .heading = block { true } else { false }
            stack.addArrangedSubview(slot.view)
            if let previous {
                stack.setCustomSpacing(Self.spacing(after: previous, beforeHeading: isHeading), after: previous.view)
            }
            previous = (slot.view, isHeading)
        }
    }

    /// A new view for `block`, showing it as ``configure(_:with:chipBackground:lazily:)`` does.
    private func makeSlot(
        for block: HoverDocument.Block, width: CGFloat, chipBackground: NSColor?, lazily: Bool
    ) -> (slot: HoverBlockSlot, openCode: OpenCodeBlock?) {
        let kind = HoverBlockSlot.Kind(block)
        let slot: HoverBlockSlot
        switch block {
            case .paragraph, .heading:
                let view = Self.makeProseTextView(linkDelegate: linkDelegate)
                view.widthAnchor.constraint(equalToConstant: width).isActive = true
                let height = view.heightAnchor.constraint(equalToConstant: 0)
                height.isActive = true
                slot = HoverBlockSlot(kind: kind, view: view, width: width, textView: view, height: height)
            case .code:
                let view = Self.makeCodeTextView(linkDelegate: linkDelegate)
                let chip = Self.makeChip()
                Self.configureChip(chip, around: view)
                chip.widthAnchor.constraint(equalToConstant: width).isActive = true
                let height = chip.heightAnchor.constraint(equalToConstant: 0)
                height.isActive = true
                slot = HoverBlockSlot(kind: kind, view: chip, width: width, textView: view, height: height)
            case .list(let ordered, let start, let items):
                let view = listBlock(
                    ordered: ordered, start: start, items: items, width: width, chipBackground: chipBackground)
                slot = HoverBlockSlot(kind: kind, view: view, width: width, textView: nil, height: nil)
            case .quote(let blocks):
                let view = quoteBlock(blocks, width: width, chipBackground: chipBackground)
                slot = HoverBlockSlot(kind: kind, view: view, width: width, textView: nil, height: nil)
            case .rule:
                let rule = Self.makeDivider()
                rule.widthAnchor.constraint(equalToConstant: width).isActive = true
                slot = HoverBlockSlot(kind: kind, view: rule, width: width, textView: nil, height: nil)
        }
        return (slot, configure(slot, with: block, chipBackground: chipBackground, lazily: lazily))
    }

    /// Shows `block` in `slot`'s view, of the block's kind: its text sized to the slot's width, and code in a box like
    /// the declaration's, on the hovered pane's background so its colors read as they do there. `lazily`, a long code
    /// block shows its first chunk of lines, and the rest are returned for the body to show as it scrolls to them.
    private func configure(
        _ slot: HoverBlockSlot, with block: HoverDocument.Block, chipBackground: NSColor?, lazily: Bool
    ) -> OpenCodeBlock? {
        switch block {
            case .paragraph(let text), .heading(_, let text):
                slot.textView?.textStorage?.setAttributedString(text)
                slot.height?.constant = Self.measuredHeight(of: text, width: slot.width)
                return nil
            case .code(let code):
                (slot.view as? NSBox)?.fillColor = chipBackground ?? .clear
                let end = lazily ? HoverCodeChunks.end(of: code.string as NSString, from: 0) : code.length
                let shown =
                    end == code.length ? code : code.attributedSubstring(from: NSRange(location: 0, length: end))
                slot.textView?.textStorage?.setAttributedString(shown)
                let innerWidth = slot.width - 2 * HoverPanelMetrics.chipHorizontalPadding
                slot.height?.constant =
                    Self.measuredHeight(of: shown, width: innerWidth) + 2 * HoverPanelMetrics.chipVerticalPadding
                return end == code.length ? nil : OpenCodeBlock(code: code, shownEnd: end, slot: slot)
            case .list, .quote, .rule:
                return nil
        }
    }

    /// A row per item: its marker, a bullet or its number, then its own blocks.
    private func listBlock(
        ordered: Bool, start: Int, items: [[HoverDocument.Block]], width: CGFloat, chipBackground: NSColor?
    ) -> NSView {
        let list = Self.makeBlockStack()
        list.spacing = HoverBlockMetrics.itemSpacing
        let contentWidth = width - HoverBlockMetrics.markerWidth
        for (offset, item) in items.enumerated() {
            let marker = NSTextField(labelWithString: ordered ? "\(start + offset)." : "•")
            marker.font = .systemFont(ofSize: HoverTypography.bodySize)
            marker.textColor = .secondaryLabelColor
            marker.translatesAutoresizingMaskIntoConstraints = false
            marker.widthAnchor.constraint(equalToConstant: HoverBlockMetrics.markerWidth).isActive = true
            let content = Self.makeBlockStack()
            fill(content, with: item, width: contentWidth, chipBackground: chipBackground)
            content.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
            let row = Self.makeRow([marker, content])
            row.widthAnchor.constraint(equalToConstant: width).isActive = true
            list.addArrangedSubview(row)
        }
        list.widthAnchor.constraint(equalToConstant: width).isActive = true
        return list
    }

    /// The quoted blocks, set in behind a bar along their leading edge.
    private func quoteBlock(_ blocks: [HoverDocument.Block], width: CGFloat, chipBackground: NSColor?) -> NSView {
        let contentWidth = width - HoverBlockMetrics.quoteBarWidth - HoverBlockMetrics.quoteGap
        let content = Self.makeBlockStack()
        fill(content, with: blocks, width: contentWidth, chipBackground: chipBackground)
        content.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        let bar = NSBox()
        bar.boxType = .custom
        bar.borderWidth = 0
        bar.fillColor = .tertiaryLabelColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.widthAnchor.constraint(equalToConstant: HoverBlockMetrics.quoteBarWidth).isActive = true
        let row = Self.makeRow([bar, content])
        row.spacing = HoverBlockMetrics.quoteGap
        bar.heightAnchor.constraint(equalTo: content.heightAnchor).isActive = true
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
    }

    // MARK: Factories

    /// A vertical, leading-aligned stack of blocks.
    static func makeBlockStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = HoverBlockMetrics.blockSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private static func makeRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// The symbol's name above its abstract, wrapping within the panel.
    static func makeTitleLabel() -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = HoverTypography.title
        label.textColor = .labelColor
        // Selectable only through the text views, whose link clicks the panel vets; a field has no such delegate.
        label.isSelectable = false
        label.preferredMaxLayoutWidth = HoverPanelSizing.width - 2 * HoverPanelMetrics.edgeInset
        return label
    }

    /// A hairline rule across whatever width its container gives it.
    static func makeDivider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private static func headingFont(level: Int) -> NSFont {
        let (size, weight) = HoverTypography.heading(level: level)
        return .systemFont(ofSize: size, weight: weight)
    }
}
