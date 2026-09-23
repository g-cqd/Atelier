package import DiffCore

// The names a setting's values read as wherever they are listed rather than picked, such as a project's overrides,
// matching the choices the Settings window's pickers offer.

extension ViewMode {
    package var displayName: String {
        switch self {
            case .inline: "Inline"
            case .split: "Side by side"
            case .stacked: "Stacked"
        }
    }
}

extension FileTreeStyle {
    package var displayName: String {
        switch self {
            case .hierarchy: "Tree"
            case .compact: "Tree with compact folders"
            case .flat: "Flat list of paths"
        }
    }
}

extension IntralineGranularity {
    package var displayName: String {
        switch self {
            case .character: "Characters"
            case .word: "Words"
            case .syntax: "Syntax"
        }
    }
}

extension WhitespaceMode {
    package var displayName: String {
        switch self {
            case .exact: "Exactly"
            case .ignoreTrailing: "Ignoring trailing whitespace"
            case .ignoreLeadingAndTrailing: "Ignoring leading and trailing whitespace"
            case .ignoreAll: "Ignoring all whitespace"
        }
    }
}

extension AnalyzedSides {
    package var displayName: String {
        switch self {
            case .both: "Both sides"
            case .leftOnly: "Left side only"
            case .rightOnly: "Right side only"
            case .none: "No side"
        }
    }
}
