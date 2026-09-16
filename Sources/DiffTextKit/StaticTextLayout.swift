import AppKit
import DiffCore
import DiffRendering
import Foundation
import SwiftUI

/// How a pane breaks lines.
package enum WrapMode: Hashable {
    /// At the pane's width.
    case viewport
    /// At a fixed number of characters.
    case column(Int)
    /// Never; the pane scrolls sideways.
    case none

    package init(wrapsLines: Bool, column: Int) {
        self = wrapsLines ? (column > 0 ? .column(column) : .viewport) : .none
    }
}

/// A TextKit 2 text system whose layout manager is not attached to any view, so measuring and re-laying it out
/// never touches AppKit layout. A card pane displays it by adding its own text view's layout manager to
/// `contentStorage`, so the text and the row spacing computed here are shown without being copied.
@MainActor
package final class StaticTextLayout {
    package let rendered: RenderedText
    package let inset = DiffPaneMetrics.containerInset
    package let contentStorage = NSTextContentStorage()
    package let layoutManager = NSTextLayoutManager()
    /// Delegate for every layout manager on `contentStorage`, so a displaying view colours rows the same way.
    package let fragmentProvider: DiffFragmentProvider
    private let container = NSTextContainer(size: NSSize(width: 0, height: DiffPaneMetrics.unboundedExtent))
    package private(set) var width: CGFloat = 0
    /// Widest line laid out, used when lines do not wrap; the container width otherwise.
    package private(set) var contentWidth: CGFloat = 0

    package init(rendered: RenderedText) {
        self.rendered = rendered
        fragmentProvider = DiffFragmentProvider(rendered: rendered)
        container.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        container.widthTracksTextView = false
        layoutManager.textContainer = container
        layoutManager.delegate = fragmentProvider
        contentStorage.addTextLayoutManager(layoutManager)
        contentStorage.textStorage?.setAttributedString(rendered.attributed)
    }

    /// Lays the text out for `mode` in a pane `viewportWidth` wide.
    package func layOut(mode: WrapMode, viewportWidth: CGFloat) {
        let width: CGFloat = switch mode {
        case .viewport: viewportWidth
        case .column(let column): DiffPalette.wrapWidth(column: column, font: rendered.palette.font, padding: container.lineFragmentPadding)
        case .none: DiffPaneMetrics.unboundedExtent
        }
        if width != self.width {
            self.width = width
            container.size = NSSize(width: max(width, 1), height: DiffPaneMetrics.unboundedExtent)
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let used = layoutManager.usageBoundsForTextContainer.width + 2 * container.lineFragmentPadding
        contentWidth = mode == .none ? max(used, viewportWidth) : max(width, viewportWidth)
        fragmentProvider.metrics.width = contentWidth
    }

    /// Height of the whole document at the current width.
    package var height: CGFloat {
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        return (layoutManager.usageBoundsForTextContainer.height + 2 * inset).rounded(.up)
    }

    /// Height of each row's lines, excluding paragraph spacing.
    package func rowHeights() -> [Double] {
        RowSpacing.rowHeights(in: layoutManager)
    }

    /// Sets each row's paragraph spacing so paired rows across two layouts share a height.
    package func apply(spacing: [Double]) {
        RowSpacing.apply(spacing, to: contentStorage, rendered: rendered)
    }
}

/// The two sides of a card, aligned row by row at a given width so they can be laid out independently by SwiftUI.
@MainActor
package final class CardLayouts {
    package let renderID: UUID
    package let old: StaticTextLayout?
    package let new: StaticTextLayout?
    package let unified: StaticTextLayout?
    private var prepared: (width: CGFloat, mode: WrapMode)?

    package init(rendered: RenderedDiff) {
        renderID = rendered.id
        old = rendered.old.map(StaticTextLayout.init(rendered:))
        new = rendered.new.map(StaticTextLayout.init(rendered:))
        unified = rendered.unified.map(StaticTextLayout.init(rendered:))
    }

    /// Lays out both split sides for a pane width and wrap mode and equalizes their rows; a no-op when already
    /// prepared for the same width and mode.
    package func prepareSplit(width: CGFloat, mode: WrapMode) {
        guard prepared?.width != width || prepared?.mode != mode, let old, let new else { return }
        prepared = (width, mode)
        old.layOut(mode: mode, viewportWidth: width)
        new.layOut(mode: mode, viewportWidth: width)
        let spacing = RowAlignment.spacing(left: old.rowHeights(), right: new.rowHeights())
        old.apply(spacing: spacing.left)
        new.apply(spacing: spacing.right)
    }
}

