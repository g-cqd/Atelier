import AtelierSyntaxModel
import Foundation
import Testing

/// Opt-in timing of the per-line merge over one screen, interleaved in one binary, in process CPU time (P1c):
/// `GDV_BENCH=1 swift test -c release --filter LayeredMergeBenchmark`.
///
/// - Before: the merge `LayeredLineTokens` ran until P1c, `HighlightMerger`'s per-byte map over each line's shown
///   layers.
/// - After: ``LayeredLineTokens/merged(line:)``, which lays each layer over the one below in one pass.
///
/// Each of 60 lines of 120 bytes holds a complete layer of 24 tokens and a sparse layer of 6. Budget: 0.1 ms per
/// screen, a tenth of the 1 ms a tier's update may take to apply to one (design note §4.7).
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
struct LayeredMergeBenchmark {
    private static let revision = SourceRevision(documentID: "a.swift", language: .swift, key: .content("blob"))

    @Test
    func `merging one screen of two layers`() {
        let lineCount = 60
        var complete: [HighlightToken] = []
        var sparse: [HighlightToken] = []
        var lineRanges: [Range<Int>] = []
        for line in 0 ..< lineCount {
            let start = line * 121
            lineRanges.append(start ..< start + 120)
            for index in 0 ..< 24 {
                complete.append(
                    HighlightToken(
                        byteRange: start + index * 5 ..< start + index * 5 + 3, role: .keyword, layer: .syntactic))
            }
            for index in 0 ..< 6 {
                sparse.append(
                    HighlightToken(
                        byteRange: start + index * 20 + 2 ..< start + index * 20 + 9, role: .variable,
                        layer: .semantic))
            }
        }
        var layered = LayeredLineTokens(lineCount: lineCount)
        for (layer, coverage, tokens) in [
            (HighlightLayer.syntactic, TierCoverage.complete, complete), (.semantic, .sparse, sparse)
        ] {
            layered.apply(
                TierUpdate(
                    layer: layer, coverage: coverage, revision: Self.revision, lines: 0 ..< lineCount,
                    tokens: LineTokens(tokens, lineRanges: lineRanges)))
        }
        let completeLines = LineTokens(complete, lineRanges: lineRanges)
        let sparseLines = LineTokens(sparse, lineRanges: lineRanges)

        var before: [Double] = []
        var after: [Double] = []
        for round in 0 ..< 201 {
            for current in round.isMultiple(of: 2) ? [false, true] : [true, false] {
                let start = Self.cpu()
                var sink = 0
                for line in 0 ..< lineCount {
                    if current {
                        sink &+= layered.merged(line: line)?.count ?? 0
                    } else {
                        let tokens =
                            completeLines[line].map { Self.token($0, layer: .syntactic) }
                            + sparseLines[line].map { Self.token($0, layer: .semantic) }
                        sink &+= HighlightMerger.merge(tokens, sourceByteCount: 120).count
                    }
                }
                let elapsed = Self.cpu() - start
                withExtendedLifetime(sink) {}
                if current { after.append(elapsed) } else { before.append(elapsed) }
            }
        }
        print(
            "BENCH layered-merge 60 lines: before \(Self.summary(before)) ms CPU, after \(Self.summary(after)) ms CPU")
        #expect(after.sorted()[after.count / 2] <= 0.1)
    }

    private static func token(_ token: LineToken, layer: HighlightLayer) -> HighlightToken {
        HighlightToken(byteRange: token.range, role: token.role, modifiers: token.modifiers, layer: layer)
    }

    /// The process's CPU time, in milliseconds: the suite runs alone, so it is the benchmark's.
    private static func cpu() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1e6
    }

    private static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        let pick = { (fraction: Double) in sorted[Int((Double(sorted.count - 1) * fraction).rounded())] }
        return String(format: "median %.4f (p10 %.4f, p90 %.4f)", pick(0.5), pick(0.1), pick(0.9))
    }
}
