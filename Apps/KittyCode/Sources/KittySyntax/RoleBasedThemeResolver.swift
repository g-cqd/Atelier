public import AtelierSyntaxModel
public import KittyStyle

/// Resolves `(HighlightRole, HighlightModifierSet)` to a visual `Style`
/// using the existing `Theme` with role-hierarchy fallback and modifier overrides.
public struct RoleBasedThemeResolver: Sendable {
    private let theme: Theme
    /// Every role's base style, at the index of its raw value, when ``init(precomputingStylesOf:)`` looked them up.
    private let baseStyles: [Style]?

    public init(theme: Theme) {
        self.theme = theme
        self.baseStyles = nil
    }

    /// A resolver that looks up every role's style once, here, for one that resolves many tokens: resolving a role
    /// then reads an array rather than searching the theme by capture name, a string hash per token.
    /// - Complexity: O(roles) theme lookups.
    public init(precomputingStylesOf theme: Theme) {
        self.theme = theme
        let unresolved = RoleBasedThemeResolver(theme: theme)
        let size = (HighlightRole.allCases.map { Int($0.rawValue) }.max() ?? -1) + 1
        var styles = Array(repeating: theme.defaultStyle, count: size)
        for role in HighlightRole.allCases {
            styles[Int(role.rawValue)] = unresolved.baseStyle(for: role)
        }
        self.baseStyles = styles
    }

    /// Resolve a role and modifiers to a concrete style.
    public func resolve(role: HighlightRole, modifiers: HighlightModifierSet = []) -> Style {
        var style = baseStyle(for: role)

        // Apply modifier overrides
        if modifiers.contains(.deprecated) {
            style.strikethrough = true
        }
        if modifiers.contains(.documentation) {
            style.italic = true
        }
        if modifiers.contains(.definition) {
            style.bold = true
        }

        return style
    }

    // MARK: - Private

    private func baseStyle(for role: HighlightRole) -> Style {
        if let baseStyles { return baseStyles[Int(role.rawValue)] }
        // Map role to capture name and use theme's hierarchical fallback
        let captureName = Self.roleToCaptureNameLookup[role] ?? "variable"
        return theme.style(for: captureName)
    }

    private static let roleToCaptureNameLookup: [HighlightRole: String] = [
        .keyword: "keyword",
        .keywordFunction: "keyword.function",
        .keywordReturn: "keyword.return",
        .keywordOperator: "keyword.operator",
        .type: "type",
        .typeBuiltin: "type.builtin",
        .typeParameter: "type.parameter",
        .function: "function",
        .functionMethod: "function.method",
        .functionBuiltin: "function.builtin",
        .functionCall: "function.call",
        .functionMacro: "function.macro",
        .functionSpecial: "function.special",
        .variable: "variable",
        .variableBuiltin: "variable.builtin",
        .variableParameter: "variable.parameter",
        .string: "string",
        .stringSpecial: "string.special",
        .stringEscape: "string.escape",
        .number: "number",
        .numberFloat: "number.float",
        .comment: "comment",
        .commentDocumentation: "comment.documentation",
        .operator: "operator",
        .punctuationBracket: "punctuation.bracket",
        .punctuationDelimiter: "punctuation.delimiter",
        .punctuationSpecial: "punctuation.special",
        .attribute: "attribute",
        .boolean: "boolean",
        .constantBuiltin: "constant.builtin",
        .constant: "constant",
        .property: "property",
        .namespace: "namespace",
        .label: "label",
        .tag: "tag",
        .constructor: "constructor",
        .embedded: "embedded",
        .escape: "escape"
    ]
}
