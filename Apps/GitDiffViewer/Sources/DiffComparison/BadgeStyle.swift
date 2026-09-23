/// The vocabulary and pure resolver behind a change badge's look; the app tier maps it to concrete colours.

/// Which colour scheme a change badge's letter is drawn in.
package enum BadgeScheme: String, CaseIterable, Identifiable, Codable {
    /// The app's own red/green/orange/purple mapping.
    case classic
    /// Xcode's source control colours: green for an addition, blue for a modification or a rename, red for a
    /// deletion.
    case xcode

    package var id: String { rawValue }
}

/// The kind of change a badge names, independent of the app tier's `FileChangeSummary.Kind`.
package enum BadgeChangeKind: Equatable, Sendable {
    case added
    case deleted
    case modified
    case renamed
}

/// Where a change stands relative to git's index: whether it would show in a committed diff (``staged``), only in
/// the working tree against the index (``unstaged``), or is a new path the index has never seen (``untracked``).
package enum BadgeChangeState: Equatable, Sendable {
    case staged
    case unstaged
    case untracked
}

/// A semantic colour a badge names; the app tier maps each one to a concrete `NSColor`/`Color`.
package enum BadgeColorToken: Equatable, Sendable {
    case green
    case blue
    case red
    case orange
    case purple
}

/// A badge's fill: nothing (a stroked badge shows the window/row background through), a flat colour, or white (the
/// inverted look a focused, selected row's badge takes).
package enum BadgeFill: Equatable, Sendable {
    case none
    case token(BadgeColorToken)
    case white
}

/// A badge's letter colour: white (on a filled, coloured badge), a semantic colour (on a stroked or inverted
/// badge), or the row's primary text colour.
package enum BadgeTextColor: Equatable, Sendable {
    case white
    case token(BadgeColorToken)
    case primary
}

/// The resolved look of one badge: its fill, its stroke (nil for a filled badge), and its text colour.
package struct BadgeStyle: Equatable, Sendable {
    package let fill: BadgeFill
    package let stroke: BadgeColorToken?
    package let text: BadgeTextColor

    package init(fill: BadgeFill, stroke: BadgeColorToken?, text: BadgeTextColor) {
        self.fill = fill
        self.stroke = stroke
        self.text = text
    }
}

/// Resolves a change badge's look from the scheme, the kind of change, where it stands against the index, and the
/// row's selection and focus.
package enum BadgeStyleResolver {
    /// The colour `kind` names under `scheme`; ``BadgeScheme`` describes each mapping.
    package static func colorToken(for kind: BadgeChangeKind, scheme: BadgeScheme) -> BadgeColorToken {
        switch scheme {
            case .classic:
                switch kind {
                    case .added: .green
                    case .deleted: .red
                    case .modified: .orange
                    case .renamed: .purple
                }
            case .xcode:
                switch kind {
                    case .added: .green
                    case .deleted: .red
                    case .modified: .blue
                    case .renamed: .blue
                }
        }
    }

    /// The badge's look for one row: filled for a ``BadgeChangeState/staged`` change, stroked otherwise, and
    /// inverted to a white fill while the row is selected in a focused list.
    package static func resolve(
        scheme: BadgeScheme, kind: BadgeChangeKind, state: BadgeChangeState, isSelected: Bool, isFocused: Bool
    ) -> BadgeStyle {
        let token = colorToken(for: kind, scheme: scheme)
        guard isSelected, isFocused else {
            return state == .staged
                ? BadgeStyle(fill: .token(token), stroke: nil, text: .white)
                : BadgeStyle(fill: .none, stroke: token, text: .token(token))
        }
        return BadgeStyle(fill: .white, stroke: nil, text: .token(token))
    }
}

/// The precedence between a pinned light/dark appearance and one derived from the theme's background luminance.
package enum AppearancePrecedence {
    /// A background whose relative luminance (0 black, 1 white) falls below this reads as a dark theme.
    package static let darkLuminanceThreshold: Double = 0.5

    /// The appearance the window presents: an explicit light or dark pin wins, and `.system` follows the theme's
    /// luminance only when `matchesTheme` is on and a theme is selected (`themeIsDark` non-nil).
    package static func resolve(
        explicit: AppearanceScheme, matchesTheme: Bool, themeIsDark: Bool?
    ) -> AppearanceScheme {
        guard explicit == .system else { return explicit }
        guard matchesTheme, let themeIsDark else { return .system }
        return themeIsDark ? .dark : .light
    }
}
