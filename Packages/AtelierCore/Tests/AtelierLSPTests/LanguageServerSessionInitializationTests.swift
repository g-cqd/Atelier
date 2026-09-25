import AemiTestKit
import Foundation
import Testing

@testable import AtelierLSP

/// The `initialize` request as the server receives it, reduced to what these tests read.
private struct InitializeEnvelope: Decodable {
    struct Params: Decodable {
        let rootUri: String?
        let initializationOptions: JSONValue?
        let workspaceFolders: [WorkspaceFolder]?
    }

    let method: String
    let params: Params
}

/// A request the client sent, reduced to what these tests read.
private struct SentRequest: Decodable {
    let id: JSONRPCID
    let method: String
}

/// Captures the first `initialize` a service sends over an in-process transport, then ends the conversation so the
/// hover that triggered it returns.
private func capturedInitialize(configuration: LanguageServerSession.Configuration) async throws -> InitializeEnvelope {
    var configuration = configuration
    // No restart budget, so the failed handshake gives up at once instead of backing off on the virtual clock.
    configuration.maximumRestarts = 0
    let transport = PipeTransport()
    let service = LanguageServerSession(configuration: configuration, clock: TestClock()) { _ in
        LSPConnection(transport: transport)
    }

    async let hover = service.hover(
        uri: "file:///workspace/a.swift", languageID: "swift", content: "let x = 1", line: 0, utf16Column: 4)
    await transport.sink.waitForCount(1)
    let frames = await transport.sink.all
    let envelope = try JSONDecoder().decode(InitializeEnvelope.self, from: unframe(frames[0]))

    // A server that goes away fails the handshake at once, without a timeout to wait out.
    transport.endIncoming()
    _ = await hover
    await service.shutdown()
    return envelope
}

@Suite
struct LanguageServerSessionInitializationTests {
    @Test
    func `the initialize request turns background indexing off by default`() async throws {
        let configuration = LanguageServerSession.Configuration(
            serverExecutable: URL(filePath: "/usr/bin/true"),
            workspaceRoot: URL(filePath: "/workspace", directoryHint: .isDirectory))

        let envelope = try await capturedInitialize(configuration: configuration)

        #expect(envelope.method == "initialize")
        #expect(envelope.params.initializationOptions == .object(["backgroundIndexing": .bool(false)]))
        #expect(envelope.params.rootUri == "file:///workspace/")
    }

    @Test
    func `the initialize request lists the workspace root as the session's one folder`() async throws {
        let configuration = LanguageServerSession.Configuration(
            serverExecutable: URL(filePath: "/usr/bin/true"),
            workspaceRoot: URL(filePath: "/workspace", directoryHint: .isDirectory))

        let envelope = try await capturedInitialize(configuration: configuration)

        #expect(envelope.params.workspaceFolders == [WorkspaceFolder(uri: "file:///workspace/", name: "workspace")])
    }

    @Test
    func `a configuration without initialization options sends none`() async throws {
        var configuration = LanguageServerSession.Configuration(
            serverExecutable: URL(filePath: "/usr/bin/true"),
            workspaceRoot: URL(filePath: "/workspace", directoryHint: .isDirectory))
        configuration.initializationOptions = nil

        let envelope = try await capturedInitialize(configuration: configuration)

        #expect(envelope.params.initializationOptions == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `an initialize reply nested past the result depth cap still completes the handshake`() async throws {
        let transport = PipeTransport()
        let service = LanguageServerSession(
            configuration: LanguageServerSession.Configuration(
                serverExecutable: URL(filePath: "/usr/bin/true"),
                workspaceRoot: URL(filePath: "/workspace", directoryHint: .isDirectory)),
            clock: TestClock()
        ) { _ in LSPConnection(transport: transport) }

        async let hover = service.hover(
            uri: "file:///workspace/a.swift", languageID: "swift", content: "let x = 1", line: 0, utf16Column: 4)
        await transport.sink.waitForCount(1)
        let initialize = try JSONDecoder().decode(SentRequest.self, from: unframe(await transport.sink.all[0]))
        let capabilities = nestedValue(depth: LSPConnection.maximumResultDepth + 16)
        transport.deliver(
            LSPFrameCodec.frame(
                try JSONRPCMessage.response(id: initialize.id, result: .object(["capabilities": capabilities]))))

        // `initialized`, `didOpen` and the hover itself follow only a completed handshake.
        await transport.sink.waitForCount(4)
        let hoverRequest = try JSONDecoder().decode(SentRequest.self, from: unframe(await transport.sink.all[3]))
        #expect(hoverRequest.method == "textDocument/hover")
        transport.deliver(LSPFrameCodec.frame(try JSONRPCMessage.response(id: hoverRequest.id, result: .null)))
        _ = await hover
        transport.endIncoming()
    }
}
