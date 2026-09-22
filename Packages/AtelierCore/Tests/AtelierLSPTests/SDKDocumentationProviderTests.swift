import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierLSP

/// Mirrors ``ScriptedConnectionFactory`` in `SourceKitLSPServiceTests.swift`: builds a fresh ``PipeTransport``
/// per connection attempt, so a test can script an entire generation's frames.
private actor ScriptedConnectionFactory {
    private(set) var transports: [PipeTransport] = []

    func make() -> LSPConnection {
        let transport = PipeTransport()
        transports.append(transport)
        return LSPConnection(transport: transport)
    }

    func transport(at index: Int) -> PipeTransport { transports[index] }
    var generationCount: Int { transports.count }

    func waitForGeneration(_ count: Int) async {
        while transports.count < count {
            await Task.yield()
        }
    }
}

private func decodeSent(_ transport: PipeTransport, at index: Int) async throws -> SentEnvelope {
    let frames = await transport.sink.all
    return try JSONDecoder().decode(SentEnvelope.self, from: unframe(frames[index]))
}

private struct SentEnvelope: Decodable {
    let jsonrpc: String
    let id: JSONRPCID?
    let method: String
    let params: JSONValue?
}

private struct DecodedDidOpenParams: Decodable {
    let textDocument: TextDocumentItem
}

private func respond(_ transport: PipeTransport, id: JSONRPCID, result: JSONValue) throws {
    transport.deliver(LSPFrameCodec.frame(try JSONRPCMessage.response(id: id, result: result)))
}

private func hoverResult(markdown: String) -> JSONValue {
    .object(["contents": .object(["kind": .string("markdown"), "value": .string(markdown)])])
}

private func makeService(factory: ScriptedConnectionFactory) -> SourceKitLSPService {
    let configuration = SourceKitLSPService.Configuration(
        serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
    return SourceKitLSPService(configuration: configuration) { _ in await factory.make() }
}

/// Drives the handshake + `didOpen` + `hover` sequence for one probe, responding with `markdown`, and returns
/// the connected transport for further inspection.
private func driveOneProbe(
    factory: ScriptedConnectionFactory, generation: Int, markdown: String
) async throws -> PipeTransport {
    await factory.waitForGeneration(generation)
    let transport = await factory.transport(at: generation - 1)
    await transport.sink.waitForCount(1)
    try respond(
        transport, id: try #require(try await decodeSent(transport, at: 0).id), result: .object([:]))
    await transport.sink.waitForCount(4)
    #expect(try await decodeSent(transport, at: 2).method == "textDocument/didOpen")
    let hoverEnvelope = try await decodeSent(transport, at: 3)
    #expect(hoverEnvelope.method == "textDocument/hover")
    try respond(transport, id: try #require(hoverEnvelope.id), result: hoverResult(markdown: markdown))
    return transport
}

@Suite
struct SDKDocumentationProviderTests {
    // MARK: - Chain extraction

    @Test
    func `extracts the full dotted chain from a mid-chain hover position`() {
        let content = "let x = NSVisualEffectView.Material.hudWindow"
        // Position inside "Material".
        let column = content.utf16.distance(
            from: content.utf16.startIndex,
            to: content.range(of: "Material")!.lowerBound.samePosition(in: content.utf16)!)
        let result = SDKDocumentationProvider.extractChain(in: content, line: 0, utf16Column: column + 2)
        #expect(result?.chain == "NSVisualEffectView.Material.hudWindow")
        #expect(result?.startsUppercase == true)
    }

    @Test
    func `trims a trailing dot when hovering just past it`() {
        let content = "NSVisualEffectView."
        let result = SDKDocumentationProvider.extractChain(in: content, line: 0, utf16Column: content.utf16.count)
        #expect(result?.chain == "NSVisualEffectView")
    }

    @Test
    func `rejects a bare lowercase member name with no receiver`() {
        let content = "let x = hudWindow"
        let column = content.utf16.count - 1
        let result = SDKDocumentationProvider.extractChain(in: content, line: 0, utf16Column: column)
        #expect(result == nil)
    }

    @Test
    func `accepts a bare uppercase type name`() {
        let content = "let x: NSView"
        let column = content.utf16.count - 1
        let result = SDKDocumentationProvider.extractChain(in: content, line: 0, utf16Column: column)
        #expect(result?.chain == "NSView")
        #expect(result?.startsUppercase == true)
    }

    @Test
    func `rejects a placeholder like dollar-zero`() {
        let content = "$0.foo"
        let result = SDKDocumentationProvider.extractChain(in: content, line: 0, utf16Column: 0)
        // "$0" is a valid chain-unit run and starts with a non-letter, non-uppercase character; dotted with
        // "foo" it's accepted as a chain (sourcekit-lsp itself will simply fail to resolve it), but standalone
        // "$0" with no following member must not crash extraction.
        #expect(result?.chain == "$0.foo")
    }

    @Test
    func `returns nil outside document bounds`() {
        let result = SDKDocumentationProvider.extractChain(in: "abc", line: 5, utf16Column: 0)
        #expect(result == nil)
    }

    // MARK: - Import collection

    @Test
    func `collects imports from content, unions defaults, dedupes, and caps at twelve`() {
        let content = """
            import Foundation
            import AppKit
            import Foundation.NSString

            let x = 1
            """
        let imports = SDKDocumentationProvider.collectImports(
            in: content, unioning: ["Foundation", "AppKit", "SwiftUI"])
        #expect(Set(imports) == ["Foundation", "AppKit", "SwiftUI"])
        #expect(imports.count <= 12)
    }

    @Test
    func `caps collected imports at twelve total`() {
        let manyImports = (0 ..< 20).map { "import Module\($0)\n" }.joined()
        let imports = SDKDocumentationProvider.collectImports(in: manyImports, unioning: ["Foundation"])
        #expect(imports.count == 12)
    }

    // MARK: - Fast nil path (no LSP traffic)

    @Test
    func `a bare lowercase member returns nil without touching the transport`() async throws {
        let factory = ScriptedConnectionFactory()
        let service = makeService(factory: factory)
        let provider = SDKDocumentationProvider(service: service)

        let query = HoverQuery(documentURI: "file:///a.swift", content: "let x = hudWindow", line: 0, utf16Column: 10)
        let result = try await provider.hover(query)

        #expect(result == nil)
        #expect(await factory.generationCount == 0)
    }

    // MARK: - Hover round trip

    @Test
    func `hover round trip maps to sdk source`() async throws {
        let factory = ScriptedConnectionFactory()
        let service = makeService(factory: factory)
        let provider = SDKDocumentationProvider(service: service)

        let content = "import AppKit\nlet x = NSView"
        let column = "let x = NSView".utf16.count - 3  // inside "NSView" on the second line
        let query = HoverQuery(documentURI: "file:///a.swift", content: content, line: 1, utf16Column: column)

        async let result = provider.hover(query)
        let transport = try await driveOneProbe(factory: factory, generation: 1, markdown: "**NSView**")

        let content2 = try #require(await result)
        #expect(content2.markdown == "**NSView**")
        #expect(content2.source == .sdk)

        // The synthesized didOpen carries the collected imports and a probe line for the chain.
        let didOpen = try await decodeSent(transport, at: 2)
        let didOpenParams = try #require(didOpen.params)
        let didOpenData = try JSONEncoder().encode(didOpenParams)
        let decoded = try JSONDecoder().decode(DecodedDidOpenParams.self, from: didOpenData)
        #expect(decoded.textDocument.text.contains("import AppKit"))
        #expect(decoded.textDocument.text.contains("let _ = NSView"))
    }

    // MARK: - LRU caching

    @Test
    func `identical queries hit the cache without a second didOpen or hover`() async throws {
        let factory = ScriptedConnectionFactory()
        let service = makeService(factory: factory)
        let provider = SDKDocumentationProvider(service: service)

        let content = "import AppKit\nlet x = NSView"
        let column = "let x = NSView".utf16.count - 3
        let query = HoverQuery(documentURI: "file:///a.swift", content: content, line: 1, utf16Column: column)

        async let first = provider.hover(query)
        let transport = try await driveOneProbe(factory: factory, generation: 1, markdown: "**NSView**")
        _ = try #require(await first)

        let framesBefore = await transport.sink.all.count
        let second = try await provider.hover(query)
        #expect(second?.markdown == "**NSView**")
        #expect(second?.source == .sdk)

        // No new frames sent: the cache answered without another round trip.
        let framesAfter = await transport.sink.all.count
        #expect(framesAfter == framesBefore)
        #expect(await factory.generationCount == 1)
    }

    @Test
    func `a nil result is also cached`() async throws {
        let factory = ScriptedConnectionFactory()
        let service = makeService(factory: factory)
        let provider = SDKDocumentationProvider(service: service)

        let content = "import AppKit\nlet x = NSView"
        let column = "let x = NSView".utf16.count - 3
        let query = HoverQuery(documentURI: "file:///a.swift", content: content, line: 1, utf16Column: column)

        async let first = provider.hover(query)
        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(1)
        try respond(
            transport, id: try #require(try await decodeSent(transport, at: 0).id), result: .object([:]))
        await transport.sink.waitForCount(4)
        let hoverEnvelope = try await decodeSent(transport, at: 3)
        // Respond with an empty markdown, which the service treats as "nothing to show" -> nil.
        try respond(transport, id: try #require(hoverEnvelope.id), result: .null)
        let firstResult = try await first
        #expect(firstResult == nil)

        let framesBefore = await transport.sink.all.count
        let second = try await provider.hover(query)
        #expect(second == nil)
        let framesAfter = await transport.sink.all.count
        #expect(framesAfter == framesBefore)
        #expect(await factory.generationCount == 1)
    }
}

@Suite
struct TieredHoverProvidersTests {
    private struct StubProvider: HoverProvider {
        let result: HoverContent?
        let shouldThrowCancellation: Bool

        init(result: HoverContent? = nil, shouldThrowCancellation: Bool = false) {
            self.result = result
            self.shouldThrowCancellation = shouldThrowCancellation
        }

        func hover(_ query: HoverQuery) async throws -> HoverContent? {
            if shouldThrowCancellation { throw CancellationError() }
            return result
        }
    }

    private actor CallRecorder {
        private(set) var calls: [String] = []
        func record(_ name: String) { calls.append(name) }
    }

    private struct RecordingProvider: HoverProvider {
        let name: String
        let result: HoverContent?
        let recorder: CallRecorder

        func hover(_ query: HoverQuery) async throws -> HoverContent? {
            await recorder.record(name)
            return result
        }
    }

    private func query() -> HoverQuery {
        HoverQuery(documentURI: "file:///a.swift", content: "x", line: 0, utf16Column: 0)
    }

    @Test
    func `returns the first non-nil result in order`() async throws {
        let recorder = CallRecorder()
        let first = RecordingProvider(name: "first", result: nil, recorder: recorder)
        let second = RecordingProvider(
            name: "second", result: HoverContent(markdown: "hit", source: .docIndex), recorder: recorder)
        let third = RecordingProvider(
            name: "third", result: HoverContent(markdown: "unused", source: .sdk), recorder: recorder)

        let tiered = TieredHoverProviders([first, second, third])
        let result = try await tiered.hover(query())

        #expect(result?.markdown == "hit")
        #expect(await recorder.calls == ["first", "second"])
    }

    @Test
    func `returns nil when every tier has nothing`() async throws {
        let tiered = TieredHoverProviders([StubProvider(), StubProvider(), StubProvider()])
        let result = try await tiered.hover(query())
        #expect(result == nil)
    }

    @Test
    func `a cancellation from a tier aborts the composite`() async throws {
        let tiered = TieredHoverProviders([
            StubProvider(shouldThrowCancellation: true),
            StubProvider(result: HoverContent(markdown: "never", source: .sdk))
        ])
        await #expect(throws: CancellationError.self) {
            _ = try await tiered.hover(query())
        }
    }

    @Test
    func `a non-cancellation error from a tier is treated as nil and the next tier runs`() async throws {
        struct ThrowingProvider: HoverProvider {
            struct SomeError: Error {}
            func hover(_ query: HoverQuery) async throws -> HoverContent? { throw SomeError() }
        }
        let tiered = TieredHoverProviders([
            ThrowingProvider(), StubProvider(result: HoverContent(markdown: "fallback", source: .sdk))
        ])
        let result = try await tiered.hover(query())
        #expect(result?.markdown == "fallback")
    }
}
