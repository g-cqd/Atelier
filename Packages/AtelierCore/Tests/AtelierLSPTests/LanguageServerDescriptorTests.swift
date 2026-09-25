import AemiTestKit
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
    func `clangd comes from the toolchain and skips background indexing`() {
        let server = LanguageServerDescriptor.clangd
        let configuration = LanguageServerSession.Configuration(
            descriptor: server, serverExecutable: URL(filePath: "/usr/bin/clangd"),
            workspaceRoot: URL(filePath: "/repo", directoryHint: .isDirectory))

        #expect(configuration.serverArguments == ["--background-index=false"])
        #expect(server.rootMarkers == ["compile_commands.json", ".clangd"])
        #expect(
            server.executableQuery(customPath: nil, overridePrefix: "GDV_")
                == ExecutableQuery(names: ["clangd"], overrideVariable: "GDV_CLANGD", searchesToolchain: true))
        #expect(server.runtimeExecutableName == nil)
    }

    @Test
    func `rust-analyzer is found in cargo's directory, rooted at Cargo.toml, and builds nothing`() {
        let server = LanguageServerDescriptor.rustAnalyzer
        let options =
            LanguageServerSession.Configuration(
                descriptor: server, serverExecutable: URL(filePath: "/home/.cargo/bin/rust-analyzer"),
                workspaceRoot: URL(filePath: "/repo", directoryHint: .isDirectory)
            )
            .initializationOptions

        #expect(server.rootMarkers == ["Cargo.toml"])
        #expect(server.homeRelativeDirectories.contains(".cargo/bin"))
        #expect(server.executableQuery(customPath: nil, overridePrefix: "GDV_").overrideVariable == "GDV_RUST_ANALYZER")
        #expect(
            options
                == .object([
                    "cargo": .object(["buildScripts": .object(["enable": .bool(false)])]),
                    "procMacro": .object(["enable": .bool(false)]),
                    "cachePriming": .object(["enable": .bool(false)]), "checkOnSave": .bool(false)
                ]))
    }

    @Test
    func `basedpyright runs over stdio, rooted at pyrightconfig.json before pyproject.toml`() {
        let server = LanguageServerDescriptor.basedPyright
        let configuration = LanguageServerSession.Configuration(
            descriptor: server, serverExecutable: URL(filePath: "/home/.local/bin/basedpyright-langserver"),
            workspaceRoot: URL(filePath: "/repo", directoryHint: .isDirectory))

        #expect(configuration.serverArguments == ["--stdio"])
        #expect(server.executableNames == ["basedpyright-langserver"])
        #expect(server.rootMarkers == ["pyrightconfig.json", "pyproject.toml"])
        #expect(server.homeRelativeDirectories.contains(".local/bin"))
        #expect(server.executableQuery(customPath: nil, overridePrefix: "GDV_").overrideVariable == "GDV_BASEDPYRIGHT")
    }

    @Test
    func `each language hover asks has one server at most`() {
        #expect(LanguageServerDescriptor.serving(.swift) == .sourceKitLSP)
        #expect(LanguageServerDescriptor.serving(.typescript) == .typeScriptLanguageServer)
        #expect(LanguageServerDescriptor.serving(.javascript) == .typeScriptLanguageServer)
        #expect(LanguageServerDescriptor.serving(.go) == .gopls)
        for language in [Language.c, .cpp, .objectiveC] {
            #expect(LanguageServerDescriptor.serving(language) == .clangd)
        }
        #expect(LanguageServerDescriptor.serving(.rust) == .rustAnalyzer)
        #expect(LanguageServerDescriptor.serving(.python) == .basedPyright)
        #expect(LanguageServerDescriptor.serving(.kotlin) == nil)
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
        ("a.JSX", "javascriptreact"), ("a.go", "go"), ("a.swift", "swift"), ("a.sh", "shellscript"), ("a.c", "c"),
        ("a.cpp", "cpp"), ("a.hpp", "cpp"), ("a.m", "objective-c"), ("a.mm", "objective-cpp"), ("a.rs", "rust"),
        ("a.py", "python")
    ])
    func `a document's language ID follows its extension`(name: String, languageID: String) {
        #expect(LanguageServerDescriptor.languageID(forDocumentAt: URL(filePath: "/repo/" + name)) == languageID)
    }

    @Test(arguments: [
        ("", "c"),
        ("#include <stddef.h>\nsize_t count(const char *text);\n", "c"),
        (
            "#ifdef __cplusplus\nextern \"C\" {\n#endif\nint add(int a, int b);\n#ifdef __cplusplus\n}\n#endif\n",
            "c"
        ),
        ("// Wraps std::vector for C callers.\n/*\n class Hidden;\n */\nvoid *make(void);\n", "c"),
        ("#import <Foundation/Foundation.h>\nvoid log(void);\n", "objective-c"),
        ("NS_ASSUME_NONNULL_BEGIN\n@interface Widget : NSObject\n@end\n", "objective-c"),
        ("@import Foundation;\n@protocol Drawing\n@end\n", "objective-c"),
        ("#pragma once\nnamespace geometry {\nstruct Point { int x; };\n}\n", "cpp"),
        ("template <typename T>\nT twice(T value);\n", "cpp"),
        ("class Shape {\npublic:\n  virtual ~Shape();\n};\n", "cpp"),
        ("#include <string>\nstd::string name();\n", "cpp"),
        (
            "#import <Foundation/Foundation.h>\n#include <vector>\nclass Buffer;\n@interface Box : NSObject\n@end\n",
            "objective-cpp"
        )
    ])
    func `a header is sent as the language its content reads as`(content: String, languageID: String) {
        let header = URL(filePath: "/repo/include/header.h")

        #expect(LanguageServerDescriptor.languageID(forDocumentAt: header, content: content) == languageID)
    }

    // MARK: - Runtimes

    /// Writes an executable script at `url`.
    private func writeExecutable(_ script: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    @Test
    func `a native server runs with the app's own environment`() async {
        let environment = await LanguageServerDescriptor.gopls.sessionEnvironment(
            serverExecutable: URL(filePath: "/go/bin/gopls"), locator: RecordingLocator(installed: [:]),
            base: ["PATH": "/usr/bin"])

        #expect(environment == nil)
    }

    @Test
    func `typescript-language-server's PATH starts with the node beside it, else with the one discovery finds`()
        async throws
    {
        let directory = TemporaryDirectory(prefix: "atelier-lsp-runtime")
        defer { directory.cleanup() }
        let root = URL(filePath: directory.path, directoryHint: .isDirectory)
        let server = root.appending(path: "nvm/bin/typescript-language-server")
        try writeExecutable("#!/bin/sh\n", at: server)
        let homebrewNode = root.appending(path: "homebrew/bin/node")
        try writeExecutable("#!/bin/sh\n", at: homebrewNode)
        let locator = RecordingLocator(installed: ["node": homebrewNode])
        let base = ["PATH": "/usr/bin:\(root.path)/homebrew/bin:/bin", "HOME": "/home"]
        let descriptor = LanguageServerDescriptor.typeScriptLanguageServer

        let found = await descriptor.sessionEnvironment(serverExecutable: server, locator: locator, base: base)
        #expect(found?["PATH"] == "\(root.path)/homebrew/bin:/usr/bin:/bin")
        #expect(found?["HOME"] == "/home")
        #expect(await locator.queries.map(\.names) == [["node"]])

        try writeExecutable("#!/bin/sh\n", at: root.appending(path: "nvm/bin/node"))
        let beside = await descriptor.sessionEnvironment(serverExecutable: server, locator: locator, base: base)
        #expect(beside?["PATH"]?.hasPrefix("\(root.path)/nvm/bin:") == true)
        #expect(await locator.queries.count == 1)

        let missing = await descriptor.sessionEnvironment(
            serverExecutable: URL(filePath: "/nowhere/typescript-language-server"),
            locator: RecordingLocator(installed: [:]), base: base)
        #expect(missing == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a server started through env node runs the node its session's PATH finds`() async throws {
        let directory = TemporaryDirectory(prefix: "atelier-lsp-shim")
        defer { directory.cleanup() }
        let root = try #require(LanguageServerRegistry.canonicalRoot(URL(filePath: directory.path)))
        let marker = root.appending(path: "ran")
        // A fake node: records the script it was asked to run and its arguments, then exits.
        let node = root.appending(path: "runtime/node")
        try writeExecutable("#!/bin/sh\necho \"$1 $2\" > '\(marker.path)'\n", at: node)
        let server = root.appending(path: "server/typescript-language-server")
        try writeExecutable("#!/usr/bin/env node\n", at: server)
        let descriptor = LanguageServerDescriptor.typeScriptLanguageServer
        let environment = try #require(
            await descriptor.sessionEnvironment(
                serverExecutable: server, locator: RecordingLocator(installed: ["node": node]),
                base: ["PATH": "/usr/bin:/bin"]))
        let configuration = LanguageServerSession.Configuration(
            descriptor: descriptor, serverExecutable: server, workspaceRoot: root, environment: environment)
        let process = LanguageServerSession.processSession(for: configuration)

        try await process.start()
        let status = await process.waitForExit()

        #expect(status == 0)
        let ran = try String(contentsOf: marker, encoding: .utf8)
        #expect(ran == "\(server.path(percentEncoded: false)) --stdio\n")
    }
}
