/// Maps tree-sitter capture names (e.g. `"keyword.function"`) to
/// `(HighlightRole, HighlightModifierSet)` pairs.
public enum CaptureRoleMapper: Sendable {
    /// Map a tree-sitter capture name to a role and modifier set.
    public static func map(_ captureName: String) -> (role: HighlightRole, modifiers: HighlightModifierSet) {
        let name = captureName.hasPrefix("@") ? String(captureName.dropFirst()) : captureName

        if let exact = exactLookup[name] {
            return exact
        }

        // Hierarchical fallback: keyword.function.builtin → keyword.function → keyword
        var parts = name.split(separator: ".")
        while parts.count > 1 {
            parts.removeLast()
            let prefix = parts.joined(separator: ".")
            if let result = exactLookup[prefix] {
                return result
            }
        }

        return (.variable, [])
    }

    /// Map an LSP semantic token type name to a role.
    public static func mapLSPTokenType(_ tokenType: String) -> HighlightRole {
        lspTokenTypeLookup[tokenType] ?? .variable
    }

    // MARK: - Lookup tables

    private static let exactLookup: [String: (role: HighlightRole, modifiers: HighlightModifierSet)] = [
        // Keywords
        "keyword": (.keyword, []),
        "keyword.function": (.keywordFunction, []),
        "keyword.return": (.keywordReturn, []),
        "keyword.operator": (.keywordOperator, []),

        // Types
        "type": (.type, []),
        "type.builtin": (.typeBuiltin, []),
        "type.parameter": (.typeParameter, []),

        // Functions
        "function": (.function, []),
        "function.name": (.function, .definition),
        "function.method": (.functionMethod, []),
        "function.builtin": (.functionBuiltin, []),
        "function.call": (.functionCall, []),
        "function.macro": (.functionMacro, []),
        "function.special": (.functionSpecial, []),

        // Variables
        "variable": (.variable, []),
        "variable.builtin": (.variableBuiltin, []),
        "variable.parameter": (.variableParameter, []),

        // Strings
        "string": (.string, []),
        "string.special": (.stringSpecial, []),
        "string.special.key": (.stringSpecial, []),
        "string.escape": (.stringEscape, []),

        // Numbers
        "number": (.number, []),
        "number.float": (.numberFloat, []),

        // Comments
        "comment": (.comment, []),
        "comment.documentation": (.commentDocumentation, .documentation),

        // Operators & punctuation
        "operator": (.operator, []),
        "punctuation": (.punctuationDelimiter, []),
        "punctuation.bracket": (.punctuationBracket, []),
        "punctuation.delimiter": (.punctuationDelimiter, []),
        "punctuation.special": (.punctuationSpecial, []),

        // Constants
        "constant": (.constant, []),
        "constant.builtin": (.constantBuiltin, []),
        "boolean": (.boolean, []),

        // Other
        "attribute": (.attribute, []),
        "property": (.property, []),
        "namespace": (.namespace, []),
        "module": (.namespace, []),
        "label": (.label, []),
        "tag": (.tag, []),
        "constructor": (.constructor, []),
        "embedded": (.embedded, []),
        "escape": (.escape, []),

        // Delimiter (legacy capture name used by some queries)
        "delimiter": (.punctuationDelimiter, [])
    ]

    private static let lspTokenTypeLookup: [String: HighlightRole] = [
        "namespace": .namespace,
        "type": .type,
        "class": .type,
        "enum": .type,
        "interface": .type,
        "struct": .type,
        "typeParameter": .typeParameter,
        "parameter": .variableParameter,
        "variable": .variable,
        "property": .property,
        "enumMember": .constantBuiltin,
        "function": .function,
        "method": .functionMethod,
        "macro": .functionMacro,
        "keyword": .keyword,
        "modifier": .keyword,
        "comment": .comment,
        "string": .string,
        "number": .number,
        "regexp": .stringSpecial,
        "operator": .operator,
        "decorator": .attribute
    ]
}
