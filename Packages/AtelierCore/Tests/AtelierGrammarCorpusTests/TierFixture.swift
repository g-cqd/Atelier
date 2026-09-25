import Foundation
import Synchronization

@testable import AtelierGrammar
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

    /// A registry that knows each language of `paths` in the directory it names, and counts its compiles in
    /// `compiles`.
    func registry(counting compiles: Counter, paths: [String: String] = ["json": "tiny"]) -> GrammarRegistry {
        let registry = GrammarRegistry(cacheDirectory: cacheDirectory) { grammar throws(GrammarError) in
            compiles.increment()
            return try ParseTableCompiler.compile(grammar)
        }
        for (language, path) in paths {
            registry.register(GrammarRegistry.LanguageEntry(name: language, extensions: [".\(language)"], path: path))
        }
        return registry
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

/// A count several tasks add to.
final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func increment() {
        count.withLock { $0 += 1 }
    }
}
