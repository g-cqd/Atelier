import AemiTestKit
import Foundation
import Synchronization
import Testing

@testable import AtelierGrammar
@testable import AtelierGrammarCorpus

/// How ``SyntaxArtifactsCache`` loads grammars: one at a time, in the order they were asked for.
@Suite
struct SyntaxArtifactsCacheTests {
    @Test
    func `grammar tables load one grammar at a time`() async throws {
        let fixture = try TierFixture()
        defer { fixture.remove() }
        try fixture.writeGrammar(keyword: "bonjour", directory: "other")
        let queued = AsyncEventProbe<String>()
        let firstCompile = AsyncLatch()
        let compiles = Mutex((running: 0, most: 0, count: 0))
        let registry = GrammarRegistry(cacheDirectory: fixture.cacheDirectory) { grammar throws(GrammarError) in
            let isFirst = compiles.withLock { state in
                state.running += 1
                state.most = max(state.most, state.running)
                state.count += 1
                return state.count == 1
            }
            defer { compiles.withLock { $0.running -= 1 } }
            if isFirst {
                do {
                    try await firstCompile.wait()
                } catch {
                    throw .resourceLimitExceeded("cancelled")
                }
            }
            return try ParseTableCompiler.compile(grammar)
        }
        registry.register(GrammarRegistry.LanguageEntry(name: "json", extensions: [".json"], path: "tiny"))
        registry.register(GrammarRegistry.LanguageEntry(name: "python", extensions: [".py"], path: "other"))
        let cache = SyntaxArtifactsCache(
            registry: registry, grammarsDirectory: fixture.grammarsDirectory, onQueued: { queued.record($0) })

        async let json: Void = cache.loadIfNeeded(for: "json")
        async let python: Void = cache.loadIfNeeded(for: "python")
        // The first load waits in its compile until the second queues behind it; loads that ran at once would
        // compile both meanwhile, and none would queue.
        _ = try await queued.wait(forAtLeast: 1)
        firstCompile.open()
        await json
        await python

        #expect(compiles.withLock { $0.most } == 1)
        #expect(compiles.withLock { $0.count } == 2)
        #expect(cache.artifacts(for: "json") != nil)
        #expect(cache.artifacts(for: "python") != nil)
    }

    @Test
    func `a table past the size limit is never kept, and a later cache leaves it on disk undecoded`() async throws {
        let fixture = try TierFixture()
        defer { fixture.remove() }
        let compiles = Counter()
        let limits = SyntaxArtifactsCache.Limits(maxTableBytes: 1, budgetBytes: 1 << 20)
        let first = SyntaxArtifactsCache(
            registry: fixture.registry(counting: compiles), grammarsDirectory: fixture.grammarsDirectory,
            limits: limits)

        #expect(await first.pin("json") == nil)
        #expect(first.isOversized("json"))
        #expect(first.loadedTableBytes == 0)
        #expect(compiles.value == 1)

        let later = SyntaxArtifactsCache(
            registry: fixture.registry(counting: compiles), grammarsDirectory: fixture.grammarsDirectory,
            limits: limits)
        await later.loadIfNeeded(for: "json")

        #expect(later.isOversized("json"))
        #expect(compiles.value == 1)
    }

    @Test
    func `past its budget the cache unloads the least recently used table, never a pinned one`() async throws {
        let fixture = try TierFixture()
        defer { fixture.remove() }
        let languages = ["json": "alpha", "python": "bravo", "ruby": "delta"]
        for (language, keyword) in languages {
            try fixture.writeGrammar(keyword: keyword, directory: language)
        }
        let compiles = Counter()
        let paths = ["json": "json", "python": "python", "ruby": "ruby"]
        // Every table once, to measure one: the three grammars differ only by a keyword of the same length.
        let measuring = SyntaxArtifactsCache(
            registry: fixture.registry(counting: compiles, paths: paths),
            grammarsDirectory: fixture.grammarsDirectory, limits: .init(maxTableBytes: 1 << 20, budgetBytes: 1 << 30))
        for language in languages.keys { await measuring.loadIfNeeded(for: language) }
        let table = measuring.loadedTableBytes / 3
        try #require(table > 0)
        let cache = SyntaxArtifactsCache(
            registry: fixture.registry(counting: compiles, paths: paths),
            grammarsDirectory: fixture.grammarsDirectory,
            limits: .init(maxTableBytes: 1 << 20, budgetBytes: 2 * table + table / 2))

        #expect(await cache.pin("json") != nil)
        await cache.loadIfNeeded(for: "python")
        await cache.loadIfNeeded(for: "ruby")
        #expect(cache.loadedLanguages == ["json", "ruby"])

        cache.unpin("json")
        await cache.loadIfNeeded(for: "python")
        #expect(cache.loadedLanguages == ["ruby", "python"])
        // Every table after the first three loads came from the disk cache.
        #expect(compiles.value == 3)
    }
}
