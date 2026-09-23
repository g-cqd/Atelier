import Foundation
import Synchronization
import Testing

@testable import AtelierGrammar
@testable import KittySyntax

/// How the registry keeps compiled tables and failed compiles, keyed by the grammar file's contents, across calls and
/// across registries that share a cache directory, as successive launches do.
@Suite
struct GrammarRegistryCacheTests {
    private static let tooLarge = GrammarError.resourceLimitExceeded("Parser state construction exceeded limit")

    @Test
    func `a failed compile is not tried again`() throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let compiles = Mutex(0)
        let registry = fixture.registry { _ throws(GrammarError) in
            compiles.withLock { $0 += 1 }
            throw Self.tooLarge
        }

        #expect(throws: Self.tooLarge) { try registry.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath) }
        #expect(throws: Self.tooLarge) { try registry.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath) }
        #expect(compiles.withLock { $0 } == 1)
    }

    @Test
    func `a failed compile is remembered by the next registry on the same cache`() throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let failing = fixture.registry { _ throws(GrammarError) in throw Self.tooLarge }
        _ = try? failing.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        let compiles = Mutex(0)
        let relaunched = fixture.registry { grammar throws(GrammarError) in
            compiles.withLock { $0 += 1 }
            return try ParseTableCompiler.compile(grammar)
        }

        #expect(throws: Self.tooLarge) {
            try relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        }
        #expect(compiles.withLock { $0 } == 0)
    }

    @Test
    func `an edited grammar compiles again after a failure`() throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let failing = fixture.registry { _ throws(GrammarError) in throw Self.tooLarge }
        _ = try? failing.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        try fixture.writeGrammar(keyword: "world")
        let relaunched = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }

        let compiled = try relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

        #expect(compiled.parseTable.terminals.contains("\"world\""))
    }

    @Test
    func `tables are cached under the hash of the text they were compiled from`() throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let first = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }
        _ = try first.grammar(for: "tiny", grammarsPath: fixture.grammarsPath)
        try fixture.writeGrammar(keyword: "world")
        _ = try first.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        let relaunched = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }

        let compiled = try relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

        #expect(compiled.parseTable.terminals.contains("\"world\""))
    }

    @Test
    func `a language registered again compiles its new grammar`() throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let registry = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }
        _ = try registry.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        try fixture.writeGrammar(keyword: "world", directory: "tiny2")

        registry.register(GrammarRegistry.LanguageEntry(name: "tiny", extensions: [".tiny"], path: "tiny2"))
        let compiled = try registry.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

        #expect(compiled.parseTable.terminals.contains("\"world\""))
    }

    @Test
    func `compiled tables are read back by the next registry on the same cache`() throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let first = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }
        let compiled = try first.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        let compiles = Mutex(0)
        let relaunched = fixture.registry { grammar throws(GrammarError) in
            compiles.withLock { $0 += 1 }
            return try ParseTableCompiler.compile(grammar)
        }

        let reloaded = try relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

        #expect(reloaded.parseTable == compiled.parseTable)
        #expect(compiles.withLock { $0 } == 0)
    }
}

/// A one-rule grammar, `tiny`, under a temporary grammars directory, and a cache directory of its own.
private struct GrammarFixture {
    let root: URL

    var grammarsPath: String { root.appending(path: "Grammars").path }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "grammar-cache-\(UUID().uuidString)")
        try writeGrammar(keyword: "hello")
    }

    func writeGrammar(keyword: String, directory name: String = "tiny") throws {
        let directory = root.appending(path: "Grammars/\(name)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let grammar = #"{"name": "tiny", "rules": {"source": {"type": "STRING", "value": "\#(keyword)"}}}"#
        try Data(grammar.utf8).write(to: directory.appending(path: "grammar.json"))
    }

    /// A registry that knows `tiny`, caches under the fixture and compiles with `compile`.
    func registry(
        compile: @escaping @Sendable (GrammarDefinition) throws(GrammarError) -> ParseTableCompiler.CompilationResult
    ) -> GrammarRegistry {
        let registry = GrammarRegistry(cacheDirectory: root.appending(path: "cache"), compile: compile)
        registry.register(GrammarRegistry.LanguageEntry(name: "tiny", extensions: [".tiny"], path: "tiny"))
        return registry
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
