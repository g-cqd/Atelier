import Foundation
import Testing

@testable import AtelierLSP

private struct Params: Codable, Equatable {
    let value: Int
}

private struct RawEnvelope: Decodable {
    let jsonrpc: String
    let id: JSONRPCID?
    let method: String?
    let params: Params?
}

@Suite
struct JSONRPCTests {
    @Test
    func `request encodes a decodable jsonrpc 2 point 0 envelope`() throws {
        let data = try JSONRPCMessage.request(id: .number(1), method: "initialize", params: Params(value: 42))
        let envelope = try JSONDecoder().decode(RawEnvelope.self, from: data)
        #expect(envelope.jsonrpc == "2.0")
        #expect(envelope.id == .number(1))
        #expect(envelope.method == "initialize")
        #expect(envelope.params == Params(value: 42))
    }

    @Test
    func `notification encodes without an id`() throws {
        let data = try JSONRPCMessage.notification(method: "initialized", params: Params(value: 1))
        let envelope = try JSONDecoder().decode(RawEnvelope.self, from: data)
        #expect(envelope.jsonrpc == "2.0")
        #expect(envelope.id == nil)
        #expect(envelope.method == "initialized")
    }

    @Test
    func `response encodes a result`() throws {
        let data = try JSONRPCMessage.response(id: .string("a"), result: .object(["ok": .bool(true)]))
        let message = try IncomingMessage.decode(data)
        guard case .response(let id, let result, let error) = message else {
            Issue.record("expected a response")
            return
        }
        #expect(id == .string("a"))
        #expect(error == nil)
        let resultData = try #require(result)
        let decodedResult = try JSONDecoder().decode(JSONValue.self, from: resultData)
        #expect(decodedResult == .object(["ok": .bool(true)]))
    }

    @Test
    func `errorResponse encodes an error`() throws {
        let data = try JSONRPCMessage.errorResponse(id: .number(9), code: -32600, message: "bad request")
        let message = try IncomingMessage.decode(data)
        guard case .response(let id, let result, let error) = message else {
            Issue.record("expected a response")
            return
        }
        #expect(id == .number(9))
        #expect(result == nil)
        #expect(error == JSONRPCError(code: -32600, message: "bad request"))
    }

    @Test
    func `decode classifies a server request`() throws {
        let payload = Data(#"{"jsonrpc":"2.0","id":3,"method":"window/workDoneProgress/create","params":{}}"#.utf8)
        let message = try IncomingMessage.decode(payload)
        guard case .serverRequest(let id, let method) = message else {
            Issue.record("expected a server request")
            return
        }
        #expect(id == .number(3))
        #expect(method == "window/workDoneProgress/create")
    }

    @Test
    func `decode classifies a notification`() throws {
        let payload = Data(#"{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{}}"#.utf8)
        let message = try IncomingMessage.decode(payload)
        guard case .notification(let method) = message else {
            Issue.record("expected a notification")
            return
        }
        #expect(method == "textDocument/publishDiagnostics")
    }

    @Test
    func `decode without id or method throws`() {
        let payload = Data(#"{"jsonrpc":"2.0"}"#.utf8)
        #expect(throws: JSONRPCDecodingError.missingIdentifyingField) {
            _ = try IncomingMessage.decode(payload)
        }
    }

    @Test
    func `JSONValue round-trips every case`() throws {
        let values: [JSONValue] = [
            .null,
            .bool(true),
            .number(3.5),
            .string("hi"),
            .array([.number(1), .string("two")]),
            .object(["k": .bool(false)])
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            #expect(decoded == value)
        }
    }
}
