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
}
