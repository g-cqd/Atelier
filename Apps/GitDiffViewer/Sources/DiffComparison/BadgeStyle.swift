/// The vocabulary and pure resolver behind a change badge's look: what colour it names, whether it is filled or
/// stroked, and how selection and focus invert it -- kept independent of AppKit/SwiftUI so it is cheap to test and
/// so the app tier (which owns the concrete `NSColor`/`Color` mapping) is the only place that needs to draw.

/// Which colour scheme a change badge's letter is drawn in.
package enum BadgeScheme: String, CaseIterable, Identifiable, Codable {
    /// The app's own red/green/orange/purple mapping.
    case classic
    /// Xcode's source control colours: green for an addition, blue for a modification or a rename, red for a
    /// deletion.
    case xcode

    package var id: String { rawValue }
}

/// The kind of change a badge names, independent of the app tier's own `ChangeGlyph`/`FileChangeSummary.Kind`
/// vocabulary so this file has nothing AppKit- or SwiftUI-flavoured to import.
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
/// file list row's selection/focus -- one pure function so every combination is a table, not a view's `if`/`else`.
package enum BadgeStyleResolver {
    /// The colour a kind of change names under a scheme. Xcode's own scheme reads a modification and a rename both
    /// as blue; everything else matches the app's classic mapping.
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

    /// The badge's look for one row.
    ///
    /// - A ``BadgeChangeState/staged`` change (or any change in a committed, ref-to-ref comparison) keeps the
    ///   filled look: a coloured background, white letter.
    /// - An ``BadgeChangeState/unstaged`` or ``BadgeChangeState/untracked`` change strokes instead: a transparent
    ///   fill, a 1pt border and letter in the status colour.
    /// - A row that is selected in a focused (key, active) list inverts whatever the state above produced: a white
    ///   fill, no stroke, the letter in the status colour -- matching how a native list's own selection tints its
    ///   content.
    /// - A row selected in an unfocused list, or not selected at all, keeps the badge exactly as the state alone
    ///   would draw it; only the row's own background changes.
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

/// The precedence between a pinned light/dark appearance and one derived from the selected syntax theme's own
/// background luminance -- pure, and framework-free, so it is testable with no `NSColor`/theme in sight; the app
/// tier turns a theme's actual colour into the `themeIsDark` this takes.
package enum AppearancePrecedence {
    /// A background whose relative luminance (0 black, 1 white) falls below this reads as a dark theme.
    package static let darkLuminanceThreshold: Double = 0.5

    /// Resolves what ``AppearanceScheme`` the window should actually present.
    ///
    /// - An explicit ``AppearanceScheme/light`` or ``AppearanceScheme/dark`` pin always wins outright: it says
    ///   how the chrome should look, and nothing about the theme overrides a direct instruction.
    /// - ``AppearanceScheme/system`` with `matchesTheme` off (the conservative, opt-in default) or with no theme
    ///   selected (`themeIsDark` nil, the system palette) stays `.system`, following the platform exactly as it
    ///   always has.
    /// - ``AppearanceScheme/system`` with `matchesTheme` on and a theme selected takes the theme's own
    ///   luminance: a dark background pins dark chrome, a light one pins light chrome.
    package static func resolve(
        explicit: AppearanceScheme, matchesTheme: Bool, themeIsDark: Bool?
    ) -> AppearanceScheme {
        guard explicit == .system else { return explicit }
        guard matchesTheme, let themeIsDark else { return .system }
        return themeIsDark ? .dark : .light
    }
}
