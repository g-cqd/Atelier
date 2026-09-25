public import AtelierDocComment
import AtelierSwiftSyntax
public import AtelierSyntaxModel

/// A `HoverProvider` backed by a `DocCommentIndex`: resolves the identifier at the query position through its locator
/// and formats the identifier's doc comment(s) as markdown, with no build context required. Only a document of a
/// language the index reads has a hover, and it lists only declarations of its own language family, TypeScript and
/// JavaScript counting as one.
public struct DocIndexHoverProvider: HoverProvider {
    private let index: DocCommentIndex
    private let side: DocIndexSides
    private let locator: any IdentifierLocating

    /// - Parameters:
    ///   - index: The index names are looked up in.
    ///   - side: The side of a comparison the hovered documents are on; only files that answer for it are listed.
    ///   - locator: Finds the identifier under the pointer; ``DocumentIdentifierLocator`` reads Swift with
    ///     swift-syntax and other languages with the lexical scanner.
    public init(
        index: DocCommentIndex, side: DocIndexSides = .both,
        locator: any IdentifierLocating = DocumentIdentifierLocator()
    ) {
        self.index = index
        self.side = side
        self.locator = locator
    }

    init(index: DocCommentIndex, side: DocIndexSides, sources: ParsedSourceCache) {
        self.init(index: index, side: side, locator: DocumentIdentifierLocator(sources: sources))
    }

    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        // swift-syntax reads any text as Swift, and another language's comments and single-quoted strings are neither
        // to it: a language the index does not read ends here, before any parse.
        let language = DocCommentIndex.language(ofURI: query.documentURI)
        guard index.indexes(language) else { return nil }
        let located = await locator.identifier(
            in: query.content, language: language, line: query.line, utf16Column: query.utf16Column)
        guard let name = located else { return nil }
        let family = Self.family(of: language)
        let entries = await index.documentation(forIdentifier: name, preferringURI: query.documentURI, side: side)
            .filter { Self.family(of: DocCommentIndex.language(ofURI: $0.uri)) == family }
        guard !entries.isEmpty else { return nil }
        let sameURI = entries.filter { $0.uri == query.documentURI }
        let shown = sameURI.isEmpty ? Array(entries.prefix(3)) : sameURI
        // Distinct entries can still render the same block, such as one file reached through two paths.
        var seenBlocks: Set<String> = []
        var blocks: [String] = []
        for entry in shown {
            let fence = DocCommentIndex.language(ofURI: entry.uri).name
            let block = "```\(fence)\n\(entry.signature)\n```\n\n\(entry.markdown)"
            if seenBlocks.insert(block).inserted {
                blocks.append(block)
            }
        }
        let markdown = blocks.joined(separator: "\n\n---\n\n")
        return HoverContent(markdown: markdown, source: .docIndex)
    }

    /// The languages whose declarations answer for each other: JavaScript's for TypeScript's, and the reverse.
    private static func family(of language: Language) -> Language {
        language == .javascript ? .typescript : language
    }
}

/// The identifier under a position of a document: swift-syntax's identifier token in a Swift document, parsed once for
/// as long as the hovers stay in it, and the lexical scanner's elsewhere.
public struct DocumentIdentifierLocator: IdentifierLocating {
    private let sources: ParsedSourceCache
    private let lexical = LexicalIdentifierLocator()

    public init() {
        self.init(sources: ParsedSourceCache())
    }

    init(sources: ParsedSourceCache) {
        self.sources = sources
    }

    public func identifier(in text: String, language: Language, line: Int, utf16Column: Int) async -> String? {
        guard language == .swift else {
            return await lexical.identifier(in: text, language: language, line: line, utf16Column: utf16Column)
        }
        let sources = sources
        return await SwiftSyntaxStack.run {
            IdentifierLocator.identifier(in: sources.source(for: text), line: line, utf16Column: utf16Column)
        }
    }
}
