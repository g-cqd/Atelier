import AtelierSwiftSyntax
public import AtelierSyntaxModel

/// A `HoverProvider` backed by a `DocCommentIndex`: resolves the identifier at the query position and formats its
/// doc comment(s) as markdown, with no build context required. The hovered document is parsed once for as long as
/// the hovers stay in it, and only a Swift document is parsed at all.
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
        // swift-syntax reads any text as Swift, and another language's comments and single-quoted strings are neither to
        // it: their brackets open levels that never close. Its answer would be wrong anyway, so anything but a Swift
        // document ends here.
        guard Self.isSwift(query.documentURI) else { return nil }
        let sources = sources
        let located = await SwiftSyntaxStack.run {
            IdentifierLocator.identifier(
                in: sources.source(for: query.content), line: query.line, utf16Column: query.utf16Column)
        }
        guard let name = located else { return nil }
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

    /// Whether `uri`, a `file://` or `atelier-blob://` URI, names a Swift file. Read from the text, not through `URL`,
    /// which would take a `#` or `?` in a blob path for a fragment or a query.
    static func isSwift(_ uri: String) -> Bool {
        guard let name = uri.split(separator: "/").last, let dot = name.lastIndex(of: ".") else { return false }
        return Language(fileExtension: String(name[name.index(after: dot)...])) == .swift
    }
}
