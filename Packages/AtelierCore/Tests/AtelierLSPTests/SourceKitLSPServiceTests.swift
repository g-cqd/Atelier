import AemiTestKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierLSP

private struct SentEnvelope: Decodable {
    let jsonrpc: String
    let id: JSONRPCID?
    let method: String
    let params: JSONValue?
}

/// Reads one sent frame back as a typed envelope.
private func decodeSent(_ transport: PipeTransport, at index: Int) async throws -> SentEnvelope {
    let frames = await transport.sink.all
    return try JSONDecoder().decode(SentEnvelope.self, from: unframe(frames[index]))
}

/// Delivers a framed JSON-RPC response for `id`.
private func respond(_ transport: PipeTransport, id: JSONRPCID, result: JSONValue) throws {
    transport.deliver(LSPFrameCodec.frame(try JSONRPCMessage.response(id: id, result: result)))
}

private func hoverResult(markdown: String) -> JSONValue {
    .object(["contents": .object(["kind": .string("markdown"), "value": .string(markdown)])])
}

/// Mirrors `DidOpenTextDocumentParams`, which is `Encodable`-only in the library; a test that inspects a sent
/// `didOpen` needs to decode it back.
private struct DecodedDidOpenParams: Decodable {
    let textDocument: TextDocumentItem
}

/// Mirrors `DidCloseTextDocumentParams`, likewise `Encodable`-only.
private struct DecodedDidCloseParams: Decodable {
    let textDocument: TextDocumentIdentifier
}

@Suite
struct SourceKitLSPServiceTests {
    @Test
    func `hover performs the initialize handshake once and returns markdown`() async throws {
        let factory = ScriptedConnectionFactory()
        let configuration = SourceKitLSPService.Configuration(
            serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
        let service = SourceKitLSPService(configuration: configuration) { _ in await factory.make() }

        async let hover = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "let x = 1", line: 0, utf16Column: 4)

        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(1)
        let initializeEnvelope = try await decodeSent(transport, at: 0)
        #expect(initializeEnvelope.method == "initialize")
        try respond(transport, id: try #require(initializeEnvelope.id), result: .object([:]))

        await transport.sink.waitForCount(3)
        let initializedEnvelope = try await decodeSent(transport, at: 1)
        #expect(initializedEnvelope.method == "initialized")
        let didOpenEnvelope = try await decodeSent(transport, at: 2)
        #expect(didOpenEnvelope.method == "textDocument/didOpen")

        await transport.sink.waitForCount(4)
        let hoverEnvelope = try await decodeSent(transport, at: 3)
        #expect(hoverEnvelope.method == "textDocument/hover")
        try respond(transport, id: try #require(hoverEnvelope.id), result: hoverResult(markdown: "**x**"))

        let content = await hover
        #expect(content?.markdown == "**x**")
        #expect(content?.source == .languageServer)
        #expect(await factory.generationCount == 1)
    }

    @Test
    func `didOpen fires once per uri and reopens with a bumped version on changed content`() async throws {
        let factory = ScriptedConnectionFactory()
        let configuration = SourceKitLSPService.Configuration(
            serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
        let service = SourceKitLSPService(configuration: configuration) { _ in await factory.make() }

        // First hover: initialize, initialized, didOpen v1, hover.
        async let first = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "let x = 1", line: 0, utf16Column: 4)
        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(1)
        try respond(
            transport, id: try #require(try await decodeSent(transport, at: 0).id), result: .object([:]))
        await transport.sink.waitForCount(4)
        let firstOpen = try await decodeSent(transport, at: 2)
        #expect(firstOpen.method == "textDocument/didOpen")
        try respond(
            transport, id: try #require(try await decodeSent(transport, at: 3).id), result: hoverResult(markdown: "a"))
        _ = try #require(await first)

        // Second hover, same content: no new open/close, straight to hover.
        async let second = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "let x = 1", line: 0, utf16Column: 4)
        await transport.sink.waitForCount(5)
        let secondHover = try await decodeSent(transport, at: 4)
        #expect(secondHover.method == "textDocument/hover")
        try respond(
            transport, id: try #require(secondHover.id), result: hoverResult(markdown: "a"))
        _ = try #require(await second)

        // Third hover, changed content: didClose then didOpen (version bumped), then hover.
        async let third = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "let x = 2", line: 0, utf16Column: 4)
        await transport.sink.waitForCount(8)
        let didClose = try await decodeSent(transport, at: 5)
        #expect(didClose.method == "textDocument/didClose")
        let reopen = try await decodeSent(transport, at: 6)
        #expect(reopen.method == "textDocument/didOpen")
        let reopenParams = try #require(reopen.params)
        let reopenData = try JSONEncoder().encode(reopenParams)
        let reopenPayload = try JSONDecoder().decode(DecodedDidOpenParams.self, from: reopenData)
        #expect(reopenPayload.textDocument.version == 2)
        let thirdHover = try await decodeSent(transport, at: 7)
        #expect(thirdHover.method == "textDocument/hover")
        try respond(transport, id: try #require(thirdHover.id), result: hoverResult(markdown: "b"))
        let thirdResult = try #require(await third)
        #expect(thirdResult.markdown == "b")
    }

    @Test
    func `the least recently used document is closed past the open limit`() async throws {
        let factory = ScriptedConnectionFactory()
        var configuration = SourceKitLSPService.Configuration(
            serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
        configuration.openDocumentLimit = 1
        let service = SourceKitLSPService(configuration: configuration) { _ in await factory.make() }

        async let first = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "a", line: 0, utf16Column: 0)
        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(1)
        try respond(
            transport, id: try #require(try await decodeSent(transport, at: 0).id), result: .object([:]))
        await transport.sink.waitForCount(4)
        #expect(try await decodeSent(transport, at: 2).method == "textDocument/didOpen")
        try respond(
            transport, id: try #require(try await decodeSent(transport, at: 3).id), result: hoverResult(markdown: "a"))
        _ = try #require(await first)

        // Second document evicts the first: didClose(a), didOpen(b), hover(b).
        async let second = service.hover(
            uri: "file:///b.swift", languageID: "swift", content: "b", line: 0, utf16Column: 0)
        await transport.sink.waitForCount(7)
        let evictClose = try await decodeSent(transport, at: 4)
        #expect(evictClose.method == "textDocument/didClose")
        let evictCloseParams = try #require(evictClose.params)
        let evictCloseData = try JSONEncoder().encode(evictCloseParams)
        let evictClosePayload = try JSONDecoder().decode(DecodedDidCloseParams.self, from: evictCloseData)
        #expect(evictClosePayload.textDocument.uri == "file:///a.swift")
        #expect(try await decodeSent(transport, at: 5).method == "textDocument/didOpen")
        try respond(
            transport, id: try #require(try await decodeSent(transport, at: 6).id), result: hoverResult(markdown: "b"))
        _ = try #require(await second)
    }

    @Test
    func `a request that never answers times out to nil and sends cancelRequest`() async throws {
        let factory = ScriptedConnectionFactory()
        var configuration = SourceKitLSPService.Configuration(
            serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
        configuration.requestTimeout = .milliseconds(50)
        let service = SourceKitLSPService(configuration: configuration) { _ in await factory.make() }

        async let hover = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "a", line: 0, utf16Column: 0)
        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(1)
        try respond(
            transport, id: try #require(try await decodeSent(transport, at: 0).id), result: .object([:]))
        await transport.sink.waitForCount(4)
        let hoverEnvelope = try await decodeSent(transport, at: 3)
        #expect(hoverEnvelope.method == "textDocument/hover")
        // Never respond to the hover request.

        let content = await hover
        #expect(content == nil)

        await transport.sink.waitForCount(5)
        let cancelEnvelope = try await decodeSent(transport, at: 4)
        #expect(cancelEnvelope.method == "$/cancelRequest")
    }

    @Test
    func `a server that never answers initialize exhausts the restart budget`() async throws {
        let factory = ScriptedConnectionFactory()
        var configuration = SourceKitLSPService.Configuration(
            serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
        configuration.requestTimeout = .milliseconds(10)
        configuration.maximumRestarts = 2
        // Zero, so idle-shutdown sleeps resolve at once and are never mistaken for the timeouts below.
        configuration.idleShutdown = .zero
        let clock = TestClock()
        let service = SourceKitLSPService(configuration: configuration, clock: clock) { _ in await factory.make() }

        // Three attempts total: the first try plus two restarts. Each times out on `initialize` and, except
        // the last, backs off for one second on the injected clock before the next hover can reconnect.
        for attempt in 0 ..< 3 {
            async let hover = service.hover(
                uri: "file:///a.swift", languageID: "swift", content: "a", line: 0, utf16Column: 0)
            // This attempt's own timeout sleeper, whatever sleepers are already parked.
            try await clock.waitForAdditionalSleepers(1)
            clock.advance(by: .milliseconds(10))
            if attempt < 2 {
                try await clock.waitForAdditionalSleepers(1)
                clock.advance(by: .seconds(1))
            }
            let content = await hover
            #expect(content == nil)
        }

        #expect(await factory.generationCount == 3)

        // Past the budget: hover returns nil immediately, without asking the factory again.
        let content = await service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "a", line: 0, utf16Column: 0)
        #expect(content == nil)
        #expect(await factory.generationCount == 3)
    }

    @Test
    func `two concurrent first hovers share one connection instead of racing two initializes`() async throws {
        let factory = ScriptedConnectionFactory()
        let configuration = SourceKitLSPService.Configuration(
            serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
        let service = SourceKitLSPService(configuration: configuration) { _ in await factory.make() }

        async let first = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "a", line: 0, utf16Column: 0)
        async let second = service.hover(
            uri: "file:///b.swift", languageID: "swift", content: "b", line: 0, utf16Column: 0)

        // Only one connection should ever be requested from the factory, no matter how the two hovers
        // interleave their awaits.
        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(1)
        let initializeEnvelope = try await decodeSent(transport, at: 0)
        #expect(initializeEnvelope.method == "initialize")
        try respond(transport, id: try #require(initializeEnvelope.id), result: .object([:]))

        // Both hovers proceed once the shared handshake completes: didOpen ×2 plus hover ×2, in some order,
        // over the one connection.
        await transport.sink.waitForCount(6)
        for index in 2 ..< 6 {
            let envelope = try await decodeSent(transport, at: index)
            if envelope.method == "textDocument/hover" {
                try respond(transport, id: try #require(envelope.id), result: hoverResult(markdown: "x"))
            }
        }

        let (firstResult, secondResult) = await (first, second)
        #expect(firstResult != nil)
        #expect(secondResult != nil)
        #expect(await factory.generationCount == 1)
    }

    @Test
    func `a connection that fails to initialize is stopped rather than leaked`() async throws {
        let factory = ScriptedConnectionFactory()
        var configuration = SourceKitLSPService.Configuration(
            serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
        configuration.requestTimeout = .milliseconds(10)
        configuration.maximumRestarts = 0
        configuration.idleShutdown = .zero
        let clock = TestClock()
        let service = SourceKitLSPService(configuration: configuration, clock: clock) { _ in await factory.make() }

        async let hover = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "a", line: 0, utf16Column: 0)
        try await clock.waitForAdditionalSleepers(1)
        clock.advance(by: .milliseconds(10))
        let content = await hover
        #expect(content == nil)

        // The connection that never answered `initialize` must have had its transport closed, not left
        // running behind a session that gave up on it.
        let transport = await factory.transport(at: 0)
        #expect(await transport.closeCount.count == 1)
    }

    @Test
    func `an idle session shuts down gracefully and reconnects on the next hover`() async throws {
        let factory = ScriptedConnectionFactory()
        var configuration = SourceKitLSPService.Configuration(
            serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
        configuration.idleShutdown = .milliseconds(10)
        let clock = TestClock()
        let service = SourceKitLSPService(configuration: configuration, clock: clock) { _ in await factory.make() }

        async let hover = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "a", line: 0, utf16Column: 0)
        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(1)
        try respond(
            transport, id: try #require(try await decodeSent(transport, at: 0).id), result: .object([:]))
        await transport.sink.waitForCount(4)
        try respond(
            transport, id: try #require(try await decodeSent(transport, at: 3).id), result: hoverResult(markdown: "a"))
        _ = try #require(await hover)

        // The request timeouts were unparked when hover() returned, so the parked sleeper is the idle shutdown.
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(10))

        // Graceful teardown: a `shutdown` request, answered here, then `exit`.
        await transport.sink.waitForCount(5)
        let shutdownEnvelope = try await decodeSent(transport, at: 4)
        #expect(shutdownEnvelope.method == "shutdown")
        try respond(transport, id: try #require(shutdownEnvelope.id), result: .null)

        await transport.sink.waitForCount(6)
        let exitEnvelope = try await decodeSent(transport, at: 5)
        #expect(exitEnvelope.method == "exit")

        // The next hover reconnects from scratch, on a new transport.
        async let second = service.hover(
            uri: "file:///a.swift", languageID: "swift", content: "a", line: 0, utf16Column: 0)
        await factory.waitForGeneration(2)
        let secondTransport = await factory.transport(at: 1)
        await secondTransport.sink.waitForCount(1)
        #expect(try await decodeSent(secondTransport, at: 0).method == "initialize")
        try respond(
            secondTransport, id: try #require(try await decodeSent(secondTransport, at: 0).id), result: .object([:]))
        await secondTransport.sink.waitForCount(4)
        try respond(
            secondTransport, id: try #require(try await decodeSent(secondTransport, at: 3).id),
            result: hoverResult(markdown: "a"))
        _ = try #require(await second)
        #expect(await factory.generationCount == 2)
    }
}
