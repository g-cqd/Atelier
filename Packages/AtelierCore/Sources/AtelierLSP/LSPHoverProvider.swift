public import AtelierSyntaxModel

/// A ``HoverProvider`` backed by a ``LanguageServerSession``.
public struct LSPHoverProvider: HoverProvider {
    private let service: LanguageServerSession
    private let resolvesDocumentationPages: Bool

    /// - Parameters:
    ///   - service: The session the hovers go to.
    ///   - resolvesDocumentationPages: Whether an answer about a system symbol carries its page in Apple's developer
    ///     documentation, which takes the server one or two more requests after the hover.
    public init(service: LanguageServerSession, resolvesDocumentationPages: Bool = false) {
        self.service = service
        self.resolvesDocumentationPages = resolvesDocumentationPages
    }

    /// The session's answer; nil when it has nothing to show or gave no answer, which a later hover asks again.
    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        guard
            let content =
                await service.hover(
                    uri: query.documentURI, languageID: "swift", content: query.content, line: query.line,
                    utf16Column: query.utf16Column
                )
                .content
        else { return nil }
        guard resolvesDocumentationPages else { return content }
        let page = await service.documentationPage(
            uri: query.documentURI, languageID: "swift", content: query.content, line: query.line,
            utf16Column: query.utf16Column)
        return HoverContent(markdown: content.markdown, source: content.source, documentationPage: page)
    }
}
