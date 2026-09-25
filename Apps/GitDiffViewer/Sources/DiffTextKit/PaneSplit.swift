package import CoreGraphics

/// How a file's two panes share the length between them, side by side or stacked (book DIFF-01): the old pane takes a
/// ratio of it, the new one the rest, and the divider between them the line it draws.
///
/// Along the axis, the panes share the length less the divider and less what bars cover before the old pane: stacked,
/// the upper pane runs beneath the toolbar and the tab bar (TAB-09), and an even split leaves both panes as much room
/// below them. The ratio is clamped so that neither pane ends shorter than ``minimumPaneLength``; a length too short
/// for two of them splits evenly.
package enum PaneSplit {
    /// The old pane's share before the divider is moved, and once it is double-clicked.
    package static let evenRatio = 0.5
    /// The shortest a pane may become along the axis: a gutter and a few columns side by side, a few rows stacked.
    package static let minimumPaneLength: CGFloat = 120
    /// The line drawn between the panes, the only length neither of them takes.
    package static let dividerThickness: CGFloat = 1
    /// How far across the pointer takes the divider: wider than its line, over the panes' edges, so it stays easy to
    /// hit without drawing anything more.
    package static let hitThickness: CGFloat = 9

    /// The length the panes share: `length` less the divider and the `covered` length before the old pane.
    package static func sharedLength(of length: CGFloat, covered: CGFloat = 0) -> CGFloat {
        max(length - dividerThickness - max(covered, 0), 0)
    }

    /// `ratio` within the bounds that leave each pane at least ``minimumPaneLength``; ``evenRatio`` when the length is
    /// too short for two such panes, or `ratio` is not a number.
    package static func clamped(_ ratio: Double, length: CGFloat, covered: CGFloat = 0) -> Double {
        let shared = sharedLength(of: length, covered: covered)
        guard ratio.isFinite, shared > 2 * minimumPaneLength else { return evenRatio }
        let least = Double(minimumPaneLength / shared)
        return min(max(ratio, least), 1 - least)
    }

    /// The old pane's length along the axis, what bars cover over it included, at `ratio` once clamped, in whole
    /// points: a pane half a point long left its text view taller than its clip view, with half a point to scroll.
    package static func leadingLength(ratio: Double, length: CGFloat, covered: CGFloat = 0) -> CGFloat {
        let shared = sharedLength(of: length, covered: covered)
        let leading = (max(covered, 0) + shared * CGFloat(clamped(ratio, length: length, covered: covered))).rounded()
        return min(max(leading, 0), max(length - dividerThickness, 0))
    }

    /// The ratio a drag of the divider `translation` points towards the new pane gives, from `start`, clamped.
    package static func ratio(
        draggingFrom start: Double, by translation: CGFloat, length: CGFloat, covered: CGFloat = 0
    ) -> Double {
        let shared = sharedLength(of: length, covered: covered)
        guard shared > 0, translation.isFinite else { return clamped(start, length: length, covered: covered) }
        return clamped(start + Double(translation / shared), length: length, covered: covered)
    }
}
