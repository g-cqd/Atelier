import Foundation
import Testing

@testable import AtelierLSP

private struct EmptyParams: Encodable, Sendable {}

private struct Payload: Codable, Equatable, Sendable {
    let value: Int
}

private struct SentEnvelope: Decodable {
    let jsonrpc: String
    let id: JSONRPCID?
    let method: String
    let params: JSONValue?
}

private struct CancelPayload: Decodable {
    let id: JSONRPCID
}

private struct ResultOnlyEnvelope: Decodable {
    let result: JSONValue?
}

@Suite
struct LSPConnectionTests {
    @Test
    func `request round trip decodes a typed result`() async throws {
        let transport = PipeTransport()
        let connection = LSPConnection(transport: transport)
        await connection.start()

        async let result = connection.request("thing/get", EmptyParams(), as: Payload.self)
        await transport.sink.waitForCount(1)

        let sent = await transport.sink.all[0]
        let envelope = try JSONDecoder().decode(SentEnvelope.self, from: unframe(sent))
        #expect(envelope.method == "thing/get")
        let id = try #require(envelope.id)

        transport.deliver(
            LSPFrameCodec.frame(try JSONRPCMessage.response(id: id, result: .object(["value": .number(42)]))))

        let payload = try await result
        #expect(payload == Payload(value: 42))
    }

    @Test
    func `concurrent requests are matched by id even when responses arrive out of order`() async throws {
        let transport = PipeTransport()
        let connection = LSPConnection(transport: transport)
        await connection.start()

        async let first = connection.request("a", EmptyParams(), as: Payload.self)
        async let second = connection.request("b", EmptyParams(), as: Payload.self)
        await transport.sink.waitForCount(2)

        let frames = await transport.sink.all
        let firstEnvelope = try JSONDecoder().decode(SentEnvelope.self, from: unframe(frames[0]))
        let secondEnvelope = try JSONDecoder().decode(SentEnvelope.self, from: unframe(frames[1]))
        let firstID = try #require(firstEnvelope.id)
        let secondID = try #require(secondEnvelope.id)

        // Respond to the second request first.
        transport.deliver(
            LSPFrameCodec.frame(try JSONRPCMessage.response(id: secondID, result: .object(["value": .number(2)]))))
        transport.deliver(
            LSPFrameCodec.frame(try JSONRPCMessage.response(id: firstID, result: .object(["value": .number(1)]))))

        let (firstPayload, secondPayload) = try await (first, second)
        #expect(firstPayload == Payload(value: 1))
        #expect(secondPayload == Payload(value: 2))
    }

    @Test
    func `server error response throws serverError`() async throws {
        let transport = PipeTransport()
        let connection = LSPConnection(transport: transport)
        await connection.start()

        let task = Task {
            try await connection.request("thing/get", EmptyParams(), as: Payload.self)
        }
        await transport.sink.waitForCount(1)
        let envelope = try JSONDecoder().decode(SentEnvelope.self, from: unframe(await transport.sink.all[0]))
        let id = try #require(envelope.id)

        transport.deliver(LSPFrameCodec.frame(try JSONRPCMessage.errorResponse(id: id, code: -32_601, message: "nope")))

        await #expect(throws: LSPConnectionError.serverError(JSONRPCError(code: -32_601, message: "nope"))) {
            _ = try await task.value
        }
    }

    @Test
    func `cancelling a pending request throws CancellationError and sends dollar cancelRequest`() async throws {
        let transport = PipeTransport()
        let connection = LSPConnection(transport: transport)
        await connection.start()

        let task = Task {
            try await connection.request("slow/thing", EmptyParams(), as: Payload.self)
        }
        await transport.sink.waitForCount(1)
        let requestID = try #require(
            try JSONDecoder().decode(SentEnvelope.self, from: unframe(await transport.sink.all[0])).id)

        task.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        await transport.sink.waitForCount(2)
        let cancelEnvelope = try JSONDecoder().decode(SentEnvelope.self, from: unframe(await transport.sink.all[1]))
        #expect(cancelEnvelope.method == "$/cancelRequest")
        let cancelParamsData = try JSONEncoder().encode(cancelEnvelope.params)
        let cancelPayload = try JSONDecoder().decode(CancelPayload.self, from: cancelParamsData)
        #expect(cancelPayload.id == requestID)
    }

    @Test
    func `transport ending fails pending requests and later calls fail immediately`() async throws {
        let transport = PipeTransport()
        let connection = LSPConnection(transport: transport)
        await connection.start()

        let task = Task {
            try await connection.request("thing/get", EmptyParams(), as: Payload.self)
        }
        await transport.sink.waitForCount(1)

        transport.endIncoming()

        await #expect(throws: LSPConnectionError.self) {
            _ = try await task.value
        }

        await #expect(throws: LSPConnectionError.self) {
            _ = try await connection.request("another", EmptyParams(), as: Payload.self)
        }
    }

    @Test
    func `workspace configuration server request is answered`() async throws {
        let transport = PipeTransport()
        let connection = LSPConnection(transport: transport)
        await connection.start()

        let payload = Data(
            #"{"jsonrpc":"2.0","id":1,"method":"workspace/configuration","params":{"items":[]}}"#.utf8)
        transport.deliver(LSPFrameCodec.frame(payload))

        await transport.sink.waitForCount(1)
        let response = try JSONDecoder()
            .decode(
                ResultOnlyEnvelope.self, from: unframe(await transport.sink.all[0]))
        #expect(response.result == .array([.null]))
    }

    @Test
    func `unknown server request gets a method not found error`() async throws {
        let transport = PipeTransport()
        let connection = LSPConnection(transport: transport)
        await connection.start()

        let payload = Data(#"{"jsonrpc":"2.0","id":7,"method":"window/somethingElse","params":{}}"#.utf8)
        transport.deliver(LSPFrameCodec.frame(payload))

        await transport.sink.waitForCount(1)
        let message = try IncomingMessage.decode(unframe(await transport.sink.all[0]))
        guard case .response(let id, let result, let error) = message else {
            Issue.record("expected an error response")
            return
        }
        #expect(id == .number(7))
        #expect(result == nil)
        #expect(error == JSONRPCError(code: -32_601, message: "method not found"))
    }

    @Test
    func `notifications from the server are ignored`() async throws {
        let transport = PipeTransport()
        let connection = LSPConnection(transport: transport)
        await connection.start()

        let payload = Data(#"{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{}}"#.utf8)
        transport.deliver(LSPFrameCodec.frame(payload))

        // Prove liveness: a subsequent request still round-trips normally, so the notification didn't wedge
        // the read loop or produce a stray reply.
        async let result = connection.request("thing/get", EmptyParams(), as: Payload.self)
        await transport.sink.waitForCount(1)
        let envelope = try JSONDecoder().decode(SentEnvelope.self, from: unframe(await transport.sink.all[0]))
        let id = try #require(envelope.id)
        transport.deliver(
            LSPFrameCodec.frame(try JSONRPCMessage.response(id: id, result: .object(["value": .number(9)]))))

        let payloadResult = try await result
        #expect(payloadResult == Payload(value: 9))
    }
}
