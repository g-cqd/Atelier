package import SwiftUI

/// Two panes side by side with a divider between them, as tall as the taller pane whatever height is proposed.
///
/// The divider lies over the gap between the panes instead of standing in the stack: a divider in an `HStack` takes
/// all the height the stack is offered, so a card measured with an unbounded height came out unbounded.
package struct SideBySidePanes<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    /// - Parameters:
    ///   - width: The pair's width; each pane is built for ``paneWidth(forWidth:)`` of it.
    ///   - leading: The pane on the left, given its width.
    ///   - trailing: The pane on the right, given its width.
    package init(
        width: CGFloat, @ViewBuilder leading: (CGFloat) -> Leading, @ViewBuilder trailing: (CGFloat) -> Trailing
    ) {
        let paneWidth = Self.paneWidth(forWidth: width)
        self.leading = leading(paneWidth)
        self.trailing = trailing(paneWidth)
    }

    /// The divider's width; the panes share the rest.
    package static var dividerWidth: CGFloat { 1 }

    /// The width of each pane in a pair `width` wide; zero when the divider takes it all.
    package static func paneWidth(forWidth width: CGFloat) -> CGFloat {
        max((width - dividerWidth) / 2, 0)
    }

    package var body: some View {
        HStack(alignment: .top, spacing: Self.dividerWidth) {
            leading.frame(maxWidth: .infinity)
            trailing.frame(maxWidth: .infinity)
        }
        .overlay {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Divider()
                Spacer(minLength: 0)
            }
        }
    }
}
