import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierGrammarCorpus

/// The bundled corpus: found without trapping, complete, and keyed on disk by what its tables depend on.
@Suite
struct GrammarCorpusTests {
    /// The languages `languages.json` names, in its order.
    static let bundledLanguages = [
        "json", "swift", "javascript", "typescript", "python", "rust", "go", "c", "cpp", "html", "css", "bash", "ruby",
        "java", "kotlin", "lua", "toml", "yaml", "markdown"
    ]

    @Test
    func `the bundled manifest names every bundled language and the corpus holds no other`() throws {
        let corpus = try GrammarCorpus.bundled()
        let directories = try FileManager.default.contentsOfDirectory(atPath: corpus.grammarsDirectory.path)
            .filter { $0 != "languages.json" }

        #expect(try corpus.manifest().entries.map(\.name) == Self.bundledLanguages)
        #expect(directories.sorted() == Self.bundledLanguages.sorted())
    }

    @Test(arguments: bundledLanguages)
    func `every bundled grammar loads from the corpus`(language: String) throws {
        let corpus = try GrammarCorpus.bundled()
        let manifest = try corpus.manifest()
        let registry = GrammarRegistry(
            cacheDirectory: FileManager.default.temporaryDirectory.appending(
                path: "grammar-corpus-\(UUID().uuidString)"),
            bundledManifest: manifest)
        let entry = try #require(manifest.entry(forLanguage: language))

        let grammar = try registry.grammar(for: language, grammarsPath: corpus.grammarsDirectory.path)

        #expect(!grammar.rules.isEmpty)
        #expect(FileManager.default.fileExists(atPath: corpus.highlightsURL(for: entry).path))
    }

    @Test
    func `a changed grammar file changes its cache key`() throws {
        let grammar = try Data(
            contentsOf: GrammarCorpus.bundled().grammarsDirectory.appending(path: "json/grammar.json"))
        var edited = grammar
        edited.append(contentsOf: Array("\n".utf8))

        let key = CompiledTableCache.Key(language: "json", grammar: grammar)

        #expect(CompiledTableCache.Key(language: "json", grammar: grammar) == key)
        #expect(CompiledTableCache.Key(language: "json", grammar: edited) != key)
        #expect(CompiledTableCache.Key(language: "yaml", grammar: grammar) != key)
        #expect(key.fileStem.hasPrefix("json-"))
        #expect(key.fileStem.hasSuffix("-v\(ParseTableCompiler.formatVersion)"))
    }

    @Test
    func `a missing corpus bundle is an error that names the directories searched`() throws {
        let directories = try [ScratchDirectory(), ScratchDirectory()]
        defer { directories.forEach { $0.remove() } }
        let searched = directories.map(\.url)

        #expect(throws: GrammarCorpusError.bundleNotFound(searched: searched.map(\.path))) {
            try GrammarCorpus.bundled(searching: searched)
        }
    }

    @Test
    func `a corpus bundle without its manifest is not found`() throws {
        let directory = try ScratchDirectory()
        defer { directory.remove() }
        try FileManager.default.createDirectory(
            at: directory.url.appending(path: "\(GrammarCorpus.bundleName)/Contents/Resources/Grammars/json"),
            withIntermediateDirectories: true)

        #expect(throws: GrammarCorpusError.bundleNotFound(searched: [directory.url.path])) {
            try GrammarCorpus.bundled(searching: [directory.url])
        }
    }

    @Test(arguments: ["Contents/Resources/", ""])
    func `the corpus bundle is found in the first directory that holds it`(resources: String) throws {
        let empty = try ScratchDirectory()
        let holding = try ScratchDirectory()
        defer {
            empty.remove()
            holding.remove()
        }
        let grammars = holding.url.appending(path: "\(GrammarCorpus.bundleName)/\(resources)Grammars")
        try FileManager.default.createDirectory(at: grammars, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: grammars.appending(path: "languages.json"))

        let corpus = try GrammarCorpus.bundled(searching: [empty.url, holding.url])

        #expect(corpus.grammarsDirectory.standardizedFileURL.path == grammars.standardizedFileURL.path)
        #expect(try corpus.manifest() == .empty)
    }

    @Test
    func `without a corpus no language loads its artifacts`() async {
        let manifest = GrammarManifest(entries: [.init(name: "json", extensions: [".json"], path: "json")])
        let cache = SyntaxArtifactsCache(
            registry: GrammarRegistry(
                cacheDirectory: FileManager.default.temporaryDirectory.appending(path: "grammar-corpus-none"),
                bundledManifest: manifest),
            grammarsDirectory: nil)

        await cache.loadIfNeeded(for: "json")

        #expect(cache.artifacts(for: "json") == nil)
    }
}

/// An empty directory under the temporary directory.
private struct ScratchDirectory {
    let url = FileManager.default.temporaryDirectory.appending(path: "grammar-corpus-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
