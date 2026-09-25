public import AtelierHighlighting
public import AtelierSyntaxModel

/// A language server's semantic tokens as a highlighting tier (PERF-11 step 7): sparse, at the
/// ``HighlightLayer/semantic`` layer, over the tiers below.
///
/// The tier colours names only: the server's keyword, comment, literal and operator tokens are left out, so those
/// keep the syntactic tier's colours. Every token's kind, names and the rest, goes to the facts store for hover, which
/// asks the server over a symbol alone. A text the resolver finds no on-disk document for, such as a side read from
/// git history, asks nothing.
public struct SemanticTokenTier: AtelierHighlighting.HighlightTier {
    /// The on-disk document a text is, and the session that answers for it.
    public struct Document: Sendable {
        public let session: LanguageServerSession
        /// A `file://` URI.
        public let uri: String
        public let languageID: String

        public init(session: LanguageServerSession, uri: String, languageID: String) {
            self.session = session
            self.uri = uri
            self.languageID = languageID
        }
    }

    /// The document `revision`'s text is, where one is on disk, the server is on and the user trusts its repository;
    /// nil otherwise, and then the tier asks nothing.
    public typealias Resolve = @Sendable (SourceRevision) async -> Document?

    private let languages: Set<Language>
    private let store: SyntaxFactsStore?
    private let resolve: Resolve

    /// - Parameters:
    ///   - languages: The languages the tier asks about.
    ///   - store: Where each text's symbol kinds are kept for hover; nil keeps none.
    ///   - resolve: Finds a text's on-disk document and its session.
    public init(
        languages: Set<Language> = [.swift], store: SyntaxFactsStore? = nil, resolve: @escaping Resolve
    ) {
        self.languages = languages
        self.store = store
        self.resolve = resolve
    }

    public var layer: HighlightLayer { .semantic }
    public var coverage: TierCoverage { .sparse }

    public func supports(_ language: Language) -> Bool {
        languages.contains(language)
    }

    /// - Throws: A ``TierFailure``: `.deadline` when the server does not answer within its session's request timeout,
    ///   `.failed` when there is no on-disk document, the server gives no tokens or no answer, or the text changed
    ///   meanwhile.
    public func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        guard let document = await resolve(request.revision) else {
            throw TierFailure.failed("no on-disk document for the text")
        }
        try Task.checkCancellation()
        let outcome = await document.session.semanticTokens(
            uri: document.uri, languageID: document.languageID, content: request.text)
        try Task.checkCancellation()
        let decoded: [HighlightToken]
        switch outcome {
            case .tokens(let data, let legend):
                decoded = LSPSemanticTokenDecoder.decode(data: data, legend: legend, source: request.text)
            case .timedOut: throw TierFailure.deadline(document.session.requestTimeout)
            case .unsupported: throw TierFailure.failed("the server gives no semantic tokens")
            case .superseded: throw TierFailure.failed("the text changed while its tokens were asked for")
            case .unavailable: throw TierFailure.failed("the server gave no answer")
        }
        store?.insert(SymbolKinds(tokens: decoded), for: request.revision)
        let names = decoded.filter { Self.colours($0.role) }
        for chunk in request.chunks {
            try Task.checkCancellation()
            await emit(
                TierUpdate(
                    layer: layer, coverage: coverage, revision: request.revision, lines: chunk,
                    tokens: request.lineTokens(names, lines: chunk)))
        }
    }

    /// Whether the tier colours a token of `role`: a name, not a keyword, a comment, a literal or an operator, which
    /// the syntactic tier colours already.
    static func colours(_ role: HighlightRole) -> Bool {
        SymbolKinds.kind(of: role) == .symbol
    }
}
