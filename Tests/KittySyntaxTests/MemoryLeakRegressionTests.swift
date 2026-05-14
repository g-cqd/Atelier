import Foundation
import KittyCodecs
import Testing

@testable import KittySyntax

/// Stress tests that exercise highlight repeatedly and assert resident memory
/// doesn't drift past a bound — guards against per-call leaks in the
/// parse / highlight / tree-drop path.
///
/// Each test is bounded by a wall-clock budget (`ContinuousClock`) rather
/// than a fixed iteration count so the cost scales with the machine: a
/// fast laptop runs ~thousands of iterations, slow CI runs hundreds, both
/// finish in the same wall-time and yield a meaningful memory drift number.
@Suite
@MainActor
struct MemoryLeakRegressionTests {

    /// Wall-clock budget per stress test. Long enough to detect real leaks
    /// (~MB-scale drift over many calls) but short enough not to stall the
    /// default `swift test` invocation.
    private let stressDuration: Duration = .seconds(3)

    /// Returns the current process resident-memory footprint in bytes.
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

    /// Runs `body` repeatedly until the elapsed clock duration exceeds
    /// `budget`. Returns the iteration count actually achieved.
    private func runFor(_ budget: Duration, _ body: () -> Void) -> Int {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: budget)
        var iterations = 0
        while clock.now < deadline {
            body()
            iterations &+= 1
        }
        return iterations
    }

    @Test
    func `bash grammar artifacts load within a time budget`() async {
        // User report: opening a `.sh` file in kittycode "ends up consuming
        // memory infinitely" — pointing the finger at bash artifact
        // compilation. Bound the call by a clock budget and assert it
        // returns. If the compilation has an unbounded path (infinite
        // recursion, exponential rule expansion), this test will time out.
        let clock = ContinuousClock()
        let start = clock.now
        let loaded = await LanguageHighlighter.ensureArtifacts(for: "bash")
        let elapsed = clock.now - start
        #expect(loaded == true, "bash artifacts failed to load")
        // Even on a slow runner the compiler should finish well under 30 s.
        #expect(
            elapsed < .seconds(30),
            "bash artifact load took \(elapsed) — possible runaway compilation"
        )
    }

    @Test
    func `bash grammar artifacts are not reloaded after warmup`() async {
        // Second call must hit the cache. If it doesn't, every artifact
        // load allocates fresh tables and the per-open cost compounds.
        _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        let baseline = residentBytes()
        for _ in 0..<50 {
            _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        }
        let after = residentBytes()
        let drift = after - baseline
        let maxAllowedDriftBytes = 8 * 1024 * 1024  // 8 MB
        #expect(
            drift < maxAllowedDriftBytes,
            "ensureArtifacts(\"bash\") drifted \(drift / 1024 / 1024) MB over 50 calls (baseline \(baseline / 1024 / 1024) MB, after \(after / 1024 / 1024) MB) — caching may be broken"
        )
    }

    @Test
    func `repeated bash highlight does not accumulate memory`() async {
        _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        let theme = Theme(defaultStyle: Style())

        // Warmup so caches stabilize.
        _ = runFor(.milliseconds(500)) {
            _ = LanguageHighlighter.highlightDocument(
                source: bashScript, language: "bash", theme: theme)
        }
        let baseline = residentBytes()

        let iterations = runFor(stressDuration) {
            _ = LanguageHighlighter.highlightDocument(
                source: bashScript, language: "bash", theme: theme)
        }
        let after = residentBytes()
        let drift = after - baseline

        // Allow some growth (caches, autorelease pool hysteresis) but not
        // anywhere near proportional to call count. A real per-call leak
        // would show MB-scale drift over thousands of calls.
        let maxAllowedDriftBytes = 32 * 1024 * 1024  // 32 MB
        #expect(
            drift < maxAllowedDriftBytes,
            "memory drifted \(drift / 1024 / 1024) MB over \(iterations) bash highlight calls (baseline \(baseline / 1024 / 1024) MB, after \(after / 1024 / 1024) MB)"
        )
    }

    /// Repeatedly call session-bound highlightDocument — different surface
    /// than the static path and a candidate for leaks if internal session
    /// state retains across parses (the historical concern was the now-
    /// removed `previousTree` storage on `GrammarSession`).
    @Test
    func `repeated bash session highlight does not accumulate memory`() async {
        _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        let theme = Theme(defaultStyle: Style())
        let session = LanguageHighlighter.makeSession(
            language: "bash", theme: theme, preferGrammar: true)

        _ = runFor(.milliseconds(500)) {
            _ = session.highlightDocument(source: bashScript)
        }
        let baseline = residentBytes()

        let iterations = runFor(stressDuration) {
            _ = session.highlightDocument(source: bashScript)
        }
        let after = residentBytes()
        let drift = after - baseline

        let maxAllowedDriftBytes = 32 * 1024 * 1024
        #expect(
            drift < maxAllowedDriftBytes,
            "session-reuse drift \(drift / 1024 / 1024) MB over \(iterations) calls (baseline \(baseline / 1024 / 1024) MB, after \(after / 1024 / 1024) MB)"
        )
    }
}
