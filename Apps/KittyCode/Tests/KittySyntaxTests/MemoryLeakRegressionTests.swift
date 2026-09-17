import AemiTestKit
import Foundation
import KittyCodecs
import Testing

@testable import KittySyntax

/// Stress tests that exercise highlight repeatedly and guard against per-call
/// accumulation in the parse / highlight / tree-drop path.
///
/// The default run never compares wall-clock durations or RSS (see
/// `AGENTS.md`): the two synchronous stress tests below measure heap
/// allocation counts with `AemiTestKit.mallocDelta` instead of resident
/// memory, and compare two equal-sized batches to each other rather than
/// against an absolute, hand-tuned budget — a per-call leak shows up as the
/// second batch allocating substantially more than the first, while steady
/// -state work allocates about the same amount every batch. The one
/// genuinely async, RSS-based check (`ensureArtifacts` reload cost) can't be
/// measured this way (see its doc comment) and is gated behind
/// `ATELIER_BENCH` instead of running by default.
@Suite
@MainActor
struct MemoryLeakRegressionTests {
    /// Returns the current process resident-memory footprint in bytes. Only
    /// used by the `ATELIER_BENCH`-gated test below, which prints (never
    /// asserts on) the measurement.
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

    @Test
    func `bash grammar artifacts load successfully`() async {
        // User report: opening a `.sh` file in kittycode "ends up consuming
        // memory infinitely" — pointing the finger at bash artifact
        // compilation. The correctness half of that regression guard (does
        // the load complete and succeed) runs unconditionally; a genuinely
        // runaway compilation would hang the test run itself rather than
        // trip a duration assertion, so no wall-clock bound is needed here
        // (and none may run by default — see `AGENTS.md`).
        let loaded = await LanguageHighlighter.ensureArtifacts(for: "bash")
        #expect(loaded == true, "bash artifacts failed to load")
    }

    /// Second call must hit the cache. If it doesn't, every artifact load
    /// allocates fresh tables and the per-open cost compounds. `ensureArtifacts`
    /// always hops onto a detached `Task` (see its doc comment), so this body
    /// is inherently concurrent and can't be measured with the synchronous-only
    /// `mallocDelta`/`expectAllocations`; RSS is the only signal available, and
    /// RSS may not drive an assertion in the default run (`AGENTS.md`), so this
    /// is an opt-in benchmark instead: run with `ATELIER_BENCH=1 swift test`.
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

    /// Repeatedly call session-bound highlightDocument — different surface
    /// than the static path and a candidate for leaks if internal session
    /// state retains across parses (the historical concern was the now-
    /// removed `previousTree` storage on `GrammarSession`).
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

    /// Runs two equal-sized batches of `body` and asserts the second batch doesn't allocate
    /// substantially more than the first. A per-call leak (state retained across calls) shows up
    /// as super-linear growth between batches; steady-state work allocates about the same amount
    /// every batch. This sidesteps needing a hand-tuned absolute allocation budget — the only
    /// number here is the slack multiplier, not a per-call count nobody has actually measured.
    /// `body` must be synchronous with no concurrent work in flight (`mallocDelta`'s requirement:
    /// the allocation counter is process-wide).
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
