import AemiTestKit
import Foundation
import KittyCodecs
import Testing

@testable import KittySyntax

/// Stress tests guarding the parse, highlight and tree-drop path against per-call accumulation. Only the bash load
/// check runs by default; the allocation and RSS measurements are opt-in through `ATELIER_BENCH`.
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

    /// With its scanner registered, bash's grammar is compiled rather than stood in for by empty tables, and it passes
    /// the compiler's 4,000-state limit: its artifacts decline, and bash highlights lexically, as it did.
    @Test
    func `bash grammar artifacts decline without hanging while its grammar passes the state limit`() async {
        // A runaway bash compile would hang this test outright, so it needs no time bound.
        let loaded = await LanguageHighlighter.ensureArtifacts(for: "bash")
        #expect(loaded == false, "bash artifacts loaded")
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
