import Foundation
import KittyCodecs
import Testing

@testable import KittySyntax

/// Stress tests that exercise highlight repeatedly and assert resident memory
/// doesn't drift past a bound — guards against per-call leaks in the
/// parse / highlight / tree-drop path.
@Suite
@MainActor
struct MemoryLeakRegressionTests {

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

    @Test
    func `repeated bash highlight does not accumulate memory`() async {
        _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        let theme = Theme(defaultStyle: Style())

        // Warmup so caches stabilize.
        for _ in 0..<20 {
            _ = LanguageHighlighter.highlightDocument(
                source: bashScript, language: "bash", theme: theme)
        }
        let baseline = residentBytes()

        for _ in 0..<500 {
            _ = LanguageHighlighter.highlightDocument(
                source: bashScript, language: "bash", theme: theme)
        }
        let after = residentBytes()

        // We allow some growth (caches, autorelease pool, etc.) but not
        // anywhere near proportional to call count. A real per-call leak
        // would show MB-scale drift over 500 calls.
        let drift = after - baseline
        let maxAllowedDriftBytes = 32 * 1024 * 1024  // 32 MB
        #expect(
            drift < maxAllowedDriftBytes,
            "memory drifted \(drift / 1024 / 1024) MB over 500 bash highlight calls (baseline \(baseline / 1024 / 1024) MB, after \(after / 1024 / 1024) MB)"
        )
    }

    /// Repeatedly call highlightDocumentTokens (the layered code path used by
    /// `highlightDocumentMerged`) — a different surface than the span-only
    /// pipeline and a candidate for leaks if tokens accumulate.
    @Test
    func `repeated bash token highlight does not accumulate memory`() async {
        _ = await LanguageHighlighter.ensureArtifacts(for: "bash")
        let theme = Theme(defaultStyle: Style())
        let session = LanguageHighlighter.makeSession(
            language: "bash", theme: theme, preferGrammar: true)

        for _ in 0..<20 {
            _ = session.highlightDocument(source: bashScript)
        }
        let baseline = residentBytes()

        for _ in 0..<500 {
            _ = session.highlightDocument(source: bashScript)
        }
        let after = residentBytes()

        let drift = after - baseline
        let maxAllowedDriftBytes = 32 * 1024 * 1024
        #expect(
            drift < maxAllowedDriftBytes,
            "session-reuse drift \(drift / 1024 / 1024) MB over 500 calls (baseline \(baseline / 1024 / 1024) MB, after \(after / 1024 / 1024) MB)"
        )
    }
}
