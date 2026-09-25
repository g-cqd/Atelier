import AemiTestKit
import AtelierGrammar
import AtelierGrammarCorpus
import AtelierQuery
import Foundation
import KittyCodecs
import Testing

@testable import KittySyntax

/// Stress tests guarding the parse, highlight and tree-drop path against per-call accumulation. Only the check of what
/// bash's load reads before its table runs by default; the whole load is opt-in through `GDV_BENCH`, and the
/// allocation and RSS measurements through `ATELIER_BENCH`.
@Suite
@MainActor
struct MemoryLeakRegressionTests {
    /// The process's resident-memory footprint in bytes, for the opt-in drift print; 0 when unavailable.
    private func residentBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint)
    }

    private let bashScript = """
        #!/usr/bin/env bash
        set -euo pipefail
        for i in 1 2 3 4 5; do
            echo "step $i"
            if [[ "$i" -eq 3 ]]; then
                continue
            fi
            ls -la "$HOME" | head -5
        done
        function greet() { echo "hello, $1"; }
        greet world
        """

    /// What loading bash's artifacts reads before its parse table: the manifest's entry, the grammar, whose external
    /// tokens need the scanner registered for it, and the highlight query. The table is the next test's.
    @Test
    func `bash grammar, scanner and highlight query load`() throws {
        let entry = try #require(BundledLanguageManifest.entry(forLanguage: "bash"))
        let corpus = try #require(KittySyntaxResources.corpus)
        let grammar = try GrammarRegistry.shared.grammar(for: entry.name, grammarsPath: corpus.grammarsDirectory.path)
        #expect(!grammar.externals.isEmpty)
        #expect(GrammarRegistry.shared.scannerType(forGrammar: grammar.name) != nil, "bash has no external scanner")
        let queryURL = corpus.highlightsURL(for: entry)
        _ = try QueryParser.parse(String(contentsOf: queryURL, encoding: .utf8))
    }

    /// The whole load, parse table included: 47 MB decoded from the compiled-table cache, or compiled when the cache
    /// is cold, which takes 3 s of a debug build alone and 12 s under a full run's load. Opt-in: `GDV_BENCH=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `bash grammar artifacts load successfully`() async {
        // A runaway bash compile would hang this test outright, so it needs no time bound.
        let loaded = await LanguageHighlighter.ensureArtifacts(for: "bash")
        #expect(loaded == true, "bash artifacts failed to load")
    }

    /// Repeated loads must hit the cache. They run on a detached task, out of `mallocDelta`'s reach, so this only
    /// prints the RSS drift and is opt-in: `ATELIER_BENCH=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_BENCH"] != nil))
    func `bash grammar artifacts are not reloaded after warmup`() async {
        _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        let baseline = residentBytes()
        for _ in 0 ..< 50 {
            _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        }
        let after = residentBytes()
        let driftMB = Double(after - baseline) / 1024 / 1024
        print("ensureArtifacts(\"bash\") drift over 50 calls: \(driftMB) MB")
    }

    /// Allocation deltas move with the allocator's arenas on shared runners, so this is opt-in: `ATELIER_BENCH=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_BENCH"] != nil))
    func `repeated bash highlight does not accumulate allocations`() async {
        _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        let theme = Theme(defaultStyle: Style())

        func highlightOnce() {
            _ = LanguageHighlighter.highlightDocument(
                source: bashScript, language: "bash", theme: theme)
        }

        // Warm up so caches (grammar tables, allocator arenas) stabilize before measuring.
        for _ in 0 ..< 50 { highlightOnce() }

        assertAllocationsDoNotAccumulate(iterationsPerBatch: 200, highlightOnce)
    }

    /// The session path, whose state could retain parses across calls.
    /// Allocation deltas move with the allocator's arenas on shared runners, so this is opt-in: `ATELIER_BENCH=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_BENCH"] != nil))
    func `repeated bash session highlight does not accumulate allocations`() async {
        _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        let theme = Theme(defaultStyle: Style())
        let session = LanguageHighlighter.makeSession(
            language: "bash", theme: theme, preferGrammar: true)

        func highlightOnce() {
            _ = session.highlightDocument(source: bashScript)
        }

        for _ in 0 ..< 50 { highlightOnce() }

        assertAllocationsDoNotAccumulate(iterationsPerBatch: 200, highlightOnce)
    }

    /// Records an issue when a second batch of `body` allocates more than twice the first plus 1000: a per-call leak
    /// grows between batches, steady work doesn't.
    /// - Precondition: `body` is synchronous with no concurrent work in flight, since the allocation counter is
    ///   process-wide.
    private func assertAllocationsDoNotAccumulate(
        iterationsPerBatch: Int,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () -> Void
    ) {
        guard
            let firstBatch = mallocDelta({ for _ in 0 ..< iterationsPerBatch { body() } }),
            let secondBatch = mallocDelta({ for _ in 0 ..< iterationsPerBatch { body() } })
        else {
            return  // allocation counting unavailable on this platform (see `allocationCountingAvailable`).
        }
        let allowedSlack = firstBatch * 2 + 1000
        if secondBatch > allowedSlack {
            Issue.record(
                """
                second batch of \(iterationsPerBatch) calls allocated \(secondBatch) vs \
                \(firstBatch) for the first — possible per-call accumulation
                """,
                sourceLocation: sourceLocation)
        }
    }
}
