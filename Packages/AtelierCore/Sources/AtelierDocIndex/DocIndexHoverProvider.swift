public import AtelierSyntaxModel

/// A `HoverProvider` backed by a `DocCommentIndex`: resolves the identifier at the query position and formats its
/// doc comment(s) as markdown, with no build context required.
public struct DocIndexHoverProvider: HoverProvider {
    private let index: DocCommentIndex

    public init(index: DocCommentIndex) {
        self.index = index
    }

    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        guard
            let name = IdentifierLocator.identifier(in: query.content, line: query.line, utf16Column: query.utf16Column)
        else { return nil }
        let entries = await index.documentation(forIdentifier: name, preferringURI: query.documentURI)
        guard !entries.isEmpty else { return nil }
        let sameURI = entries.filter { $0.uri == query.documentURI }
        let shown = sameURI.isEmpty ? Array(entries.prefix(3)) : sameURI
        let markdown =
            shown.map { entry in
                "```swift\n\(entry.signature)\n```\n\n\(entry.markdown)"
            }
            .joined(separator: "\n\n---\n\n")
        return HoverContent(markdown: markdown, source: .docIndex)
    }
}
