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

extension HoverDocPanel {
    /// Rebuilds ``bodyStack`` from `blocks`, under an Overview heading, each block its own view `width` wide. Only the
    /// blocks the panel can show at once are built: every block is a view measured and laid out, and a discussion of
    /// a few hundred of them took seconds (`HoverBuildBenchmark`). The rest are built as the body scrolls towards
    /// them, in ``bodyDidScroll()``.
    func renderDiscussion(_ blocks: [HoverDocument.Block], chipBackground: NSColor?, width: CGFloat) {
        // Dropped first, so the scroll back to the top builds nothing of the discussion shown before.
        pendingDiscussion = nil
        bodyScrollView.contentView.scroll(to: .zero)
        bodyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !blocks.isEmpty else { return }
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

    /// Builds the next blocks once the body's visible end comes within a panel's height of the built ones' end, and
    /// grows the scrolling document to hold them.
    func bodyDidScroll() {
        guard pendingDiscussion != nil,
            bodyScrollView.contentView.bounds.maxY >= bodyDocument.frame.height - HoverPanelSizing.maxHeight
        else { return }
        buildPendingBlocks()
        bodyStack.layoutSubtreeIfNeeded()
        bodyDocument.setFrameSize(NSSize(width: bodyDocument.frame.width, height: bodyStack.fittingSize.height))
        bodyScrollView.reflectScrolledClipView(bodyScrollView.contentView)
    }

    /// Builds pending blocks until they add up to the panel's greatest height, which leaves the body scrolling while
    /// any remain, or until none is left.
    private func buildPendingBlocks() {
        guard var pending = pendingDiscussion else { return }
        let (rest, last) = fill(
            bodyStack, with: pending.blocks, width: pending.width, chipBackground: pending.chipBackground,
            after: pending.last, filling: HoverPanelSizing.maxHeight)
        pending.blocks = rest
        pending.last = last
        pendingDiscussion = rest.isEmpty ? nil : pending
    }

    /// Adds a view per block to `stack`, after `last`, the block already at its end, spaced wider above a heading and
    /// tighter below it; stops once the views added are `height` tall. Returns the blocks left and the last one added.
    @discardableResult
    private func fill(
        _ stack: NSStackView, with blocks: ArraySlice<HoverDocument.Block>, width: CGFloat, chipBackground: NSColor?,
        after last: HoverBuiltBlock? = nil, filling height: CGFloat = .infinity
    ) -> (rest: ArraySlice<HoverDocument.Block>, last: HoverBuiltBlock?) {
        var previous = last
        var rest = blocks
        var filled: CGFloat = 0
        while let block = rest.first, filled < height {
            rest = rest.dropFirst()
            let view = blockView(block, width: width, chipBackground: chipBackground)
            let isHeading = if case .heading = block { true } else { false }
            stack.addArrangedSubview(view)
            var spacing: CGFloat = 0
            if let previous {
                spacing =
                    previous.isHeading
                    ? HoverBlockMetrics.afterHeading
                    : isHeading ? HoverBlockMetrics.beforeHeading : HoverBlockMetrics.blockSpacing
                stack.setCustomSpacing(spacing, after: previous.view)
            }
            // Measured only when there is a height to fill: an item's or a quote's blocks are built whole.
            if height.isFinite { filled += spacing + view.fittingSize.height }
            previous = (view, isHeading)
        }
        return (rest, previous)
    }

    private func blockView(_ block: HoverDocument.Block, width: CGFloat, chipBackground: NSColor?) -> NSView {
        switch block {
            case .paragraph(let text), .heading(_, let text):
                return textBlock(text, width: width)
            case .code(let code):
                return codeBlock(code, width: width, chipBackground: chipBackground)
            case .list(let ordered, let start, let items):
                return listBlock(
                    ordered: ordered, start: start, items: items, width: width, chipBackground: chipBackground)
            case .quote(let blocks):
                return quoteBlock(blocks, width: width, chipBackground: chipBackground)
            case .rule:
                let rule = Self.makeDivider()
                rule.widthAnchor.constraint(equalToConstant: width).isActive = true
                return rule
        }
    }

    /// A selectable text view sized to `text` at `width`.
    private func textBlock(_ text: NSAttributedString, width: CGFloat) -> NSView {
        let view = Self.makeProseTextView(linkDelegate: linkDelegate)
        view.textStorage?.setAttributedString(text)
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        view.heightAnchor.constraint(equalToConstant: Self.measuredHeight(of: text, width: width)).isActive = true
        return view
    }

    /// The code in a box like the declaration's, on the hovered pane's background so its colors read as they do there.
    private func codeBlock(_ code: NSAttributedString, width: CGFloat, chipBackground: NSColor?) -> NSView {
        let view = Self.makeCodeTextView(linkDelegate: linkDelegate)
        view.textStorage?.setAttributedString(code)
        let chip = Self.makeChip()
        Self.configureChip(chip, around: view)
        chip.fillColor = chipBackground ?? .clear
        let innerWidth = width - 2 * HoverPanelMetrics.chipHorizontalPadding
        let height = Self.measuredHeight(of: code, width: innerWidth) + 2 * HoverPanelMetrics.chipVerticalPadding
        chip.widthAnchor.constraint(equalToConstant: width).isActive = true
        chip.heightAnchor.constraint(equalToConstant: height).isActive = true
        return chip
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
            fill(content, with: item[...], width: contentWidth, chipBackground: chipBackground)
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
        fill(content, with: blocks[...], width: contentWidth, chipBackground: chipBackground)
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
