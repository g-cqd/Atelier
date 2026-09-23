public import AtelierSyntaxModel

/// A ``HoverProvider`` backed by a ``SourceKitLSPService`` session.
public struct LSPHoverProvider: HoverProvider {
    private let service: SourceKitLSPService

    public init(service: SourceKitLSPService) {
        self.service = service
    }

    /// The session's answer; nil when it has nothing to show or gave no answer, which a later hover asks again.
    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        await service.hover(
            uri: query.documentURI, languageID: "swift", content: query.content, line: query.line,
            utf16Column: query.utf16Column
        )
        .content
    }
}
