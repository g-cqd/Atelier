import AtelierLexers
import AtelierSyntaxModel
import AtelierText
import Foundation
import Testing

/// Opt-in timing of the lexical tier's two paths over one Swift side of about a megabyte, interleaved in one binary,
/// in process CPU time (PERF-09's fifth criterion, P1a): `GDV_BENCH=1 swift test -c release --filter
/// ProgressiveHighlightingBenchmark`.
///
/// - Before: the whole side scanned, then the visible lines cut from it, which is what the lexical tier emitted first.
/// - After: ``ProgressiveHighlighting``, whose first chunk is the visible lines alone, from a guessed state; then the
///   whole run, and `lexAll` in four pieces.
///
/// Budgets (design note §4.7): the visible lines of one side within 1 ms, a whole side within 2 ms per 100 KB.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
struct ProgressiveHighlightingBenchmark {
    private static let rounds = 31

    @Test
    func `the visible lines of a side, then the whole side`() async throws {
        var text = ""
        var seed: UInt64 = 1
        while text.utf8.count < 1_000_000 {
            text += LexerCorpus.text(.swift, seed: seed)
            seed += 1
        }
        let lines = TextLines(text)
        let lexer = LexicalLineLexer(language: .swift)
        let middle = lines.lineCount / 2
        let visible = middle ..< middle + 60
        let hundredKB = Double(text.utf8.count) / 100_000

        var before: [Double] = []
        var visibleCPU: [Double] = []
        var wholeCPU: [Double] = []
        var parallelWall: [Double] = []
        var parallelCPU: [Double] = []
        for round in 0 ..< Self.rounds {
            for after in round.isMultiple(of: 2) ? [false, true] : [true, false] {
                if after {
                    let start = Self.cpu()
                    var first: Double?
                    let states = await ProgressiveHighlighting.run(lines, lexer: lexer, visibleLines: visible) { _, _ in
                        if first == nil { first = Self.cpu() - start }
                    }
                    wholeCPU.append(Self.cpu() - start)
                    visibleCPU.append(first ?? .nan)
                    #expect(states.exactLines == lines.lineCount)
                } else {
                    let start = Self.cpu()
                    let utf8 = text.utf8Span
                    let tokens = LexicalHighlightEngine().highlight(utf8: utf8.span, language: .swift)
                    let cut = LineTokens(tokens, lineRanges: Array(lines.lineRanges[visible]))
                    before.append(Self.cpu() - start)
                    withExtendedLifetime(cut) {}
                }
            }
            let wall = ContinuousClock.now
            let start = Self.cpu()
            let all = try await ProgressiveHighlighting.lexAll(lines, lexer: lexer, parallelism: 4)
            parallelCPU.append(Self.cpu() - start)
            parallelWall.append(Self.milliseconds(wall.duration(to: .now)))
            withExtendedLifetime(all) {}
        }
        let wholePer100KB = Self.median(wholeCPU) / hundredKB
        print(
            "BENCH progressive-lexing bytes \(text.utf8.count) lines \(lines.lineCount): visible lines before "
                + "\(Self.summary(before)) ms CPU, after \(Self.summary(visibleCPU)) ms CPU; whole side "
                + "\(Self.summary(wholeCPU)) ms CPU (\(Self.format(wholePer100KB)) ms per 100 KB); lexAll x4 "
                + "\(Self.summary(parallelWall)) ms wall, \(Self.summary(parallelCPU)) ms CPU")
        #expect(Self.median(visibleCPU) <= 1)
        #expect(wholePer100KB <= 2)
    }

    /// The process's CPU time, in milliseconds: the suite runs alone, so it is the benchmark's.
    private static func cpu() -> Double {
        Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1e6
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func median(_ samples: [Double]) -> Double {
        samples.sorted()[samples.count / 2]
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        let pick = { (fraction: Double) in sorted[Int((Double(sorted.count - 1) * fraction).rounded())] }
        return "median \(format(pick(0.5))) (p10 \(format(pick(0.1))), p90 \(format(pick(0.9))))"
    }
}
