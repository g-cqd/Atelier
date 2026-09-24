import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser
@testable import KittySyntax

/// How the registry reads a `languages.json` manifest, and how its compiled-table cache stays readable by, and from,
/// Foundation's JSON coders.
@Suite
struct GrammarRegistryJSONTests {
    @Test
    func `a manifest with a byte-order mark registers its entries`() throws {
        let manifest = Data(#"[{"name": "elvish", "extensions": [".elv"], "path": "elvish"}]"#.utf8)
        let registry = GrammarRegistry()

        try registry.loadManifest(from: writeManifest(Data([0xEF, 0xBB, 0xBF]) + manifest))

        #expect(registry.entry(forLanguage: "elvish")?.extensions == [".elv"])
    }

    @Test
    func `manifest entries with a missing, mistyped or unsafe member are skipped`() throws {
        let manifest = #"""
            [
                {"name": "kept", "extensions": [".k"], "path": "kept"},
                {"name": "no-path", "extensions": [".n"]},
                {"name": "mixed", "extensions": [".m", 1], "path": "mixed"},
                {"name": 7, "extensions": [".s"], "path": "seven"},
                {"name": "escape", "extensions": [".e"], "path": "../etc"}
            ]
            """#
        let registry = GrammarRegistry()

        try registry.loadManifest(from: writeManifest(Data(manifest.utf8)))

        #expect(registry.languageNames == ["kept"])
    }

    @Test
    func `a key repeated in a manifest entry keeps its first value`() throws {
        let manifest = #"[{"name": "first", "extensions": [".f"], "path": "first", "name": "second"}]"#
        let registry = GrammarRegistry()

        try registry.loadManifest(from: writeManifest(Data(manifest.utf8)))

        #expect(registry.languageNames == ["first"])
    }

    @Test(arguments: [
        #"{"name": "json", "extensions": [".json"], "path": "json"}"#,
        #"[{"name": "json", "extensions": [".json"], "path": "json"}, 1]"#
    ])
    func `a manifest that is not an array of entries is invalid JSON`(manifest: String) throws {
        let path = try writeManifest(Data(manifest.utf8))

        #expect(throws: GrammarError.invalidJSON("Expected array of language entries")) {
            try GrammarRegistry().loadManifest(from: path)
        }
    }

    @Test
    func `a manifest that is not JSON is invalid JSON and a missing one is not found`() throws {
        let path = try writeManifest(Data("[{".utf8))
        let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path

        let error = #expect(throws: GrammarError.self) { try GrammarRegistry().loadManifest(from: path) }
        #expect(error?.isInvalidJSON == true)
        #expect(throws: GrammarError.fileNotFound(missing)) { try GrammarRegistry().loadManifest(from: missing) }
    }

    @Test
    func `tables Foundation's encoder cached decode to the same tables`() throws {
        let compiled = try compiledJSONGrammar()

        let decoded = try GrammarRegistry.decodeCompiledTables(from: JSONEncoder().encode(compiled))

        #expect(decoded.parseTable == compiled.parseTable)
        #expect(decoded.lexTable == compiled.lexTable)
        #expect(decoded.productions == compiled.productions)
    }

    @Test
    func `tables cached now decode in Foundation's decoder`() throws {
        let compiled = try compiledJSONGrammar()

        let decoded = try JSONDecoder()
            .decode(ParseTableCompiler.CompilationResult.self, from: GrammarRegistry.encodeCompiledTables(compiled))

        #expect(decoded.parseTable == compiled.parseTable)
        #expect(decoded.lexTable == compiled.lexTable)
        #expect(decoded.productions == compiled.productions)
    }

    @Test
    func `bundled JSON parses a nested value without ERROR nodes`() throws {
        let compiled = try compiledJSONGrammar()
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        let tree = try parser.parse(#"{"name":"value","items":[1,true,null]}"#)
        #expect(tree.root.type == "document")
        var pending = [tree.root]
        while let node = pending.popLast() {
            #expect(!node.isError)
            pending.append(contentsOf: node.children)
        }
    }

    @Test
    func `bundled JSON parses without error nodes`() throws {
        let compiled = try compiledJSONGrammar()
        let parser = GrammarParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        let tree = try parser.parse(#"{"name":"value","enabled":true,"count":3}"#)
        var pending = [tree.root]
        var errorCount = 0
        while let node = pending.popLast() {
            if node.isError { errorCount += 1 }
            pending.append(contentsOf: node.children)
        }
        #expect(errorCount == 0)
    }

    private func compiledJSONGrammar() throws -> ParseTableCompiler.CompilationResult {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        return try ParseTableCompiler.compile(GrammarLoader.load(from: "\(resourcePath)/Grammars/json/grammar.json"))
    }

    private func writeManifest(_ contents: Data) throws -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "languages-\(UUID().uuidString).json")
        try contents.write(to: url)
        return url.path
    }
}

extension GrammarError {
    fileprivate var isInvalidJSON: Bool {
        guard case .invalidJSON = self else { return false }
        return true
    }
}
