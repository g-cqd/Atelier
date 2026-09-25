import AemiRuntime
import AemiTestKit
import AtelierHighlighting
import AtelierParser
import AtelierSyntaxModel
import Foundation
import Synchronization
import Testing

@testable import AtelierGrammarCorpus

/// The grammar tier (PERF-11 step 4): its tokens from the core's corpus, its deadline, its failure record, its
/// throughput predictor and its breaker, and table loads one grammar at a time.
@Suite
struct GrammarTierTests {
    /// The lines of `text`, each without its line break.
    private static func lineRanges(of text: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for (offset, byte) in text.utf8.enumerated() where byte == UInt8(ascii: "\n") {
            ranges.append(start ..< offset)
            start = offset + 1
        }
        ranges.append(start ..< text.utf8.count)
        return ranges
    }

    /// A JSON request for `text`, keyed by `content`, with `visibleLines` on screen, all of them by default.
    private static func request(
        _ text: String, content: String = UUID().uuidString, visibleLines: Range<Int>? = nil
    ) -> TierRequest {
        let lines = lineRanges(of: text)
        return TierRequest(
            revision: SourceRevision(documentID: "a.json", language: .json, key: .content(content)), text: text,
            lineRanges: lines, visibleLines: visibleLines ?? 0 ..< lines.count)
    }

    /// Runs `tier` on `request`, answering the updates it emitted.
    private static func run(_ tier: GrammarTier, _ request: TierRequest) async throws -> [TierUpdate] {
        let updates = Mutex<[TierUpdate]>([])
        try await tier.run(request) { update in updates.withLock { $0.append(update) } }
        return updates.withLock { $0 }
    }

    /// The failure `body` threw; nil when it threw none or something else.
    private static func failure(of body: () async throws -> Void) async -> TierFailure? {
        do {
            try await body()
            return nil
        } catch {
            return error as? TierFailure
        }
    }

    @Test
    func `a JSON text takes its grammar's colour from the core's corpus, the visible lines first`() async throws {
        let corpus = try GrammarCorpus.bundled()
        let cache = ScratchDirectory()
        defer { cache.remove() }
        let artifacts = SyntaxArtifactsCache(
            registry: GrammarRegistry(cacheDirectory: cache.url, bundledManifest: try corpus.manifest()),
            grammarsDirectory: corpus.grammarsDirectory)
        let text = "{\n  \"a\": 1,\n  \"b\": true\n}"

        let updates = try await Self.run(
            GrammarTier(artifacts: artifacts), Self.request(text, visibleLines: 1 ..< 2))

        #expect(updates.map(\.lines) == [1 ..< 2, 2 ..< 4, 0 ..< 1])
        #expect(updates.allSatisfy { $0.layer == .structural && $0.coverage == .complete })
        let second = try #require(updates.first?.tokens.first)
        #expect(second.map(\.role).contains(.property))
        #expect(second.map(\.role).contains(.number))
    }

    @Test
    func `a parse past its deadline in CPU time is stopped, and the tier fails by its deadline`() async throws {
        let fixture = try TierFixture()
        defer { fixture.remove() }
        // Each reading of the thread's CPU time finds 100 ms more used.
        let readings = Mutex(0)
        let stopped = Mutex(false)
        let cpuTime: GrammarTier.ThreadCPUTime = {
            let reading = readings.withLock {
                $0 += 1
                return $0
            }
            return .milliseconds(100 * reading)
        }
        let parse: GrammarTier.Parse = { _, _, isCancelled in
            // A parse that never ends by itself, checking as the parser does.
            while !isCancelled() {}
            stopped.withLock { $0 = true }
            throw ParseError.cancelled(atToken: 0)
        }
        let tier = GrammarTier(
            artifacts: fixture.artifacts(), record: GrammarTierRecord(), deadline: .milliseconds(250), pool: nil,
            cpuTime: cpuTime, parse: parse)

        let failure = await Self.failure { _ = try await Self.run(tier, Self.request("hello")) }

        #expect(failure == .deadline(.milliseconds(250)))
        #expect(stopped.withLock { $0 })
        #expect(readings.withLock { $0 } == 4)
    }

    @Test
    func `with a pool, the parse runs on the pool's threads`() async throws {
        let fixture = try TierFixture()
        defer { fixture.remove() }
        let pool = BlockingOffloadPool(width: 1, qualityOfService: .utility)
        defer { pool.shutdown() }
        let threadName = Mutex("")
        let tier = GrammarTier(
            artifacts: fixture.artifacts(), record: GrammarTierRecord(), deadline: .milliseconds(250), pool: pool,
            cpuTime: GrammarTier.threadCPUTime
        ) { engine, text, isCancelled in
            var name = [CChar](repeating: 0, count: 64)
            pthread_getname_np(pthread_self(), &name, name.count)
            threadName.withLock {
                $0 = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
            return try engine.parse(text, externalScanner: nil, isCancelled: isCancelled)
        }

        #expect(try await Self.run(tier, Self.request("hello")).count == 1)
        #expect(threadName.withLock { $0 }.hasPrefix("BlockingOffloadPool"))
    }

    @Test
    func `a text that fails the gate is recorded, and the same content is not parsed again`() async throws {
        let fixture = try TierFixture()
        defer { fixture.remove() }
        let record = GrammarTierRecord()
        let tier = GrammarTier(artifacts: fixture.artifacts(), record: record)
        let broken = Self.request("goodbye", content: "blob-1")

        let first = await Self.failure { _ = try await Self.run(tier, broken) }
        let again = await Self.failure { _ = try await Self.run(tier, broken) }

        guard case .gate = first else {
            Issue.record("expected a gate failure, got \(String(describing: first))")
            return
        }
        #expect(again == first)
        #expect(record.parsesStarted == 1)
        #expect(try await Self.run(tier, Self.request("hello", content: "blob-2")).count == 1)
        #expect(record.parsesStarted == 2)
    }

    @Test
    func `a text its grammar's throughput predicts past the deadline starts no parse`() async throws {
        let fixture = try TierFixture()
        defer { fixture.remove() }
        let artifacts = fixture.artifacts()
        let record = GrammarTierRecord()
        let parses = Mutex(0)
        let tier = GrammarTier(
            artifacts: artifacts, record: record, deadline: .milliseconds(250), pool: nil,
            cpuTime: GrammarTier.threadCPUTime
        ) { engine, text, isCancelled in
            parses.withLock { $0 += 1 }
            return try engine.parse(text, externalScanner: nil, isCancelled: isCancelled)
        }
        // The first text of a grammar always parses; this one says the grammar reads 1 KB in a second.
        _ = try await Self.run(tier, Self.request("hello"))
        let grammar = try #require(artifacts.artifacts(for: "json")?.grammarKey)
        record.observe(grammar: grammar, bytes: 1024, elapsed: .seconds(1))
        #expect(record.predictedDuration(grammar: grammar, bytes: 1024) == .seconds(1))

        await #expect(throws: TierFailure.self) {
            try await Self.run(tier, Self.request(String(repeating: "hello ", count: 100)))
        }

        #expect(parses.withLock { $0 } == 1)
    }

    @Test
    func `three failures in a row stop the grammar until its hash changes`() async throws {
        let fixture = try TierFixture()
        defer { fixture.remove() }
        let record = GrammarTierRecord()
        let tier = GrammarTier(artifacts: fixture.artifacts(), record: record)
        for broken in ["goodbye", "farewell", "adieu"] {
            await #expect(throws: TierFailure.self) { try await Self.run(tier, Self.request(broken)) }
        }

        await #expect(throws: TierFailure.failed("the grammar stopped after 3 failures in a row")) {
            try await Self.run(tier, Self.request("hello"))
        }
        #expect(record.parsesStarted == 3)

        try fixture.writeGrammar(keyword: "howdy", directory: "tiny")
        let edited = GrammarTier(artifacts: fixture.artifacts(), record: record)
        #expect(try await Self.run(edited, Self.request("howdy")).count == 1)
        #expect(record.parsesStarted == 4)
    }
}

/// An empty directory under the temporary directory.
private struct ScratchDirectory {
    let url = FileManager.default.temporaryDirectory.appending(path: "grammar-tier-cache-\(UUID().uuidString)")

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
