public import AtelierSyntaxModel

/// Reads a text's documented declarations, for a doc-comment index. One extractor serves each language: the lexical
/// one today, a grammar's once the grammar qualifies (HOVER-16), with no change to the index or its readers.
public protocol DeclarationExtracting: Sendable {
    /// The declarations of `text` that carry a doc comment, in source order, each with its comment rendered as
    /// markdown in ``SyntaxDeclaration/documentation`` and its head in ``SyntaxDeclaration/signature``.
    func declarations(in text: String, language: Language) -> [SyntaxDeclaration]
}

/// Finds the identifier under a position of a document, for a hover that looks a name up.
public protocol IdentifierLocating: Sendable {
    /// The identifier covering `(line, utf16Column)`, zero-based, or touching it from the left; nil over a keyword,
    /// a literal, a comment, punctuation or whitespace, and for a language the locator does not read.
    func identifier(in text: String, language: Language, line: Int, utf16Column: Int) async -> String?
}
