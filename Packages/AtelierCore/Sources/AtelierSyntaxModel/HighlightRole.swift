/// Semantic role of a highlighted token, independent of visual style.
/// Maps to tree-sitter capture names and LSP semantic token types.
public enum HighlightRole: UInt16, Sendable, Hashable, CaseIterable {
    case keyword = 0
    case keywordFunction
    case keywordReturn
    case keywordOperator
    case type
    case typeBuiltin
    case typeParameter
    case function
    case functionMethod
    case functionBuiltin
    case functionCall
    case functionMacro
    case functionSpecial
    case variable
    case variableBuiltin
    case variableParameter
    case string
    case stringSpecial
    case stringEscape
    case number
    case numberFloat
    case comment
    case commentDocumentation
    case `operator`
    case punctuationBracket
    case punctuationDelimiter
    case punctuationSpecial
    case attribute
    case boolean
    case constantBuiltin
    case constant
    case property
    case namespace
    case label
    case tag
    case constructor
    case embedded
    case escape
}
