import AemiJSON
public import Foundation

/// A JSON value with no schema attached, for payloads whose shape is decided by the method name
/// rather than by Swift's type system.
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .null: try container.encodeNil()
            case .bool(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
        }
    }
}

/// A JSON-RPC request identifier, which the protocol allows to be a number or a string.
public enum JSONRPCID: Sendable, Hashable {
    case number(Int)
    case string(String)
}

extension JSONRPCID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a JSON-RPC id (number or string)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .number(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
        }
    }
}

/// A JSON-RPC error object, as carried by an error response.
public struct JSONRPCError: Error, Sendable, Equatable, Codable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// A result the client does not read, such as `initialize`'s capabilities: its decode reads nothing, so a large or
/// deeply nested reply costs no work beyond the parse, and cannot fail on a shape the client has no use for.
struct DiscardedResult: Decodable, Sendable {
    init(from decoder: any Decoder) {}
}

/// Failure to classify a decoded JSON-RPC payload.
public enum JSONRPCDecodingError: Error, Sendable, Equatable {
    /// Neither a `method` nor an `id` was present, so the payload is not a valid JSON-RPC message.
    case missingIdentifyingField
}

private struct RequestEnvelope<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let id: JSONRPCID
    let method: String
    let params: Params
}

private struct NotificationEnvelope<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: Params
}

private struct ResponseEnvelope: Encodable {
    let jsonrpc = "2.0"
    let id: JSONRPCID
    let result: JSONValue
}

private struct ErrorResponseEnvelope: Encodable {
    let jsonrpc = "2.0"
    let id: JSONRPCID
    let error: JSONRPCError
}

/// Builders for the four JSON-RPC envelope shapes a client sends over the LSP base protocol.
public enum JSONRPCMessage {
    /// A request the client sends to the server, expecting a matching response.
    public static func request<P: Encodable>(id: JSONRPCID, method: String, params: P) throws -> Data {
        try AemiJSON.JSONEncoder().encode(RequestEnvelope(id: id, method: method, params: params))
    }

    /// A notification the client sends to the server, with no response expected.
    public static func notification<P: Encodable>(method: String, params: P) throws -> Data {
        try AemiJSON.JSONEncoder().encode(NotificationEnvelope(method: method, params: params))
    }

    /// A successful reply to a request the server sent.
    public static func response(id: JSONRPCID, result: JSONValue) throws -> Data {
        try AemiJSON.JSONEncoder().encode(ResponseEnvelope(id: id, result: result))
    }

    /// A failed reply to a request the server sent.
    public static func errorResponse(id: JSONRPCID, code: Int, message: String) throws -> Data {
        try AemiJSON.JSONEncoder()
            .encode(
                ErrorResponseEnvelope(id: id, error: JSONRPCError(code: code, message: message)))
    }
}

/// A decoded incoming JSON-RPC payload, classified by which fields it carries.
public enum IncomingMessage: Sendable {
    /// A reply to a request the client sent, matched by `id`. `result` is the untouched raw JSON
    /// text of the envelope's `result` field, for a typed decode at the call site.
    case response(id: JSONRPCID, result: Data?, error: JSONRPCError?)
    /// A request the server sent to the client, needing a reply with the same `id`.
    case serverRequest(id: JSONRPCID, method: String)
    /// A notification the server sent, with no reply expected.
    case notification(method: String)

    /// Decodes and classifies one JSON-RPC payload.
    ///
    /// A response's `result` is the payload's own bytes for that field, handed back without a re-encode.
    public static func decode(_ payload: Data) throws -> IncomingMessage {
        var options = JSONParseOptions.strict
        options.recordsContainerSpans = true
        let root = try AemiJSON.parse(payload, options: options).root

        let idNode = root["id"]
        let id: JSONRPCID? = idNode.int.map(JSONRPCID.number) ?? idNode.string.map(JSONRPCID.string)

        if let method = root["method"].string {
            if let id {
                return .serverRequest(id: id, method: method)
            }
            return .notification(method: method)
        }

        guard let id else {
            throw JSONRPCDecodingError.missingIdentifyingField
        }

        let errorNode = root["error"]
        var error: JSONRPCError?
        if let code = errorNode["code"].int, let message = errorNode["message"].string {
            error = JSONRPCError(code: code, message: message)
        }
        let resultData = root["result"].withRawJSONBytes { Data($0) }
        return .response(id: id, result: resultData, error: error)
    }

    /// The id of a response that ``decode(_:)`` refused, such as one carrying invalid UTF-8 or a lone surrogate
    /// escape, read with a lenient parse that does not validate strings. Nil when even that parse fails, or when the
    /// payload names a method: a server request's id is the server's own and matches none of the client's.
    static func responseID(ofUndecodable payload: Data) -> JSONRPCID? {
        // A payload that is not JSON even leniently has no id to read; the caller logs why decode refused it.
        guard let root = try? AemiJSON.parse(payload, options: .lenient).root, root["method"].string == nil else {
            return nil
        }
        let idNode = root["id"]
        return idNode.int.map(JSONRPCID.number) ?? idNode.string.map(JSONRPCID.string)
    }
}
