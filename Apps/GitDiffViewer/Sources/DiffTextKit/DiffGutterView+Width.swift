package import AppKit
import DiffRendering

/// The gutter's own width, and the width it shares with a card list's other gutters (book D43, "the gutter's width
/// follows what it shows" and "one gutter width across the card list").
extension DiffGutterView {
    /// Negative space before the change marker layer, so a marker is easy to click without hugging the gutter's own
    /// edge (book D43, `compact-inline-design.md`).
    private static let markerLeadingGap: CGFloat = 2
    /// The gap between the change marker layer and the numbers.
    private static let numberGap: CGFloat = 2

    /// Whether the change layer has anything to draw: the compact view's markers, or, lacking those, the Xcode
    /// change bar; false when neither applies, so the gutter reclaims the layer's own width (book D43, "the gutter's
    /// width follows what it shows"). The compact view leaves ``RenderedText/changes`` empty when it is off, so this
    /// needs no setting of its own.
    private var showsChangeLayer: Bool {
        guard let rendered else { return false }
        return !rendered.changes.isEmpty || rendered.palette.changeBar != nil
    }

    /// The leading edge to the numbers: nothing beyond a small gap when the change layer has nothing to draw;
    /// otherwise the negative space, the change marker layer (book DIFF-04, and D18's change bar, which the layer
    /// holds instead when the Xcode colours are on; back on the leading edge 09-30, reversing D42), and a gap before
    /// the numbers.
    var padding: CGFloat {
        showsChangeLayer ? Self.markerLeadingGap + ChangeMarkerLayout.hitWidth + Self.numberGap : Self.numberGap
    }

    /// The change layer's leading edge, right after the negative space, before the numbers: the compact view's
    /// markers, or, with the Xcode colours, the change bar, never both.
    var changeLayerX: CGFloat { showsChangeLayer ? Self.markerLeadingGap : 0 }

    /// This gutter's own width, on a whole point: the text beside it starts on one, so its clip view is not scrolled
    /// sideways by the fraction AppKit aligns it by.
    private var naturalThickness: CGFloat {
        let columns: CGFloat = style == .dual ? 2 : 1
        return (padding + trailingPadding + columns * metrics.columnWidth + (columns - 1) * columnGap).rounded(.up)
    }

    /// The gutter's width: its own, or, sharing one with a card list's other gutters, the widest any of them needs
    /// (book D43, "one gutter width across the card list").
    package var thickness: CGFloat { max(naturalThickness, widthCoordinator?.sharedWidth ?? 0) }

    /// Registers this gutter's own width with its ``widthCoordinator``, if it has one, so a wider or narrower need
    /// moves the shared width every card's gutter reads back.
    func registerWidth() {
        guard let widthCoordinator else { return }
        widthCoordinator.register(ObjectIdentifier(self), width: naturalThickness) { [weak self] in
            self?.invalidateIntrinsicContentSize()
            self?.needsDisplay = true
        }
    }

    package override var intrinsicContentSize: NSSize {
        NSSize(width: thickness, height: NSView.noIntrinsicMetric)
    }
}
