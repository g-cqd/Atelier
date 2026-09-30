import AemiTestKit
import Foundation
import Synchronization
import Testing

@testable import AtelierGrammar
@testable import AtelierGrammarCorpus

/// How the registry keeps compiled tables and failed compiles, keyed by the grammar file's contents, across calls and
/// across registries that share a cache directory, as successive launches do.
@Suite
struct GrammarRegistryCacheTests {
    private static let tooLarge = GrammarError.resourceLimitExceeded("Parser state construction exceeded limit")

    @Test
    func `simultaneous requests share one compilation task`() async throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let callers = AsyncEventProbe<Int>()
        let compiles = AsyncEventProbe<Int>()
        let registry = fixture.registry { grammar throws(GrammarError) in
            compiles.record(1)
            do {
                _ = try await callers.wait(forAtLeast: 16, timeout: .seconds(10))
            } catch {
                throw Self.tooLarge
            }
            return try ParseTableCompiler.compile(grammar)
        }

        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 16 {
                group.addTask {
                    callers.record(1)
                    _ = try await callers.wait(forAtLeast: 16, timeout: .seconds(10))
                    let result = try await registry.compiledResult(
                        for: "tiny", grammarsPath: fixture.grammarsPath)
                    return result.parseTable.stateCount
                }
            }
            for try await stateCount in group {
                #expect(stateCount > 0)
            }
        }

        #expect(compiles.count == 1)
    }

    @Test
    func `a failed compile is not tried again`() async throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let compiles = Mutex(0)
        let registry = fixture.registry { _ throws(GrammarError) in
            compiles.withLock { $0 += 1 }
            throw Self.tooLarge
        }

        await #expect(throws: Self.tooLarge) {
            try await registry.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        }
        await #expect(throws: Self.tooLarge) {
            try await registry.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        }
        #expect(compiles.withLock { $0 } == 1)
    }

    @Test
    func `a failed compile is remembered by the next registry on the same cache`() async throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let failing = fixture.registry { _ throws(GrammarError) in throw Self.tooLarge }
        _ = try? await failing.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        let compiles = Mutex(0)
        let relaunched = fixture.registry { grammar throws(GrammarError) in
            compiles.withLock { $0 += 1 }
            return try ParseTableCompiler.compile(grammar)
        }

        await #expect(throws: Self.tooLarge) {
            try await relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        }
        #expect(compiles.withLock { $0 } == 0)
    }

    @Test
    func `an edited grammar compiles again after a failure`() async throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let failing = fixture.registry { _ throws(GrammarError) in throw Self.tooLarge }
        _ = try? await failing.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        try fixture.writeGrammar(keyword: "world")
        let relaunched = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }

        let compiled = try await relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

        #expect(compiled.parseTable.terminals.contains("\"world\""))
    }

    @Test
    func `tables are cached under the hash of the text they were compiled from`() async throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let first = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }
        _ = try first.grammar(for: "tiny", grammarsPath: fixture.grammarsPath)
        try fixture.writeGrammar(keyword: "world")
        _ = try await first.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        let relaunched = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }

        let compiled = try await relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

        #expect(compiled.parseTable.terminals.contains("\"world\""))
    }

    @Test
    func `a language registered again compiles its new grammar`() async throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let registry = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }
        _ = try await registry.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        try fixture.writeGrammar(keyword: "world", directory: "tiny2")

        registry.register(GrammarRegistry.LanguageEntry(name: "tiny", extensions: [".tiny"], path: "tiny2"))
        let compiled = try await registry.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

        #expect(compiled.parseTable.terminals.contains("\"world\""))
    }

    @Test
    func `cached tables that point outside themselves are compiled again`() async throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let first = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }
        let compiled = try await first.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        var damaged = compiled
        damaged.parseTable.actions[0, 0] = .shift(compiled.parseTable.stateCount)
        try fixture.overwriteCachedTables(with: damaged)
        let compiles = Mutex(0)
        let relaunched = fixture.registry { grammar throws(GrammarError) in
            compiles.withLock { $0 += 1 }
            return try ParseTableCompiler.compile(grammar)
        }

        let reloaded = try await relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

        #expect(reloaded.parseTable == compiled.parseTable)
        #expect(compiles.withLock { $0 } == 1)
    }

    @Test
    func `a cache file is read whole, and a missing, empty or oversized one is not read`() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "table-read-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data((0 ..< 100_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try bytes.write(to: directory.appending(path: "whole"))
        try Data().write(to: directory.appending(path: "empty"))
        // Past the limit, sparse: its size is set, and nothing is written.
        let large = directory.appending(path: "large")
        try Data().write(to: large)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(CompiledTableCache.maximumFileSize + 1))
        try handle.close()

        #expect(CompiledTableCache.contents(of: directory.appending(path: "whole")) == bytes)
        #expect(CompiledTableCache.contents(of: directory.appending(path: "empty")) == nil)
        #expect(CompiledTableCache.contents(of: directory.appending(path: "missing")) == nil)
        #expect(CompiledTableCache.contents(of: large) == nil)
    }

    /// A table file cut short, of another version, whose header miscounts its payload, or that is not a table file.
    static let damagedTableFiles: [String] = ["cut short", "another version", "a miscounted payload", "JSON"]

    @Test(arguments: damagedTableFiles)
    func `a damaged table file is compiled again and replaced`(damage: String) async throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let first = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }
        let compiled = try await first.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        var file = try Data(contentsOf: fixture.cachedTableFileURL())
        switch damage {
            case "cut short": file = file.prefix(file.count / 2)
            case "another version": file[TableFile.versionOffset] &+= 1
            case "a miscounted payload": file[TableFile.lengthOffset] &+= 1
            default: file = try GrammarRegistry.encodeCompiledTables(compiled)
        }
        try fixture.overwriteCachedTableFile(with: file)
        let compiles = Mutex(0)
        let relaunched = fixture.registry { grammar throws(GrammarError) in
            compiles.withLock { $0 += 1 }
            return try ParseTableCompiler.compile(grammar)
        }

        let reloaded = try await relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

        #expect(reloaded.parseTable == compiled.parseTable)
        #expect(compiles.withLock { $0 } == 1)
        #expect(try Data(contentsOf: fixture.cachedTableFileURL()) == compiled.tableFile())
    }

    @Test
    func `compiled tables are read back by the next registry on the same cache`() async throws {
        let fixture = try GrammarFixture()
        defer { fixture.remove() }
        let first = fixture.registry { grammar throws(GrammarError) in try ParseTableCompiler.compile(grammar) }
        let compiled = try await first.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)
        let compiles = Mutex(0)
        let relaunched = fixture.registry { grammar throws(GrammarError) in
            compiles.withLock { $0 += 1 }
            return try ParseTableCompiler.compile(grammar)
        }

        let reloaded = try await relaunched.compiledResult(for: "tiny", grammarsPath: fixture.grammarsPath)

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

    /// Replaces the cached tables of the current `tiny` grammar with `tables`.
    func overwriteCachedTables(with tables: ParseTableCompiler.CompilationResult) throws {
        try overwriteCachedTableFile(with: tables.tableFile())
    }

    /// Replaces the cached table file of the current `tiny` grammar with `contents`.
    func overwriteCachedTableFile(with contents: Data) throws {
        try contents.write(to: cachedTableFileURL())
    }

    /// The cached table file of the current `tiny` grammar.
    func cachedTableFileURL() throws -> URL {
        let grammar = try Data(contentsOf: root.appending(path: "Grammars/tiny/grammar.json"))
        let key = CompiledTableCache.Key(language: "tiny", grammar: grammar)
        return CompiledTableCache(directory: root.appending(path: "cache"), format: .binary)
            .fileURL(for: key, kind: .tables)
    }

    /// A registry that knows `tiny`, caches under the fixture and compiles with `compile`.
    func registry(
        compile:
            @escaping @Sendable (GrammarDefinition) async throws(GrammarError) -> ParseTableCompiler.CompilationResult
    ) -> GrammarRegistry {
        let registry = GrammarRegistry(cacheDirectory: root.appending(path: "cache"), compile: compile)
        registry.register(GrammarRegistry.LanguageEntry(name: "tiny", extensions: [".tiny"], path: "tiny"))
        return registry
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
