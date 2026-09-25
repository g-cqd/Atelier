// Hand-rolled Codable types for exactly the LSP requests the apps make: initialize, document
// sync for open/close, and hover. Not a general-purpose LSP model.

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

/// The client capabilities advertised in `initialize`, trimmed to what hover needs.
public struct ClientCapabilities: Sendable, Encodable {
    public let textDocument: TextDocumentClientCapabilities

    public init(textDocument: TextDocumentClientCapabilities = TextDocumentClientCapabilities()) {
        self.textDocument = textDocument
    }
}

/// Per-feature text document capabilities, trimmed to hover.
public struct TextDocumentClientCapabilities: Sendable, Encodable {
    public let hover: HoverClientCapabilities

    public init(hover: HoverClientCapabilities = HoverClientCapabilities()) {
        self.hover = hover
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
