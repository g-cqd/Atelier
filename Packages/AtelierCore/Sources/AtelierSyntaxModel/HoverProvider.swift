/// A position in a document whose documentation is wanted, with enough context that a provider needs nothing else:
/// the full content travels with the query, so providers work for on-disk files and git blobs alike.
public struct HoverQuery: Sendable, Hashable {
    /// A `file://` URI for on-disk documents, or a synthetic `atelier-blob://<oid>/<path>` URI for git blobs.
    public let documentURI: String
    /// The complete document text the position refers to.
    public let content: String
    /// Zero-based line in `content`.
    public let line: Int
    /// Zero-based UTF-16 column within the line.
    public let utf16Column: Int

    public init(documentURI: String, content: String, line: Int, utf16Column: Int) {
        self.documentURI = documentURI
        self.content = content
        self.line = line
        self.utf16Column = utf16Column
    }
}

/// Documentation for a hovered symbol, and which tier produced it.
public struct HoverContent: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        /// A language server answered, with build-context fidelity.
        case languageServer
        /// The source-only doc-comment index answered.
        case docIndex
    }

    /// Markdown, possibly with fenced code blocks.
    public let markdown: String
    public let source: Source

    public init(markdown: String, source: Source) {
        self.markdown = markdown
        self.source = source
    }
}

/// Answers hover queries; e.g. a language-server client, or a doc-comment index over the sources themselves.
/// Implementations must honor task cancellation promptly and return nil rather than throw when they simply have
/// nothing to show.
public protocol HoverProvider: Sendable {
    func hover(_ query: HoverQuery) async throws -> HoverContent?
}
