public import AtelierSyntaxModel
public import Foundation

/// A ``HoverProvider`` backed by language server sessions: one given session, or, per document, the session of the
/// server that serves the document's language, at the document's root.
///
/// The document's language and its language ID come from its path. A registry-backed provider answers nothing, and
/// starts no server, for a language none of its servers serves, and for a document not on disk, such as a git blob's.
public struct LanguageServerHoverProvider: HoverProvider {
    private enum Sessions: Sendable {
        case fixed(LanguageServerSession, resolvesDocumentationPages: Bool)
        case registry(LanguageServerRegistry, servers: [LanguageServerDescriptor], workspaceRoot: URL)
    }

    private let sessions: Sessions

    /// A provider whose hovers all go to `session`, whatever the document's language.
    /// - Parameters:
    ///   - session: The session the hovers go to.
    ///   - resolvesDocumentationPages: Whether an answer about a system symbol carries its page in Apple's developer
    ///     documentation, which takes the server one or two more requests after the hover.
    public init(session: LanguageServerSession, resolvesDocumentationPages: Bool = false) {
        sessions = .fixed(session, resolvesDocumentationPages: resolvesDocumentationPages)
    }

    /// A provider that sends each on-disk document to the session `registry` holds for its server among `servers`, at
    /// the document's root under `workspaceRoot` (``LanguageServerRegistry/session(forDocumentAt:within:server:)``).
    /// An answer carries its documentation page when the server resolves them
    /// (``LanguageServerDescriptor/resolvesDocumentationPages``).
    public init(
        registry: LanguageServerRegistry, servers: [LanguageServerDescriptor] = LanguageServerDescriptor.all,
        workspaceRoot: URL
    ) {
        sessions = .registry(registry, servers: servers, workspaceRoot: workspaceRoot)
    }

    /// The session's answer; nil when no session serves the document, when it has nothing to show or when it gave no
    /// answer, which a later hover asks again.
    public func hover(_ query: HoverQuery) async throws -> HoverContent? {
        let document = URL(string: query.documentURI)
        let session: LanguageServerSession
        let resolvesDocumentationPages: Bool
        switch sessions {
            case .fixed(let fixed, let resolves):
                session = fixed
                resolvesDocumentationPages = resolves
            case .registry(let registry, let servers, let workspaceRoot):
                guard let document, document.isFileURL,
                    let server = LanguageServerDescriptor.serving(
                        Language(fileExtension: document.pathExtension), among: servers),
                    let found = await registry.session(forDocumentAt: document, within: workspaceRoot, server: server)
                else { return nil }
                session = found
                resolvesDocumentationPages = server.resolvesDocumentationPages
        }
        let languageID =
            document.map(LanguageServerDescriptor.languageID(forDocumentAt:)) ?? Language.plain.lspLanguageID
        guard
            let content =
                await session.hover(
                    uri: query.documentURI, languageID: languageID, content: query.content, line: query.line,
                    utf16Column: query.utf16Column
                )
                .content
        else { return nil }
        guard resolvesDocumentationPages else { return content }
        let page = await session.documentationPage(
            uri: query.documentURI, languageID: languageID, content: query.content, line: query.line,
            utf16Column: query.utf16Column)
        return HoverContent(markdown: content.markdown, source: content.source, documentationPage: page)
    }
}
