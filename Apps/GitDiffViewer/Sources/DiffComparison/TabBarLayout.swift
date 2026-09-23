/// The tab bar's own pure layout decisions -- kept independent of SwiftUI (even of `CGFloat`'s own home,
/// CoreGraphics) so they are cheap to test; the app tier only draws what these decide, converting to `CGFloat` at
/// the point of use the same way it already turns ``DiffComparison`` statuses into concrete `Color`s.

/// The bar's single rhythm: the gap between adjacent tabs, reused as the inset around the whole row on every side,
/// so the negative space inside the bar reads the same everywhere -- one constant instead of two that could drift
/// apart.
package enum TabBarLayout {
    package static let gap: Double = 6
}

/// What a tab's fixed-size leading slot shows: the diff badge when the pointer isn't over the tab and it carries a
/// change, the neutral icon as that slot's fallback when it doesn't, or the close button whenever the pointer is
/// over the tab -- one table so hover state and change status can never leave the slot showing two things, or
/// nothing, at once.
package enum TabSlotContent: Equatable, Sendable {
    case badge
    case icon
    case close

    /// Hovering always wins: the close button is the one piece of chrome a pointer's presence should reveal,
    /// whether or not the tab underneath it has a change to show.
    package static func resolve(isHovering: Bool, hasBadge: Bool) -> TabSlotContent {
        guard !isHovering else { return .close }
        return hasBadge ? .badge : .icon
    }
}
