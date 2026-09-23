/// How a file card lays out its panes. A card shows its file inline or side by side; the stacked layout is for a
/// single file, and a card shows it side by side.
package enum CardLayout: Equatable, Sendable {
    case inline
    case split

    /// The card layout for the layout chosen in the settings.
    package init(_ mode: ViewMode) {
        self = mode == .inline ? .inline : .split
    }
}

extension ViewMode {
    /// The layout a file card uses for this mode.
    package var cardLayout: CardLayout { CardLayout(self) }

    /// Whether the layout controls offer this mode while `detail` is on screen. The card list shows stacked side by
    /// side, so the controls disable stacked there instead of hiding it; the stored setting stays as chosen.
    package func isAvailable(showing detail: DetailState) -> Bool {
        self != .stacked || detail != .cards
    }

    /// The layout drawn for this mode while `detail` is on screen, which the layout picker shows as selected.
    package func drawn(showing detail: DetailState) -> ViewMode {
        isAvailable(showing: detail) ? self : .split
    }
}
