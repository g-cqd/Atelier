public import AtelierSyntaxModel

/// A `HoverProvider` backed by a `DocCommentIndex`: resolves the identifier at the query position and formats its
/// doc comment(s) as markdown, with no build context required. The hovered document is parsed once for as long as
/// the hovers stay in it.
public struct DocIndexHoverProvider: HoverProvider {
    private let index: DocCommentIndex
    private let side: DocIndexSides
    private let sources: ParsedSourceCache

    /// - Parameters:
    ///   - index: The index names are looked up in.
    ///   - side: The side of a comparison the hovered documents are on; only files that answer for it are listed.
    public init(index: DocCommentIndex, side: DocIndexSides = .both) {
        self.init(index: index, side: side, sources: ParsedSourceCache())
    }

    init(index: DocCommentIndex, side: DocIndexSides, sources: ParsedSourceCache) {
        self.index = index
        self.side = side
        self.sources = sources
    }

    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        let source = sources.source(for: query.content)
        guard let name = IdentifierLocator.identifier(in: source, line: query.line, utf16Column: query.utf16Column)
        else { return nil }
        let entries = await index.documentation(forIdentifier: name, preferringURI: query.documentURI, side: side)
        guard !entries.isEmpty else { return nil }
        let sameURI = entries.filter { $0.uri == query.documentURI }
        let shown = sameURI.isEmpty ? Array(entries.prefix(3)) : sameURI
        // Distinct entries can still render the same block, such as one file reached through two paths.
        var seenBlocks: Set<String> = []
        var blocks: [String] = []
        for entry in shown {
            let block = "```swift\n\(entry.signature)\n```\n\n\(entry.markdown)"
            if seenBlocks.insert(block).inserted {
                blocks.append(block)
            }
        }
        let markdown = blocks.joined(separator: "\n\n---\n\n")
        return HoverContent(markdown: markdown, source: .docIndex)
    }
}
