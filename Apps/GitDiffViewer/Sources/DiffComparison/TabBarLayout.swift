// The tab bar's pure decisions, free of SwiftUI and CoreGraphics so they stay cheap to test; the app tier converts
// them to `CGFloat`s and `Color`s where it draws.

/// The tab bar's spacing.
package enum TabBarLayout {
    /// The bar's single rhythm: the gap between adjacent tabs, reused as the inset around the whole row.
    package static let gap: Double = 6
}

/// What a tab's fixed-size leading slot shows: the close button while the pointer is over the tab, otherwise the
/// diff badge, or the neutral icon when the tab has no change to show.
package enum TabSlotContent: Equatable, Sendable {
    case badge
    case icon
    case close

    package static func resolve(isHovering: Bool, hasBadge: Bool) -> TabSlotContent {
        guard !isHovering else { return .close }
        return hasBadge ? .badge : .icon
    }
}

/// How a tab draws in one state: whether it is kept open, whether it is active, and where the pointer is.
package struct TabAppearance: Equatable, Sendable {
    /// A preview tab, which the next single click replaces, sets its name in italics.
    package let isItalic: Bool
    /// A kept-open tab carries a pin after its name.
    package let showsPin: Bool
    /// The active tab draws in the primary ink, every other tab in the secondary one.
    package let usesPrimaryInk: Bool
    /// Opacity of the primary-colour outline; the active tab's is the stronger one whatever the pointer does.
    package let outlineOpacity: Double
    /// Opacity of the primary-colour wash inside the tab; zero unless the pointer is over the tab.
    package let washOpacity: Double
    /// Opacity of the disc behind the close button; zero unless the pointer is over the button and so over the tab,
    /// which keeps a button exit that was never reported from leaving the disc on.
    package let closeDiscOpacity: Double

    /// The look of a tab in this state; `isHoveringClose` counts only while `isHovering` holds.
    package static func resolve(isPinned: Bool, isActive: Bool, isHovering: Bool, isHoveringClose: Bool)
        -> TabAppearance
    {
        TabAppearance(
            isItalic: !isPinned, showsPin: isPinned, usesPrimaryInk: isActive,
            outlineOpacity: isActive ? 0.28 : 0.1, washOpacity: isHovering ? 0.03 : 0,
            closeDiscOpacity: isHovering && isHoveringClose ? 0.12 : 0)
    }

    /// The look of the file list's fixed tab: a kept-open tab's, upright, with neither pin nor close button.
    package static func fixed(isActive: Bool, isHovering: Bool) -> TabAppearance {
        let tab = resolve(isPinned: true, isActive: isActive, isHovering: isHovering, isHoveringClose: false)
        return TabAppearance(
            isItalic: false, showsPin: false, usesPrimaryInk: tab.usesPrimaryInk, outlineOpacity: tab.outlineOpacity,
            washOpacity: tab.washOpacity, closeDiscOpacity: 0)
    }
}
