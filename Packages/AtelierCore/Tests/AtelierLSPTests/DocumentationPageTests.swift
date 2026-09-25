import AemiTestKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierLSP

/// HOVER-20 criterion 5: a system symbol's hover carries its page in Apple's developer documentation, filed under the
/// module of the type its chain starts with, then its nesting types, then its name with its labels.
struct DocumentationChainTests {
    @Test
    func `the chain runs from its first type to the hovered name`() throws {
        let content = "let _ = String.Encoding.utf8"
        let onMember = try #require(DocumentationChain(content: content, line: 0, utf16Column: 25))
        #expect(onMember.segments == ["String", "Encoding", "utf8"])
        #expect(onMember.rootColumn == 8)

        let onType = try #require(DocumentationChain(content: content, line: 0, utf16Column: 16))
        #expect(onType.segments == ["String", "Encoding"])
    }

    @Test
    func `a page is filed under the module, the nesting types, then the symbol's name with its labels`() throws {
        let chain = try #require(
            DocumentationChain(content: "FileManager.default.contents", line: 0, utf16Column: 12))
        #expect(
            chain.page(module: "Foundation", symbolName: "default")
                == HoverContent.DocumentationPage(module: "Foundation", path: ["FileManager", "default"]))

        let method = try #require(
            DocumentationChain(content: "  FileManager.contents(atPath: p)", line: 0, utf16Column: 16))
        #expect(
            method.page(module: "Foundation", symbolName: "contents(atPath:)")
                == HoverContent.DocumentationPage(module: "Foundation", path: ["FileManager", "contents(atPath:)"]))
    }

    @Test
    func `a member reached through a value has no page`() throws {
        let chain = try #require(DocumentationChain(content: "let p = url.path", line: 0, utf16Column: 13))
        #expect(chain.page(module: "Foundation", symbolName: "path") == nil)
    }

    @Test
    func `a chain that names the module first files its page under it`() throws {
        let chain = try #require(DocumentationChain(content: "Foundation.FileManager", line: 0, utf16Column: 12))
        #expect(chain.startsWith(module: "Foundation"))
        #expect(
            chain.page(module: "Foundation", symbolName: "FileManager")
                == HoverContent.DocumentationPage(module: "Foundation", path: ["FileManager"]))
    }

    @Test
    func `no name at the position is no chain`() {
        #expect(DocumentationChain(content: "let x = (1)", line: 0, utf16Column: 8) == nil)
        #expect(DocumentationChain(content: "a", line: 3, utf16Column: 0) == nil)
    }
}

private func respond(_ transport: PipeTransport, id: JSONRPCID, result: JSONValue) throws {
    transport.deliver(LSPFrameCodec.frame(try JSONRPCMessage.response(id: id, result: result)))
}

private struct SentRequest: Decodable {
    struct Params: Decodable {
        let position: Position?
    }

    let id: JSONRPCID?
    let method: String
    let params: Params?
}

private func sent(_ transport: PipeTransport, at index: Int) async throws -> SentRequest {
    let frames = await transport.sink.all
    return try JSONDecoder().decode(SentRequest.self, from: unframe(frames[index]))
}

private func symbol(_ name: String, module: String?) -> JSONValue {
    var fields: [String: JSONValue] = ["name": .string(name), "kind": .number(7)]
    if let module { fields["systemModule"] = .object(["moduleName": .string(module)]) }
    return .array([.object(fields)])
}

private let hoverAnswer: JSONValue = .object([
    "contents": .object(["kind": .string("markdown"), "value": .string("```swift\nstruct Bool\n```\n\nA value.")])
])

private func makeService(_ factory: ScriptedConnectionFactory) -> LanguageServerSession {
    let configuration = LanguageServerSession.Configuration(
        serverExecutable: URL(fileURLWithPath: "/usr/bin/true"), workspaceRoot: URL(fileURLWithPath: "/tmp"))
    return LanguageServerSession(configuration: configuration, clock: TestClock()) { _ in await factory.make() }
}

@Suite
struct LanguageServerSessionDocumentationPageTests {
    @Test
    func `a member's page is filed under the module of its chain's first type`() async throws {
        let factory = ScriptedConnectionFactory(answering: ["initialize": .object([:]), "shutdown": .null])
        let service = makeService(factory)

        async let page = service.documentationPage(
            uri: "file:///a.swift", languageID: "swift", content: "let _ = String.Encoding.utf8", line: 0,
            utf16Column: 25)

        await factory.waitForGeneration(1)
        let transport = await factory.transport(at: 0)
        await transport.sink.waitForCount(4)
        let onSymbol = try await sent(transport, at: 3)
        #expect(onSymbol.method == "textDocument/symbolInfo")
        #expect(onSymbol.params?.position == Position(line: 0, character: 25))
        // Foundation declares `String.Encoding.utf8`; the documentation files it under String's module.
        try respond(transport, id: try #require(onSymbol.id), result: symbol("utf8", module: "Foundation"))
        await transport.sink.waitForCount(5)
        let onRoot = try await sent(transport, at: 4)
        #expect(onRoot.method == "textDocument/symbolInfo")
        #expect(onRoot.params?.position == Position(line: 0, character: 8))
        try respond(transport, id: try #require(onRoot.id), result: symbol("String", module: "Swift"))

        #expect(await page == HoverContent.DocumentationPage(module: "Swift", path: ["String", "Encoding", "utf8"]))
        await service.shutdown()
    }

    @Test
    func `a symbol with sources has no page, and its chain's first type is not asked about`() async throws {
        let factory = ScriptedConnectionFactory(answering: [
            "initialize": .object([:]), "textDocument/symbolInfo": symbol("load(from:)", module: nil),
            "shutdown": .null
        ])
        let service = makeService(factory)

        let page = await service.documentationPage(
            uri: "file:///a.swift", languageID: "swift", content: "Config.load(from: url)", line: 0, utf16Column: 8)

        #expect(page == nil)
        let frames = await factory.transport(at: 0).sink.all
        let methods = try frames.map { try JSONDecoder().decode(SentRequest.self, from: unframe($0)).method }
        #expect(methods.filter { $0 == "textDocument/symbolInfo" }.count == 1)
        await service.shutdown()
    }

    @Test
    func `the language server tier's answer carries the page when asked to`() async throws {
        let factory = ScriptedConnectionFactory(answering: [
            "initialize": .object([:]), "textDocument/hover": hoverAnswer,
            "textDocument/symbolInfo": symbol("Bool", module: "Swift"), "shutdown": .null
        ])
        let service = makeService(factory)
        let query = HoverQuery(documentURI: "file:///a.swift", content: "let b: Bool", line: 0, utf16Column: 8)

        let plain = try await LanguageServerHoverProvider(session: service).hover(query)
        let paged = try await LanguageServerHoverProvider(session: service, resolvesDocumentationPages: true)
            .hover(query)

        #expect(plain?.documentationPage == nil)
        #expect(paged?.documentationPage == HoverContent.DocumentationPage(module: "Swift", path: ["Bool"]))
        await service.shutdown()
    }

    @Test
    func `the SDK tier's answer carries its probe's page when asked to`() async throws {
        let factory = ScriptedConnectionFactory(answering: [
            "initialize": .object([:]), "textDocument/hover": hoverAnswer,
            "textDocument/symbolInfo": symbol("Bool", module: "Swift"), "shutdown": .null
        ])
        let service = makeService(factory)
        let provider = SDKDocumentationProvider(service: service, resolvesDocumentationPages: true)

        let content = try await provider.hover(
            HoverQuery(documentURI: "file:///a.swift", content: "let b: Bool = true", line: 0, utf16Column: 8))

        #expect(content?.source == .sdk)
        #expect(content?.documentationPage == HoverContent.DocumentationPage(module: "Swift", path: ["Bool"]))
        await provider.shutdown()
    }

    @Test
    func `a tier's prose behind another's declaration keeps whichever page either had`() async throws {
        struct Stub: HoverProvider {
            let content: HoverContent
            func hover(_ query: HoverQuery) async throws -> HoverContent? { content }
        }
        let page = HoverContent.DocumentationPage(module: "Swift", path: ["Bool"])
        let tiered = TieredHoverProviders([
            Stub(
                content: HoverContent(
                    markdown: "```swift\nstruct Bool\n```\n", source: .languageServer, documentationPage: page)),
            Stub(content: HoverContent(markdown: "A value type.", source: .docIndex))
        ])

        let content = try await tiered.hover(
            HoverQuery(documentURI: "file:///a.swift", content: "Bool", line: 0, utf16Column: 0))

        #expect(content?.source == .docIndex)
        #expect(content?.documentationPage == page)
    }
}
