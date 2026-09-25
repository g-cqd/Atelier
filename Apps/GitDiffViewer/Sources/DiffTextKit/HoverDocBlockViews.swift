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

/// The last block a stack holds, which sets the spacing above the next.
typealias HoverBuiltBlock = (view: NSView, isHeading: Bool)

/// A discussion's blocks still to build, with what building them takes.
struct PendingDiscussion {
    var blocks: ArraySlice<HoverDocument.Block>
    let width: CGFloat
    let chipBackground: NSColor?
    var last: HoverBuiltBlock?
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
}

/// The body's top-level block views, in the stack's order: the first ``shown`` show the discussion, and the rest,
/// hidden, wait for a later block of their kind. A hidden view leaves the stack's layout, and hiding it costs a
/// fraction of removing it: taking a few hundred views out of the stack took 60 to 360 ms.
struct HoverBlockSlots {
    var slots: [HoverBlockSlot] = []
    var shown = 0
}

extension HoverDocPanel {
    /// Shows `blocks` in ``bodyStack``, under an Overview heading, each block its own view `width` wide. Only the
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
    /// grows the scrolling document by their height. The stack is neither laid out nor measured whole here: with every
    /// block built so far in it, each scroll would cost more than the last.
    func bodyDidScroll() {
        guard pendingDiscussion != nil,
            bodyScrollView.contentView.bounds.maxY >= bodyDocument.frame.height - HoverPanelSizing.maxHeight
        else { return }
        let added = buildPendingBlocks()
        bodyDocument.setFrameSize(NSSize(width: bodyDocument.frame.width, height: bodyDocument.frame.height + added))
        bodyScrollView.reflectScrolledClipView(bodyScrollView.contentView)
    }

    /// Shows pending blocks, spaced wider above a heading and tighter below it, until they add up to the panel's
    /// greatest height, which leaves the body scrolling while any remain, or until none is left; returns the height
    /// they add, their spacing included.
    @discardableResult
    private func buildPendingBlocks() -> CGFloat {
        guard var pending = pendingDiscussion else { return 0 }
        var filled: CGFloat = 0
        while filled < HoverPanelSizing.maxHeight, let block = pending.blocks.popFirst() {
            let view = showNext(block, width: pending.width, chipBackground: pending.chipBackground)
            let isHeading = if case .heading = block { true } else { false }
            let spacing = pending.last.map { Self.spacing(after: $0, beforeHeading: isHeading) } ?? 0
            if let last = pending.last { bodyStack.setCustomSpacing(spacing, after: last.view) }
            filled += spacing + view.fittingSize.height
            pending.last = (view, isHeading)
        }
        pendingDiscussion = pending.blocks.isEmpty ? nil : pending
        return filled
    }

    /// Shows `block` at the body's next place: in the view already there when it is of the block's kind and width,
    /// and otherwise in a new view that takes its place.
    private func showNext(_ block: HoverDocument.Block, width: CGFloat, chipBackground: NSColor?) -> NSView {
        let index = blockSlots.shown
        blockSlots.shown += 1
        let kind = HoverBlockSlot.Kind(block)
        if index < blockSlots.slots.count {
            let existing = blockSlots.slots[index]
            if existing.kind == kind, kind.isReusable, existing.width == width {
                configure(existing, with: block, chipBackground: chipBackground)
                existing.view.isHidden = false
                return existing.view
            }
            let slot = makeSlot(for: block, width: width, chipBackground: chipBackground)
            bodyStack.insertArrangedSubview(slot.view, at: index)
            existing.view.removeFromSuperview()
            blockSlots.slots[index] = slot
            return slot.view
        }
        let slot = makeSlot(for: block, width: width, chipBackground: chipBackground)
        bodyStack.addArrangedSubview(slot.view)
        blockSlots.slots.append(slot)
        return slot.view
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
            let slot = makeSlot(for: block, width: width, chipBackground: chipBackground)
            let isHeading = if case .heading = block { true } else { false }
            stack.addArrangedSubview(slot.view)
            if let previous {
                stack.setCustomSpacing(Self.spacing(after: previous, beforeHeading: isHeading), after: previous.view)
            }
            previous = (slot.view, isHeading)
        }
    }

    /// A new view for `block`, showing it.
    private func makeSlot(for block: HoverDocument.Block, width: CGFloat, chipBackground: NSColor?) -> HoverBlockSlot {
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
        configure(slot, with: block, chipBackground: chipBackground)
        return slot
    }

    /// Shows `block` in `slot`'s view, of the block's kind: its text sized to the slot's width, and code in a box like
    /// the declaration's, on the hovered pane's background so its colors read as they do there.
    private func configure(_ slot: HoverBlockSlot, with block: HoverDocument.Block, chipBackground: NSColor?) {
        switch block {
            case .paragraph(let text), .heading(_, let text):
                slot.textView?.textStorage?.setAttributedString(text)
                slot.height?.constant = Self.measuredHeight(of: text, width: slot.width)
            case .code(let code):
                slot.textView?.textStorage?.setAttributedString(code)
                (slot.view as? NSBox)?.fillColor = chipBackground ?? .clear
                let innerWidth = slot.width - 2 * HoverPanelMetrics.chipHorizontalPadding
                slot.height?.constant =
                    Self.measuredHeight(of: code, width: innerWidth) + 2 * HoverPanelMetrics.chipVerticalPadding
            case .list, .quote, .rule:
                break
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
