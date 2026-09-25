import AtelierProcess
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierLSP

/// A locator that records the query it was asked and answers from a fixed table of names.
private actor RecordingLocator: ExecutableLocating {
    private let installed: [String: URL]
    private(set) var queries: [ExecutableQuery] = []

    init(installed: [String: URL]) {
        self.installed = installed
    }

    func locateExecutable(_ query: ExecutableQuery) async -> URL? {
        queries.append(query)
        return query.names.compactMap { installed[$0] }.first
    }
}

@Suite
struct LanguageServerDescriptorTests {
    @Test
    func `sourcekit-lsp's descriptor builds the session Swift hovers always had`() {
        let executable = URL(filePath: "/usr/bin/sourcekit-lsp")
        let root = URL(filePath: "/repo", directoryHint: .isDirectory)

        let configuration = LanguageServerSession.Configuration(
            descriptor: .sourceKitLSP, serverExecutable: executable, workspaceRoot: root)

        #expect(configuration.serverExecutable == executable)
        #expect(configuration.serverArguments.isEmpty)
        #expect(configuration.workspaceRoot == root)
        #expect(configuration.initializationOptions == .object(["backgroundIndexing": .bool(false)]))
        #expect(configuration.idleShutdown == .seconds(180))
        #expect(configuration.initializeTimeout == .seconds(2))
        #expect(configuration.requestTimeout == .seconds(2))
        #expect(configuration.maximumRestarts == 2)
        #expect(configuration.openDocumentLimit == 32)
    }

    @Test
    func `typescript-language-server runs over stdio with a longer handshake`() {
        let configuration = LanguageServerSession.Configuration(
            descriptor: .typeScriptLanguageServer, serverExecutable: URL(filePath: "/bin/tsls"),
            workspaceRoot: URL(filePath: "/repo", directoryHint: .isDirectory))

        #expect(configuration.serverArguments == ["--stdio"])
        #expect(configuration.initializeTimeout == .seconds(10))
        #expect(configuration.requestTimeout == .seconds(2))
        #expect(configuration.initializationOptions == nil)
    }

    @Test
    func `each language hover asks has one server at most`() {
        #expect(LanguageServerDescriptor.serving(.swift) == .sourceKitLSP)
        #expect(LanguageServerDescriptor.serving(.typescript) == .typeScriptLanguageServer)
        #expect(LanguageServerDescriptor.serving(.javascript) == .typeScriptLanguageServer)
        #expect(LanguageServerDescriptor.serving(.go) == .gopls)
        #expect(LanguageServerDescriptor.serving(.python) == nil)
        #expect(LanguageServerDescriptor.serving(.go, among: [.sourceKitLSP]) == nil)
        for language in Language.allCases {
            #expect(LanguageServerDescriptor.all.count { $0.languages.contains(language) } <= 1)
        }
        #expect(Set(LanguageServerDescriptor.all.map(\.id)).count == LanguageServerDescriptor.all.count)
    }

    @Test
    func `a descriptor's query carries its override variable, names and install directories`() async {
        let gopls = URL(filePath: "/home/go/bin/gopls")
        let locator = RecordingLocator(installed: ["gopls": gopls])

        let located = await LanguageServerDescriptor.gopls.locate(
            using: locator, customPath: "/custom/gopls", overridePrefix: "GDV_")

        #expect(located == gopls)
        #expect(
            await locator.queries == [
                ExecutableQuery(
                    names: ["gopls"], overrideVariable: "GDV_GOPLS", customPath: "/custom/gopls",
                    searchesToolchain: false, homeRelativeDirectories: [".npm-global/bin", ".cargo/bin", "go/bin"])
            ])
        let sourceKit = LanguageServerDescriptor.sourceKitLSP.executableQuery(customPath: nil, overridePrefix: "GDV_")
        let expected = ExecutableQuery(
            names: ["sourcekit-lsp"], overrideVariable: "GDV_SOURCEKIT_LSP", searchesToolchain: true)
        #expect(sourceKit == expected)
        #expect(
            LanguageServerDescriptor.typeScriptLanguageServer.executableQuery(customPath: nil, overridePrefix: nil)
                .overrideVariable == nil)
    }

    @Test(arguments: [
        ("a.ts", "typescript"), ("a.tsx", "typescriptreact"), ("a.mts", "typescript"), ("a.js", "javascript"),
        ("a.JSX", "javascriptreact"), ("a.go", "go"), ("a.swift", "swift"), ("a.sh", "shellscript")
    ])
    func `a document's language ID follows its extension`(name: String, languageID: String) {
        #expect(LanguageServerDescriptor.languageID(forDocumentAt: URL(filePath: "/repo/" + name)) == languageID)
    }
}
