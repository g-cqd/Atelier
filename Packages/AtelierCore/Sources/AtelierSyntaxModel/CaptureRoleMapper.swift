/// Maps tree-sitter capture names (e.g. `"keyword.function"`) to
/// `(HighlightRole, HighlightModifierSet)` pairs.
public enum CaptureRoleMapper: Sendable {
    /// Whether a capture colors text. A name with a leading underscore only feeds a predicate, and `spell`, `nospell`
    /// and `conceal` steer an editor's spell checking and concealment, so a highlighter skips them: otherwise the
    /// `@spell` of `(comment) @comment @spell` would restyle the comment.
    public static func colorsText(_ captureName: String) -> Bool {
        let name = captureName.hasPrefix("@") ? captureName.dropFirst() : captureName[...]
        return !name.hasPrefix("_") && !nonColoringNames.contains(name)
    }

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
    /// - Parameters:
    ///   - tokenType: The LSP semantic token type name, such as `"type"` or `"property"`.
    ///   - isDefaultLibrary: LSP's `defaultLibrary` modifier, sourcekit-lsp's signal that the symbol is declared
    ///     outside the edited target: the role for a type, a function, a method, a variable, a property or a
    ///     constant becomes its "other module" variant, the only tier able to draw that distinction from Xcode's own
    ///     `identifier.*.system` colours.
    ///   - isDeclaration: LSP's `declaration` or `definition` modifier, on the token that names what it declares: a
    ///     type or a function's own name takes Xcode's `declaration.type`/`declaration.other`, distinct from every
    ///     later reference to the same name.
    /// - Returns: The role `tokenType` maps to, refined by `isDefaultLibrary` and `isDeclaration`.
    public static func mapLSPTokenType(
        _ tokenType: String, isDefaultLibrary: Bool = false, isDeclaration: Bool = false
    ) -> HighlightRole {
        let role = lspTokenTypeLookup[tokenType] ?? .variable
        if isDeclaration, let declared = declarationVariant[role] { return declared }
        guard isDefaultLibrary else { return role }
        return otherModuleVariant[role] ?? role
    }

    /// The role a project-module role becomes once `defaultLibrary` marks it as declared elsewhere.
    private static let otherModuleVariant: [HighlightRole: HighlightRole] = [
        .type: .typeBuiltin, .function: .functionBuiltin, .functionMethod: .functionBuiltin,
        .functionCall: .functionBuiltin, .variable: .variableBuiltin, .property: .propertyBuiltin,
        .constant: .constantBuiltin
    ]

    /// The role a type's or a function's own name takes at its declaration, distinct from a use of the same name; a
    /// variable, a property or a constant has no such distinction in Xcode's own categories.
    private static let declarationVariant: [HighlightRole: HighlightRole] = [
        .type: .typeDeclaration, .function: .declarationOther, .functionMethod: .declarationOther
    ]

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
        "type.declaration": (.typeDeclaration, []),

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
        "string.regex": (.regex, []),

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
        "delimiter": (.punctuationDelimiter, []),

        // Names from older nvim-treesitter queries, which some grammars' own queries still use
        "conditional": (.keyword, []),
        "repeat": (.keyword, []),
        "include": (.keyword, []),
        "exception": (.keyword, []),
        "preproc": (.keyword, []),
        "float": (.numberFloat, []),
        "parameter": (.variableParameter, []),
        "field": (.property, []),
        "method": (.functionMethod, []),
        "character": (.string, []),
        "character.special": (.punctuationSpecial, [])
    ]

    private static let nonColoringNames: Set<Substring> = ["spell", "nospell", "conceal"]

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
        "regexp": .regex,
        "operator": .operator,
        "decorator": .attribute
    ]
}
