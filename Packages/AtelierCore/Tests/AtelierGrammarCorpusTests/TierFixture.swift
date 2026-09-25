import Foundation

@testable import AtelierGrammarCorpus

/// A one-rule grammar that reads `hello`, registered as JSON's under a temporary grammars directory, with a
/// highlight query that colours what it reads as a keyword, and a cache directory of its own.
struct TierFixture {
    let root = FileManager.default.temporaryDirectory.appending(path: "grammar-tier-\(UUID().uuidString)")

    var grammarsDirectory: URL { root.appending(path: "Grammars", directoryHint: .isDirectory) }
    var cacheDirectory: URL { root.appending(path: "cache", directoryHint: .isDirectory) }

    init() throws {
        try writeGrammar(keyword: "hello", directory: "tiny")
    }

    func writeGrammar(keyword: String, directory name: String) throws {
        let directory = grammarsDirectory.appending(path: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let grammar = #"{"name": "\#(name)", "rules": {"source": {"type": "STRING", "value": "\#(keyword)"}}}"#
        try Data(grammar.utf8).write(to: directory.appending(path: "grammar.json"))
        try Data("(source) @keyword\n".utf8).write(to: directory.appending(path: "highlights.scm"))
    }

    /// Artifacts loaded afresh: a new registry reads the grammar file as it is now.
    func artifacts() -> SyntaxArtifactsCache {
        let registry = GrammarRegistry(cacheDirectory: cacheDirectory)
        registry.register(GrammarRegistry.LanguageEntry(name: "json", extensions: [".json"], path: "tiny"))
        return SyntaxArtifactsCache(registry: registry, grammarsDirectory: grammarsDirectory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
