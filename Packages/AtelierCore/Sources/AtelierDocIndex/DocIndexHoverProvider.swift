public import AtelierSyntaxModel

/// A `HoverProvider` backed by a `DocCommentIndex`: resolves the identifier at the query position and formats its
/// doc comment(s) as markdown, with no build context required.
public struct DocIndexHoverProvider: HoverProvider {
    private let index: DocCommentIndex
    private let side: DocIndexSides

    /// - Parameters:
    ///   - index: The index names are looked up in.
    ///   - side: The side of a comparison the hovered documents are on; only files that answer for it are listed.
    public init(index: DocCommentIndex, side: DocIndexSides = .both) {
        self.index = index
        self.side = side
    }

    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        guard
            let name = IdentifierLocator.identifier(in: query.content, line: query.line, utf16Column: query.utf16Column)
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
