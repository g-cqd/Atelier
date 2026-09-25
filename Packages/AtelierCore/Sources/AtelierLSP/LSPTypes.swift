// Hand-rolled Codable types for exactly the LSP requests the apps make: initialize, document
// sync, hover and semantic tokens. Not a general-purpose LSP model.

import AtelierSyntaxModel

/// Parameters for the `initialize` request. A nil field is left out of the request.
public struct InitializeParams: Sendable, Encodable {
    public let processId: Int?
    public let rootUri: String?
    public let capabilities: ClientCapabilities
    /// The server's own options, whose shape each server defines.
    public let initializationOptions: JSONValue?
    /// The folders the session covers, which the specification prefers to the deprecated `rootUri`.
    public let workspaceFolders: [WorkspaceFolder]?

    public init(
        processId: Int?, rootUri: String?, capabilities: ClientCapabilities = ClientCapabilities(),
        initializationOptions: JSONValue? = nil, workspaceFolders: [WorkspaceFolder]? = nil
    ) {
        self.processId = processId
        self.rootUri = rootUri
        self.capabilities = capabilities
        self.initializationOptions = initializationOptions
        self.workspaceFolders = workspaceFolders
    }
}

/// A workspace folder, as `initialize` lists them.
public struct WorkspaceFolder: Sendable, Codable, Equatable {
    public let uri: String
    /// The folder's name in the client's user interface.
    public let name: String

    public init(uri: String, name: String) {
        self.uri = uri
        self.name = name
    }
}

/// The client capabilities advertised in `initialize`, trimmed to what hover and semantic colour need.
public struct ClientCapabilities: Sendable, Encodable {
    public let textDocument: TextDocumentClientCapabilities
    public let workspace: WorkspaceClientCapabilities

    public init(
        textDocument: TextDocumentClientCapabilities = TextDocumentClientCapabilities(),
        workspace: WorkspaceClientCapabilities = WorkspaceClientCapabilities()
    ) {
        self.textDocument = textDocument
        self.workspace = workspace
    }
}

/// Per-feature text document capabilities, trimmed to hover and semantic tokens.
public struct TextDocumentClientCapabilities: Sendable, Encodable {
    public let hover: HoverClientCapabilities
    public let semanticTokens: SemanticTokensClientCapabilities

    public init(
        hover: HoverClientCapabilities = HoverClientCapabilities(),
        semanticTokens: SemanticTokensClientCapabilities = SemanticTokensClientCapabilities()
    ) {
        self.hover = hover
        self.semanticTokens = semanticTokens
    }
}

/// Workspace capabilities: the server may ask the client to refresh its semantic tokens.
public struct WorkspaceClientCapabilities: Sendable, Encodable {
    public struct SemanticTokens: Sendable, Encodable {
        public let refreshSupport: Bool
    }

    public let semanticTokens: SemanticTokens

    public init(semanticTokensRefresh: Bool = true) {
        semanticTokens = SemanticTokens(refreshSupport: semanticTokensRefresh)
    }
}

/// What the client reads of semantic tokens: whole documents, as deltas against the last result, in the
/// specification's standard types and modifiers and its relative format.
public struct SemanticTokensClientCapabilities: Sendable, Encodable {
    public struct Requests: Sendable, Encodable {
        public struct Full: Sendable, Encodable {
            public let delta: Bool
        }

        public let range: Bool
        public let full: Full
    }

    /// The token types the specification defines, which ``LSPSemanticTokenDecoder`` maps to roles.
    public static let standardTokenTypes = [
        "namespace", "type", "class", "enum", "interface", "struct", "typeParameter", "parameter", "variable",
        "property", "enumMember", "event", "function", "method", "macro", "keyword", "modifier", "comment", "string",
        "number", "regexp", "operator", "decorator"
    ]
    /// The token modifiers the specification defines.
    public static let standardTokenModifiers = [
        "declaration", "definition", "readonly", "static", "deprecated", "abstract", "async", "modification",
        "documentation", "defaultLibrary"
    ]

    public let requests: Requests
    public let tokenTypes: [String]
    public let tokenModifiers: [String]
    public let formats: [String]
    public let overlappingTokenSupport: Bool
    public let multilineTokenSupport: Bool

    public init(delta: Bool = true) {
        requests = Requests(range: false, full: Requests.Full(delta: delta))
        tokenTypes = Self.standardTokenTypes
        tokenModifiers = Self.standardTokenModifiers
        formats = ["relative"]
        overlappingTokenSupport = false
        multilineTokenSupport = false
    }
}

/// The content formats the client accepts for hover text, most preferred first.
public struct HoverClientCapabilities: Sendable, Encodable {
    public let contentFormat: [String]

    public init(contentFormat: [String] = ["markdown", "plaintext"]) {
        self.contentFormat = contentFormat
    }
}

/// The (empty) payload of the `initialized` notification, sent once `initialize` completes.
public struct InitializedParams: Sendable, Encodable {
    public init() {}
}

/// A text document as the server first sees it, for `textDocument/didOpen`.
public struct TextDocumentItem: Sendable, Codable, Equatable {
    public let uri: String
    public let languageId: String
    public let version: Int
    public let text: String

    public init(uri: String, languageId: String, version: Int, text: String) {
        self.uri = uri
        self.languageId = languageId
        self.version = version
        self.text = text
    }
}

/// Parameters for `textDocument/didOpen`.
public struct DidOpenTextDocumentParams: Sendable, Encodable {
    public let textDocument: TextDocumentItem

    public init(textDocument: TextDocumentItem) {
        self.textDocument = textDocument
    }
}

/// Identifies a text document by URI alone, without its content.
public struct TextDocumentIdentifier: Sendable, Codable, Equatable {
    public let uri: String

    public init(uri: String) {
        self.uri = uri
    }
}

/// Parameters for `textDocument/didClose`.
public struct DidCloseTextDocumentParams: Sendable, Encodable {
    public let textDocument: TextDocumentIdentifier

    public init(textDocument: TextDocumentIdentifier) {
        self.textDocument = textDocument
    }
}

/// A zero-based line/character position, in UTF-16 code units, as LSP defines it.
public struct Position: Sendable, Codable, Equatable {
    public let line: Int
    public let character: Int

    public init(line: Int, character: Int) {
        self.line = line
        self.character = character
    }
}

/// Parameters for `textDocument/hover`.
public struct HoverParams: Sendable, Encodable {
    public let textDocument: TextDocumentIdentifier
    public let position: Position

    public init(textDocument: TextDocumentIdentifier, position: Position) {
        self.textDocument = textDocument
        self.position = position
    }
}

/// The span a hover result applies to.
public struct HoverRange: Sendable, Codable, Equatable {
    public let start: Position
    public let end: Position

    public init(start: Position, end: Position) {
        self.start = start
        self.end = end
    }
}

/// A hover result, with `contents` normalized to a single markdown string.
///
/// The LSP spec allows `contents` to be a `MarkupContent`, a bare string, a `{language, value}`
/// object, or an array of any mix of the latter two (the deprecated `MarkedString` forms). This
/// type decodes all of them into one `markdown` string, joining array items with a blank line.
public struct Hover: Sendable, Equatable {
    public let markdown: String
    public let range: HoverRange?

    public init(markdown: String, range: HoverRange? = nil) {
        self.markdown = markdown
        self.range = range
    }
}

extension Hover: Decodable {
    private enum CodingKeys: String, CodingKey {
        case contents
        case range
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.markdown = try Self.decodeMarkdown(from: container)
        self.range = try container.decodeIfPresent(HoverRange.self, forKey: .range)
    }

    private static func decodeMarkdown(from container: KeyedDecodingContainer<CodingKeys>) throws -> String {
        if let markup = try? container.decode(MarkupContent.self, forKey: .contents) {
            return markup.value
        }
        if let text = try? container.decode(String.self, forKey: .contents) {
            return text
        }
        if let marked = try? container.decode(MarkedStringObject.self, forKey: .contents) {
            return marked.markdown
        }
        if let items = try? container.decode([MarkedStringItem].self, forKey: .contents) {
            return items.map(\.markdown).joined(separator: "\n\n")
        }
        throw DecodingError.dataCorruptedError(
            forKey: .contents, in: container, debugDescription: "Unrecognized hover contents shape")
    }
}

/// `MarkupContent`: `{kind, value}`, where `kind` is `"markdown"` or `"plaintext"`.
private struct MarkupContent: Decodable {
    let kind: String
    let value: String
}

/// The deprecated `MarkedString` object shape: `{language, value}`.
private struct MarkedStringObject: Decodable {
    let language: String
    let value: String

    var markdown: String { "```\(language)\n\(value)\n```" }
}

/// One element of a `MarkedString[]`: either a bare string or a `{language, value}` object.
private enum MarkedStringItem: Decodable {
    case plain(String)
    case object(MarkedStringObject)

    init(from decoder: any Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let text = try? container.decode(String.self) {
            self = .plain(text)
            return
        }
        self = .object(try MarkedStringObject(from: decoder))
    }

    var markdown: String {
        switch self {
            case .plain(let text): text
            case .object(let object): object.markdown
        }
    }
}

/// Parameters for `$/cancelRequest`.
public struct CancelParams: Sendable, Encodable {
    public let id: JSONRPCID

    public init(id: JSONRPCID) {
        self.id = id
    }
}

/// One symbol of sourcekit-lsp's `textDocument/symbolInfo` answer, which the LSP extension clangd started: the
/// fields a documentation page needs.
public struct SymbolDetails: Sendable, Decodable, Equatable {
    /// Where a system symbol is declared; sourcekit-lsp names a submodule after its module, as
    /// `Foundation.NSFileManager`.
    public struct SystemModule: Sendable, Decodable, Equatable {
        public let moduleName: String

        public init(moduleName: String) {
            self.moduleName = moduleName
        }
    }

    /// The symbol's name, a function's with its argument labels, as `contents(atPath:)`.
    public let name: String?
    /// Set only for a symbol a module without sources declares, such as the SDK's.
    public let systemModule: SystemModule?

    public init(name: String?, systemModule: SystemModule?) {
        self.name = name
        self.systemModule = systemModule
    }
}

// MARK: - Semantic tokens

/// Identifies a text document at one version, for `textDocument/didChange`.
public struct VersionedTextDocumentIdentifier: Sendable, Codable, Equatable {
    public let uri: String
    public let version: Int

    public init(uri: String, version: Int) {
        self.uri = uri
        self.version = version
    }
}

/// One change of a document: its whole new text, since the client sends the full content.
public struct TextDocumentContentChangeEvent: Sendable, Codable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

/// Parameters for `textDocument/didChange`.
public struct DidChangeTextDocumentParams: Sendable, Encodable {
    public let textDocument: VersionedTextDocumentIdentifier
    public let contentChanges: [TextDocumentContentChangeEvent]

    public init(textDocument: VersionedTextDocumentIdentifier, contentChanges: [TextDocumentContentChangeEvent]) {
        self.textDocument = textDocument
        self.contentChanges = contentChanges
    }
}

/// Parameters for `textDocument/semanticTokens/full`.
public struct SemanticTokensParams: Sendable, Encodable {
    public let textDocument: TextDocumentIdentifier

    public init(textDocument: TextDocumentIdentifier) {
        self.textDocument = textDocument
    }
}

/// Parameters for `textDocument/semanticTokens/full/delta`: the result the delta is against.
public struct SemanticTokensDeltaParams: Sendable, Encodable {
    public let textDocument: TextDocumentIdentifier
    public let previousResultId: String

    public init(textDocument: TextDocumentIdentifier, previousResultId: String) {
        self.textDocument = textDocument
        self.previousResultId = previousResultId
    }
}

/// A whole document's semantic tokens, and the result ID a later delta names.
struct SemanticTokensResult: Decodable, Sendable {
    let resultId: String?
    let data: [UInt32]
}

/// A delta request's answer: the whole tokens again, or edits to the last result's data.
enum SemanticTokensDeltaResult: Decodable, Sendable {
    case full(SemanticTokensResult)
    case delta(resultId: String?, edits: [LSPSemanticTokenDecoder.SemanticTokenEdit])

    private enum CodingKeys: String, CodingKey {
        case resultId
        case data
        case edits
    }

    private struct Edit: Decodable {
        let start: Int
        let deleteCount: Int
        let data: [UInt32]?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let resultId = try container.decodeIfPresent(String.self, forKey: .resultId)
        if let edits = try container.decodeIfPresent([Edit].self, forKey: .edits) {
            self = .delta(
                resultId: resultId,
                edits: edits.map { .init(start: $0.start, deleteCount: $0.deleteCount, data: $0.data ?? []) })
        } else {
            self = .full(
                SemanticTokensResult(resultId: resultId, data: try container.decode([UInt32].self, forKey: .data)))
        }
    }
}

/// What a server's `initialize` answer says about semantic tokens: its legend, and whether it answers whole documents
/// and deltas. Every other capability is left unread, so an answer the client cannot read beyond these keys still
/// completes the handshake.
struct InitializeResult: Decodable, Sendable {
    struct SemanticTokensSupport: Sendable, Equatable {
        let legend: SemanticTokensLegend
        let full: Bool
        let delta: Bool
    }

    let semanticTokens: SemanticTokensSupport?

    private enum CodingKeys: String, CodingKey {
        case capabilities
    }

    private enum CapabilityKeys: String, CodingKey {
        case semanticTokensProvider
    }

    private struct Provider: Decodable {
        struct Legend: Decodable {
            let tokenTypes: [String]
            let tokenModifiers: [String]
        }

        /// `full` is a Boolean or an object with `delta`.
        struct Full: Decodable {
            let isSupported: Bool
            let delta: Bool

            init(from decoder: any Decoder) throws {
                let single = try decoder.singleValueContainer()
                if let flag = try? single.decode(Bool.self) {
                    isSupported = flag
                    delta = false
                } else {
                    struct Options: Decodable { let delta: Bool? }
                    isSupported = true
                    delta = try single.decode(Options.self).delta ?? false
                }
            }
        }

        let legend: Legend
        let full: Full?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let capabilities = try? container.nestedContainer(keyedBy: CapabilityKeys.self, forKey: .capabilities)
        guard let provider = try? capabilities?.decodeIfPresent(Provider.self, forKey: .semanticTokensProvider) else {
            semanticTokens = nil
            return
        }
        semanticTokens = SemanticTokensSupport(
            legend: SemanticTokensLegend(
                tokenTypes: provider.legend.tokenTypes, tokenModifiers: provider.legend.tokenModifiers),
            full: provider.full?.isSupported ?? false, delta: provider.full?.delta ?? false)
    }
}
