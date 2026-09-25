import AemiTestKit
import AtelierHighlighting
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierLSP

/// A frame the client sent, with its parameters as JSON.
private struct Sent: Decodable {
    let id: JSONRPCID?
    let method: String?
    let params: JSONValue?
}

/// A reply the client sent to a server's request, with its result as JSON, `null` included.
private struct Reply: Decodable {
    let id: JSONRPCID
    let result: JSONValue
}

private func sent(_ transport: PipeTransport, at index: Int) async throws -> Sent {
    try JSONDecoder().decode(Sent.self, from: unframe(await transport.sink.all[index]))
}

private func respond(_ transport: PipeTransport, to frame: Sent, with result: JSONValue) throws {
    transport.deliver(LSPFrameCodec.frame(try JSONRPCMessage.response(id: try #require(frame.id), result: result)))
}

/// The legend the scripted server gives: keywords, variables and functions.
private let legend = SemanticTokensLegend(
    tokenTypes: ["keyword", "variable", "function"], tokenModifiers: ["declaration"])

/// An `initialize` answer that gives semantic tokens with `legend`, deltas included.
private let initializeWithTokens: JSONValue = .object([
    "capabilities": .object([
        "semanticTokensProvider": .object([
            "legend": .object([
                "tokenTypes": .array(legend.tokenTypes.map(JSONValue.string)),
                "tokenModifiers": .array(legend.tokenModifiers.map(JSONValue.string))
            ]),
            "full": .object(["delta": .bool(true)])
        ])
    ])
])

private func numbers(_ values: [UInt32]) -> JSONValue {
    .array(values.map { .number(Double($0)) })
}

private let uri = "file:///repo/Sources/A.swift"
private let text = "let value = compute()"
/// `let` a keyword, `value` a variable, `compute` a function, in the relative encoding.
private let tokens: [UInt32] = [0, 0, 3, 0, 0, 0, 4, 5, 1, 1, 0, 8, 7, 2, 0]

private func makeSession(_ factory: ScriptedConnectionFactory, clock: TestClock = TestClock()) -> LanguageServerSession
{
    LanguageServerSession(
        configuration: LanguageServerSession.Configuration(
            serverExecutable: URL(filePath: "/usr/bin/true"), workspaceRoot: URL(filePath: "/repo")),
        clock: clock
    ) { _ in await factory.make() }
}

private let revision = SourceRevision(documentID: "Sources/A.swift", language: .swift, key: .content("blob"))

private func request(_ text: String = text) -> TierRequest {
    TierRequest(revision: revision, text: text, lineRanges: [0 ..< text.utf8.count], visibleLines: 0 ..< 1)
}

@Suite
struct SemanticTokensTests {
    @Test
    func `the client advertises whole-document and delta semantic tokens, and their refresh`() throws {
        let data = try JSONEncoder().encode(ClientCapabilities())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let textDocument = try #require(json["textDocument"] as? [String: Any])
        let semantic = try #require(textDocument["semanticTokens"] as? [String: Any])
        let requests = try #require(semantic["requests"] as? [String: Any])
        let workspace = try #require(json["workspace"] as? [String: Any])

        #expect((requests["full"] as? [String: Any])?["delta"] as? Bool == true)
        #expect(requests["range"] as? Bool == false)
        #expect(semantic["formats"] as? [String] == ["relative"])
        #expect((semantic["tokenTypes"] as? [String])?.contains("variable") == true)
        #expect((semantic["tokenModifiers"] as? [String])?.contains("deprecated") == true)
        #expect((workspace["semanticTokens"] as? [String: Any])?["refreshSupport"] as? Bool == true)
    }

    @Test
    func `the first request asks for the whole document and answers with the server's data and legend`() async throws {
        let factory = ScriptedConnectionFactory(answering: [
            "initialize": initializeWithTokens, "shutdown": .null,
            "textDocument/semanticTokens/full": .object(["resultId": .string("1"), "data": numbers(tokens)])
        ])
        let session = makeSession(factory)

        let outcome = await session.semanticTokens(uri: uri, languageID: "swift", content: text)

        #expect(outcome == .tokens(data: tokens, legend: legend))
        let transport = await factory.transport(at: 0)
        let frames = try await (0 ..< transport.sink.all.count).asyncMap { try await sent(transport, at: $0) }
        #expect(
            frames.map(\.method) == [
                "initialize", "initialized", "textDocument/didOpen", "textDocument/semanticTokens/full"
            ])
        #expect(frames.last?.params == .object(["textDocument": .object(["uri": .string(uri)])]))
        await session.shutdown()
    }

    @Test
    func `a later request asks for a delta against the last result and applies its edits`() async throws {
        let changed: [UInt32] = [0, 0, 3, 0, 0, 0, 4, 5, 1, 1]
        let factory = ScriptedConnectionFactory(answering: [
            "initialize": initializeWithTokens, "shutdown": .null,
            "textDocument/semanticTokens/full": .object(["resultId": .string("1"), "data": numbers(tokens)]),
            "textDocument/semanticTokens/full/delta": .object([
                "resultId": .string("2"),
                "edits": .array([
                    .object(["start": .number(10), "deleteCount": .number(5)]),
                    .object(["start": .number(9), "deleteCount": .number(1), "data": numbers([1])])
                ])
            ])
        ])
        let session = makeSession(factory)

        _ = await session.semanticTokens(uri: uri, languageID: "swift", content: text)
        let second = await session.semanticTokens(uri: uri, languageID: "swift", content: "let value = 1")

        #expect(second == .tokens(data: changed, legend: legend))
        let transport = await factory.transport(at: 0)
        let frames = try await (0 ..< transport.sink.all.count).asyncMap { try await sent(transport, at: $0) }
        #expect(
            frames.dropFirst(4).map(\.method) == ["textDocument/didChange", "textDocument/semanticTokens/full/delta"])
        #expect(
            frames.last?.params
                == .object(["textDocument": .object(["uri": .string(uri)]), "previousResultId": .string("1")]))
        await session.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func `a reply for an older version of the document is dropped`() async throws {
        let factory = ScriptedConnectionFactory(answering: ["initialize": initializeWithTokens, "shutdown": .null])
        let session = makeSession(factory)

        async let outcome = session.semanticTokens(uri: uri, languageID: "swift", content: text)
        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(4)
        let pending = try await sent(transport, at: 3)
        #expect(pending.method == "textDocument/semanticTokens/full")
        // A hover with new text changes the document to version 2 while the tokens are out.
        async let hover = session.hover(
            uri: uri, languageID: "swift", content: "let other = 2", line: 0, utf16Column: 5)
        await transport.sink.waitForCount(6)
        #expect(try await sent(transport, at: 4).method == "textDocument/didChange")
        try respond(transport, to: pending, with: .object(["resultId": .string("1"), "data": numbers(tokens)]))
        try respond(transport, to: try await sent(transport, at: 5), with: .null)

        #expect(await outcome == .superseded)
        #expect(await hover == .answered(nil))
        await session.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func `a reply that does not come within the request timeout fails the tier with its deadline`() async throws {
        let factory = ScriptedConnectionFactory(answering: ["initialize": initializeWithTokens, "shutdown": .null])
        let clock = TestClock()
        let session = makeSession(factory, clock: clock)
        let tier = SemanticTokenTier { _ in SemanticTokenTier.Document(session: session, uri: uri, languageID: "swift")
        }

        async let failure: (any Error)? = {
            do {
                try await tier.run(request()) { _ in }
                return nil
            } catch {
                return error
            }
        }()
        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(4)
        #expect(try await sent(transport, at: 3).method == "textDocument/semanticTokens/full")
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: session.requestTimeout)

        #expect(await failure as? TierFailure == .deadline(.seconds(2)))
        await session.shutdown()
    }

    @Test
    func `a synthetic URI is never sent, and a text with no on-disk document asks nothing`() async throws {
        let factory = ScriptedConnectionFactory(answering: ["initialize": initializeWithTokens])
        let session = makeSession(factory)
        let tier = SemanticTokenTier { _ in nil }

        let outcome = await session.semanticTokens(
            uri: "atelier-blob://abc123/Sources/A.swift", languageID: "swift", content: text)
        await #expect(throws: TierFailure.failed("no on-disk document for the text")) {
            try await tier.run(request()) { _ in }
        }

        #expect(outcome == .unavailable)
        #expect(await factory.generationCount == 0)
    }

    @Test
    func `a server without semantic tokens is unsupported`() async {
        let factory = ScriptedConnectionFactory(answering: ["initialize": .object([:]), "shutdown": .null])
        let session = makeSession(factory)

        #expect(await session.semanticTokens(uri: uri, languageID: "swift", content: text) == .unsupported)
        await session.shutdown()
    }

    @Test
    func `the tier colours names only, and keeps every token's kind for hover`() async throws {
        let factory = ScriptedConnectionFactory(answering: [
            "initialize": initializeWithTokens, "shutdown": .null,
            "textDocument/semanticTokens/full": .object(["resultId": .string("1"), "data": numbers(tokens)])
        ])
        let session = makeSession(factory)
        let store = SyntaxFactsStore()
        let tier = SemanticTokenTier(store: store) { _ in
            SemanticTokenTier.Document(session: session, uri: uri, languageID: "swift")
        }
        var updates: [TierUpdate] = []

        try await tier.run(request()) { updates.append($0) }

        let line = try #require(updates.first?.tokens[0])
        #expect(line.map(\.start) == [4, 12])
        #expect(line.map(\.role) == [.variable, .function])
        #expect(updates.first?.layer == .semantic)
        #expect(updates.first?.coverage == .sparse)
        let kinds = try #require(store.symbolKinds(for: revision))
        #expect(kinds.kind(atUTF8: 1) == .keyword)
        #expect(kinds.kind(atUTF8: 6) == .symbol)
        #expect(kinds.kind(atUTF8: 10) == nil)
        await session.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func `the server's refresh request is answered`() async throws {
        let transport = PipeTransport()
        let connection = LSPConnection(transport: transport)
        await connection.start()

        transport.deliver(
            LSPFrameCodec.frame(Data(#"{"jsonrpc":"2.0","id":7,"method":"workspace/semanticTokens/refresh"}"#.utf8)))
        await transport.sink.waitForCount(1)

        let reply = try JSONDecoder().decode(Reply.self, from: unframe(await transport.sink.all[0]))
        #expect(reply.id == .number(7))
        #expect(reply.result == .null)
        await connection.stop()
    }
}

extension Sequence {
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        for element in self { results.append(try await transform(element)) }
        return results
    }
}
