package import AppKit
import CoreText
import DiffCore
package import DiffRendering
package import Foundation
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
    /// The space above a card's first row and below its last: none, so a card's body is its rows.
    package static let verticalInset: CGFloat = 0

    package let rendered: RenderedText
    /// The space above the first row, which the gutter and the height read from each layout: ``verticalInset``, and
    /// the band of a gap at the top of the file (book DIFF-02). A displaying view insets its text by it.
    package let inset: CGFloat
    /// The space below the last row: ``verticalInset``, and the band of a gap at the end of the file.
    package let bottomInset: CGFloat
    package let contentStorage = NSTextContentStorage()
    package let layoutManager = NSTextLayoutManager()
    /// Delegate for every layout manager on `contentStorage`, so a displaying view colours rows the same way.
    package let fragmentProvider: DiffFragmentProvider
    private let container = NSTextContainer(size: NSSize(width: 0, height: DiffPaneMetrics.unboundedExtent))
    package private(set) var width: CGFloat = 0
    /// The width a displaying view needs: the longest line or the pane, whichever is wider, when lines do not wrap;
    /// the container width otherwise.
    package private(set) var contentWidth: CGFloat = 0
    /// The mode and pane width of the last ``layOut(mode:viewportWidth:)``; without wrapping, sizes are known
    /// without layout.
    private var laidOut: (mode: WrapMode, viewportWidth: CGFloat)?
    /// ``height`` since the text was last laid out or respaced.
    private var measuredHeight: CGFloat?
    private lazy var unwrappedWidth = rendered.measuredUnwrappedWidth()

    package init(rendered: RenderedText) {
        self.rendered = rendered
        inset = Self.verticalInset + rendered.bandAbove
        bottomInset = Self.verticalInset + rendered.bandBelow
        fragmentProvider = DiffFragmentProvider(rendered: rendered)
        container.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        container.widthTracksTextView = false
        layoutManager.textContainer = container
        layoutManager.delegate = fragmentProvider
        contentStorage.addTextLayoutManager(layoutManager)
        if let storage = contentStorage.textStorage {
            storage.setAttributedString(rendered.attributed)
            rendered.padEmptyLastRow(in: storage)
        }
    }

    /// Lays the text out for `mode` in a pane `viewportWidth` wide; a no-op when already laid out for both.
    ///
    /// Without wrapping every row is one line, so nothing is laid out: the width and ``height`` follow from the
    /// rows, and a displaying view lays out only what it shows.
    /// - Complexity: O(1) without wrapping once ``RenderedText/measuredUnwrappedWidth()`` is known, and when
    ///   nothing changed; O(rows) otherwise.
    package func layOut(mode: WrapMode, viewportWidth: CGFloat) {
        if let laidOut, laidOut.mode == mode, laidOut.viewportWidth == viewportWidth { return }
        laidOut = (mode, viewportWidth)
        measuredHeight = nil
        if mode == .none {
            contentWidth = max(unwrappedWidth, viewportWidth)
            fragmentProvider.metrics.width = contentWidth
            return
        }
        let width =
            if case .column(let column) = mode {
                DiffPalette.wrapWidth(
                    column: column, font: rendered.palette.font, padding: container.lineFragmentPadding)
            } else {
                viewportWidth
            }
        if width != self.width {
            self.width = width
            container.size = NSSize(width: max(width, 1), height: DiffPaneMetrics.unboundedExtent)
            layoutManager.invalidateLayout(for: layoutManager.documentRange)
        }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        contentWidth = max(width, viewportWidth)
        fragmentProvider.metrics.width = contentWidth
    }

    /// Height of the whole document at the current width and row spacing: one line per row without wrapping, and the
    /// gaps' bands.
    /// - Complexity: O(1) once measured; measuring a wrapped text lays out whatever is not laid out yet.
    package var height: CGFloat {
        if let measuredHeight { return measuredHeight }
        let height: CGFloat
        if laidOut?.mode == WrapMode.none {
            height = (rendered.unwrappedTextHeight + inset + bottomInset).rounded(.up)
        } else {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
            height = (layoutManager.usageBoundsForTextContainer.height + inset + bottomInset).rounded(.up)
        }
        measuredHeight = height
        return height
    }

    /// Height of each row's lines, excluding paragraph spacing.
    package func rowHeights() -> [Double] {
        RowSpacing.rowHeights(in: layoutManager)
    }

    /// Sets each row's paragraph spacing so paired rows across two layouts share a height.
    package func apply(spacing: [Double]) {
        if RowSpacing.apply(spacing, to: contentStorage, rendered: rendered) { measuredHeight = nil }
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
        let wasAligned = prepared.map { $0.mode != .none } ?? false
        prepared = (width, mode)
        old.layOut(mode: mode, viewportWidth: width)
        new.layOut(mode: mode, viewportWidth: width)
        guard mode != .none else {
            // One line per row already pairs rows at one height; only an earlier wrapped alignment needs undoing.
            if wasAligned {
                old.apply(spacing: [])
                new.apply(spacing: [])
            }
            return
        }
        let spacing = RowAlignment.spacing(left: old.rowHeights(), right: new.rowHeights())
        old.apply(spacing: spacing.left)
        new.apply(spacing: spacing.right)
    }
}

extension RenderedText {
    private static let nonASCII = CharacterSet(charactersIn: Unicode.Scalar(UInt8(0)) ... Unicode.Scalar(UInt8(0x7F)))
        .inverted

    /// Gives an empty last row a space, so TextKit lays it out as a paragraph of its own. A text ending with a
    /// newline otherwise ends with the extra line TextKit adds after it, which does not take the row's line height
    /// after an empty paragraph and draws in the previous row's colour; the row then ends short of its partner on the
    /// other side. Offsets up to ``attributed``'s length are unchanged.
    /// - Parameter storage: A text storage holding exactly ``attributed``.
    package func padEmptyLastRow(in storage: NSTextStorage) {
        guard let lastStart = lineStarts.last, lastStart == storage.length else { return }
        let attributes: [NSAttributedString.Key: Any]
        if storage.length > 0 {
            attributes = storage.attributes(at: storage.length - 1, effectiveRange: nil)
        } else {
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = palette.defaultLineHeight > 0 ? lineHeight / palette.defaultLineHeight : 1
            attributes = [.font: palette.font, .paragraphStyle: style]
        }
        storage.append(NSAttributedString(string: " ", attributes: attributes))
    }

    /// The width a pane that never wraps needs to show every row whole, line fragment padding and a point of slack
    /// included.
    ///
    /// ``unwrappedWidth`` counts one cell per UTF-16 unit, which a wide character overflows, so the rows holding a
    /// non-ASCII character are measured with Core Text instead.
    /// - Complexity: O(text length), plus one line measurement per non-ASCII row.
    package func measuredUnwrappedWidth() -> CGFloat {
        let text = attributed.string as NSString
        var widest: CGFloat = 0
        if text.rangeOfCharacter(from: Self.nonASCII).location != NSNotFound {
            for (row, start) in lineStarts.enumerated() {
                let end = row + 1 < lineStarts.count ? lineStarts[row + 1] - 1 : text.length
                guard end > start else { continue }
                let range = NSRange(location: start, length: end - start)
                guard text.rangeOfCharacter(from: Self.nonASCII, options: [], range: range).location != NSNotFound
                else { continue }
                let line = CTLineCreateWithAttributedString(
                    attributed.attributedSubstring(from: range) as CFAttributedString)
                widest = max(widest, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            }
        }
        return max(unwrappedWidth, widest + 2 * DiffPaneMetrics.lineFragmentPadding).rounded(.up) + 1
    }
}
