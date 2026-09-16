public import KittyStyle

/// Resolves `(HighlightRole, HighlightModifierSet)` to a visual `Style`
/// using the existing `Theme` with role-hierarchy fallback and modifier overrides.
public struct RoleBasedThemeResolver: Sendable {
    private let theme: Theme

    public init(theme: Theme) {
        self.theme = theme
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
