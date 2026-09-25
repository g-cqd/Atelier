package import SwiftUI

/// A file's two panes, side by side or stacked, with a divider between them that can be dragged to change their
/// share of the length, and double-clicked to split it evenly again (book DIFF-01).
///
/// `ratio` is the old pane's share as stored, which only a finished drag or a double click writes; while the divider
/// is dragged, the panes follow the pointer without writing it. It is shown clamped to the length at hand
/// (``PaneSplit``), and kept as stored, so a window made narrower and wider again gets its panes back.
package struct ResizablePanes<Leading: View, Trailing: View>: View {
    private let axis: Axis
    @Binding private var ratio: Double
    private let covered: CGFloat
    private let leading: Leading
    private let trailing: Trailing

    /// The drag in progress: the ratio shown as it started and the one it shows now.
    @State private var drag: (start: Double, ratio: Double)?

    /// - Parameters:
    ///   - axis: `.horizontal` side by side, `.vertical` stacked.
    ///   - ratio: The old pane's share of the length the two share.
    ///   - covered: How much of the old pane bars cover at its start, which the panes do not share: stacked, the
    ///     bars the upper pane runs beneath.
    ///   - leading: The old pane, on the left or at the top.
    ///   - trailing: The new pane, on the right or at the bottom.
    package init(
        axis: Axis, ratio: Binding<Double>, covered: CGFloat = 0, @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.axis = axis
        _ratio = ratio
        self.covered = covered
        self.leading = leading()
        self.trailing = trailing()
    }

    package var body: some View {
        // The reader hands the drag the length the layout splits, in the pass that lays it out.
        GeometryReader { proxy in
            let length = axis == .horizontal ? proxy.size.width : proxy.size.height
            PaneSplitLayout(axis: axis, ratio: drag?.ratio ?? ratio, covered: covered) {
                leading
                trailing
                PaneDivider(
                    axis: axis, onDrag: { dragged(by: $0, length: length) }, onDragEnd: endDrag, onReset: reset)
            }
        }
    }

    private func dragged(by translation: CGFloat, length: CGFloat) {
        let start = drag?.start ?? PaneSplit.clamped(ratio, length: length, covered: covered)
        let dragged = PaneSplit.ratio(draggingFrom: start, by: translation, length: length, covered: covered)
        drag = (start, dragged)
    }

    private func endDrag() {
        guard let drag else { return }
        self.drag = nil
        if drag.ratio != drag.start { ratio = drag.ratio }
    }

    private func reset() {
        drag = nil
        ratio = PaneSplit.evenRatio
    }
}

/// Lays out the old pane, the new pane and the divider, in that order: the panes at their share of the length with
/// the divider's line between them, and the divider over that line, across the panes' edges, on top of both.
struct PaneSplitLayout: Layout {
    let axis: Axis
    let ratio: Double
    let covered: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let length = axis == .horizontal ? bounds.width : bounds.height
        let leading = PaneSplit.leadingLength(ratio: ratio, length: length, covered: covered)
        let trailingStart = leading + PaneSplit.dividerThickness
        let trailing = max(length - trailingStart, 0)
        let lineMiddle = leading + PaneSplit.dividerThickness / 2
        let hit = PaneSplit.hitThickness
        place(subviews[0], at: 0, length: leading, in: bounds)
        place(subviews[1], at: trailingStart, length: trailing, in: bounds)
        place(subviews[2], at: lineMiddle - hit / 2, length: hit, in: bounds)
    }

    /// Places `subview` `offset` along the axis from the start of `bounds`, `length` long and as wide as `bounds`.
    private func place(_ subview: LayoutSubview, at offset: CGFloat, length: CGFloat, in bounds: CGRect) {
        switch axis {
            case .horizontal:
                subview.place(
                    at: CGPoint(x: bounds.minX + offset, y: bounds.minY), anchor: .topLeading,
                    proposal: ProposedViewSize(width: length, height: bounds.height))
            case .vertical:
                subview.place(
                    at: CGPoint(x: bounds.minX, y: bounds.minY + offset), anchor: .topLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: length))
        }
    }
}

/// ``PaneDividerView`` in SwiftUI.
struct PaneDivider: NSViewRepresentable {
    let axis: Axis
    let onDrag: (CGFloat) -> Void
    let onDragEnd: () -> Void
    let onReset: () -> Void

    func makeNSView(context: Context) -> PaneDividerView {
        let view = PaneDividerView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PaneDividerView, context: Context) {
        view.axis = axis
        view.onDrag = onDrag
        view.onDragEnd = onDragEnd
        view.onReset = onReset
    }
}
