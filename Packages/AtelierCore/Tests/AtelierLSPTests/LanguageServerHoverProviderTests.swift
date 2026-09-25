import AemiTestKit
import AtelierSyntaxModel
import Foundation
import Synchronization
import Testing

@testable import AtelierLSP

/// A sent frame's method, and a `didOpen`'s document when it is one.
private struct SentFrame: Decodable {
    struct Params: Decodable {
        let textDocument: TextDocumentItem
    }

    private enum CodingKeys: String, CodingKey {
        case method
        case params
    }

    let method: String?
    let params: Params?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        // Only `didOpen` sends a whole document; every other frame's parameters read as none.
        params = try? container.decode(Params.self, forKey: .params)
    }
}

/// A registry over scripted servers that answer every request at once, recording which server each session is for
/// and the root it runs at.
private final class ScriptedServers: Sendable {
    struct Configured: Sendable {
        let server: String
        let root: URL
    }

    let factory: ScriptedConnectionFactory
    private let configured = Mutex<[Configured]>([])

    init(hover: String) {
        factory = ScriptedConnectionFactory(answering: [
            "initialize": .object([:]), "shutdown": .null,
            "textDocument/hover": .object([
                "contents": .object(["kind": .string("markdown"), "value": .string(hover)])
            ]),
            "textDocument/symbolInfo": .array([
                .object(["name": .string("Bool"), "systemModule": .object(["moduleName": .string("Swift")])])
            ])
        ])
    }

    var sessions: [Configured] { configured.withLock { $0 } }

    func registry() -> LanguageServerRegistry {
        let factory = factory
        return LanguageServerRegistry(
            admits: { _, _ in true },
            makeConfiguration: { root, server in
                self.configured.withLock { $0.append(Configured(server: server.id, root: root)) }
                return LanguageServerSession.Configuration(
                    descriptor: server, serverExecutable: URL(filePath: "/usr/bin/false"), workspaceRoot: root)
            },
            makeSession: { configuration in
                LanguageServerSession(configuration: configuration, clock: TestClock()) { _ in await factory.make() }
            })
    }

    /// Every frame the first server was sent, decoded.
    func sentFrames() async throws -> [SentFrame] {
        try await factory.transport(at: 0).sink.all.map { try JSONDecoder().decode(SentFrame.self, from: unframe($0)) }
    }
}

@Suite
struct LanguageServerHoverProviderTests {
    /// A scratch workspace holding `files`, empty, and its canonical root.
    private func workspace(_ files: [String]) throws -> (TemporaryDirectory, URL) {
        let directory = TemporaryDirectory(prefix: "atelier-lsp-hover")
        let root = try #require(LanguageServerRegistry.canonicalRoot(URL(filePath: directory.path)))
        for file in files {
            let url = root.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        return (directory, root)
    }

    @Test
    func `a document goes to its language's server at its root, with its language ID`() async throws {
        let (directory, root) = try workspace(["web/tsconfig.json", "web/src/App.tsx"])
        defer { directory.cleanup() }
        let servers = ScriptedServers(hover: "```typescript\nfunction App(): Element\n```")
        let registry = servers.registry()
        let provider = LanguageServerHoverProvider(registry: registry, workspaceRoot: root)
        let uri = root.appending(path: "web/src/App.tsx").absoluteString

        let content = try await provider.hover(
            HoverQuery(documentURI: uri, content: "export function App() {}", line: 0, utf16Column: 17))

        #expect(content?.markdown == "```typescript\nfunction App(): Element\n```")
        #expect(content?.source == .languageServer)
        #expect(content?.documentationPage == nil)
        #expect(servers.sessions.map(\.server) == ["typescript-language-server"])
        #expect(servers.sessions.first?.root == root.appending(path: "web", directoryHint: .isDirectory))
        let opened = try await servers.sentFrames().first { $0.method == "textDocument/didOpen" }
        #expect(opened?.params?.textDocument.languageId == "typescriptreact")
        #expect(opened?.params?.textDocument.uri == uri)
        await registry.shutdownAll()
    }

    @Test
    func `a Swift document goes to sourcekit-lsp as swift, and its answer carries its page`() async throws {
        let (directory, root) = try workspace(["Package.swift", "Sources/A.swift"])
        defer { directory.cleanup() }
        let servers = ScriptedServers(hover: "```swift\nstruct Bool\n```\n\nA value type.")
        let registry = servers.registry()
        let provider = LanguageServerHoverProvider(registry: registry, servers: [.sourceKitLSP], workspaceRoot: root)

        let content = try await provider.hover(
            HoverQuery(
                documentURI: root.appending(path: "Sources/A.swift").absoluteString, content: "let b: Bool", line: 0,
                utf16Column: 8))

        #expect(content?.documentationPage == HoverContent.DocumentationPage(module: "Swift", path: ["Bool"]))
        #expect(servers.sessions.map(\.server) == ["sourcekit-lsp"])
        #expect(servers.sessions.first?.root == root)
        let opened = try await servers.sentFrames().first { $0.method == "textDocument/didOpen" }
        #expect(opened?.params?.textDocument.languageId == "swift")
        await registry.shutdownAll()
    }

    /// Hovers the document at `path` under `root` through a provider over every server, and answers the server and
    /// root of the one session it started, with the language ID its document was opened with.
    private func hoverOnce(
        _ path: String, content: String, in root: URL
    ) async throws -> (server: String?, root: URL?, languageID: String?) {
        let servers = ScriptedServers(hover: "`x`")
        let registry = servers.registry()
        let provider = LanguageServerHoverProvider(registry: registry, workspaceRoot: root)

        let answer = try await provider.hover(
            HoverQuery(
                documentURI: root.appending(path: path).absoluteString, content: content, line: 0, utf16Column: 0))

        #expect(answer?.markdown == "`x`")
        let opened = try await servers.sentFrames().first { $0.method == "textDocument/didOpen" }
        await registry.shutdownAll()
        #expect(servers.sessions.count == 1)
        return (servers.sessions.first?.server, servers.sessions.first?.root, opened?.params?.textDocument.languageId)
    }

    @Test
    func `a header goes to clangd as its content's language, at the repository without a compilation database`()
        async throws
    {
        let (directory, root) = try workspace(["include/Widget.h"])
        defer { directory.cleanup() }

        let opened = try await hoverOnce(
            "include/Widget.h", content: "#import <Foundation/Foundation.h>\n@interface Widget : NSObject\n@end",
            in: root)

        #expect(opened.server == "clangd")
        #expect(opened.root == root)
        #expect(opened.languageID == "objective-c")
    }

    @Test
    func `a C++ file goes to clangd at its compilation database's directory`() async throws {
        let (directory, root) = try workspace(["native/compile_commands.json", "native/src/shape.cpp"])
        defer { directory.cleanup() }

        let opened = try await hoverOnce("native/src/shape.cpp", content: "class Shape {};", in: root)

        #expect(opened.server == "clangd")
        #expect(opened.root == root.appending(path: "native", directoryHint: .isDirectory))
        #expect(opened.languageID == "cpp")
    }

    @Test
    func `a Rust file goes to rust-analyzer at its crate`() async throws {
        let (directory, root) = try workspace(["crates/core/Cargo.toml", "crates/core/src/lib.rs"])
        defer { directory.cleanup() }

        let opened = try await hoverOnce("crates/core/src/lib.rs", content: "pub fn run() {}", in: root)

        #expect(opened.server == "rust-analyzer")
        #expect(opened.root == root.appending(path: "crates/core", directoryHint: .isDirectory))
        #expect(opened.languageID == "rust")
    }

    @Test
    func `a Python file goes to basedpyright at its pyrightconfig.json over a nearer pyproject.toml`() async throws {
        let (directory, root) = try workspace(["pyrightconfig.json", "tools/pyproject.toml", "tools/lint/run.py"])
        defer { directory.cleanup() }

        let opened = try await hoverOnce("tools/lint/run.py", content: "def run(): pass", in: root)

        #expect(opened.server == "basedpyright")
        #expect(opened.root == root)
        #expect(opened.languageID == "python")
    }

    @Test
    func `a blob, or a language none of its servers serves, starts no server`() async throws {
        let (directory, root) = try workspace(["main.go", "tool.py"])
        defer { directory.cleanup() }
        let servers = ScriptedServers(hover: "x")
        let provider = LanguageServerHoverProvider(
            registry: servers.registry(), servers: [.sourceKitLSP, .typeScriptLanguageServer], workspaceRoot: root)

        for uri in [
            "atelier-blob://abc123/main.ts", root.appending(path: "main.go").absoluteString,
            root.appending(path: "tool.py").absoluteString
        ] {
            let query = HoverQuery(documentURI: uri, content: "x", line: 0, utf16Column: 0)
            #expect(try await provider.hover(query) == nil)
        }
        #expect(servers.sessions.isEmpty)
        #expect(await servers.factory.generationCount == 0)
    }
}
