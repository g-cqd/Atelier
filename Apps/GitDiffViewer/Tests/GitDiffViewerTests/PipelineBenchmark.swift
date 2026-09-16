import AtelierSwiftSyntax
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffCore
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// Opt-in phase timing of the whole pipeline over a patch file; run with GDV_BENCH=1 and GDV_BENCH_PATCH=path.
@MainActor
struct PipelineBenchmark {
    /// Accumulates the time of each phase and remembers the slowest file for it.
    private struct PhaseTimings {
        private let clock = ContinuousClock()
        private(set) var totals: [String: Duration] = [:]
        private(set) var worst: [String: (file: String, elapsed: Duration)] = [:]

        mutating func time<T>(_ phase: String, _ file: String, _ body: () throws -> T) rethrows -> T {
            let start = clock.now
            let result = try body()
            let elapsed = clock.now - start
            totals[phase, default: .zero] += elapsed
            if elapsed > (worst[phase]?.elapsed ?? .zero) { worst[phase] = (file, elapsed) }
            return result
        }
    }

    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil
                && ProcessInfo.processInfo.environment["GDV_BENCH_PATCH"] != nil))
    func `pipeline phases over a patch`() async throws {
        let path = ProcessInfo.processInfo.environment["GDV_BENCH_PATCH"] ?? ""
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var timings = PhaseTimings()
        let patch = timings.time("parse", path) { UnifiedPatch(parsing: text) }
        let prepared = Self.prepare(patch, timings: &timings)
        let rendered = Self.render(prepared, timings: &timings)
        for (index, diff) in rendered.enumerated() {
            let layouts = timings.time("card layouts init", prepared[index].title) { CardLayouts(rendered: diff) }
            timings.time("card layouts split", prepared[index].title) {
                layouts.prepareSplit(width: 700, mode: .viewport)
            }
        }
        print("BENCH files \(prepared.count)")
        for (phase, total) in timings.totals.sorted(by: { $0.value > $1.value }) {
            guard let worst = timings.worst[phase] else { continue }
            let file = worst.file.split(separator: "/").last ?? ""
            print("BENCH \(phase): \(Self.ms(total)) ms total, worst \(Self.ms(worst.elapsed)) ms in \(file)")
        }
    }

    /// The diff of every text file of the patch, each phase timed on its own before the whole preparation.
    private static func prepare(_ patch: UnifiedPatch, timings: inout PhaseTimings) -> [PreparedDiff] {
        let tokenizer = SwiftSyntaxTokenRanges()
        var prepared: [PreparedDiff] = []
        for file in patch.files where !file.isBinary {
            let name = file.newPath ?? file.oldPath ?? "?"
            let texts = file.reconstructedTexts
            let old = texts.old ?? ""
            let new = texts.new ?? ""
            let language = Language(fileExtension: (name as NSString).pathExtension)
            _ = timings.time("split lines", name) { (DiffModel.lines(of: old), DiffModel.lines(of: new)) }
            _ = timings.time("syntax token ranges", name) {
                (
                    tokenizer.tokenRangesByLine(text: old, language: language),
                    tokenizer.tokenRangesByLine(text: new, language: language)
                )
            }
            _ = timings.time("model: word tier", name) {
                DiffModel(oldText: old, newText: new, granularity: .word, language: language, tokenRanges: tokenizer)
            }
            let model = timings.time("model: syntax tier", name) {
                DiffModel(oldText: old, newText: new, granularity: .syntax, language: language, tokenRanges: tokenizer)
            }
            _ = timings.time("highlight tokens", name) {
                (
                    DiffRenderer.tokensByLine(text: old, lines: model.oldLines, language: language),
                    DiffRenderer.tokensByLine(text: new, lines: model.newLines, language: language)
                )
            }
            prepared.append(
                timings.time("prepare total", name) {
                    PreparedDiff(
                        FileDiffInput(title: name, oldText: old, newText: new, language: language), granularity: .syntax
                    )
                })
        }
        return prepared
    }

    /// Every prepared file rendered in the three layouts a window uses; returns the split changes-only render.
    private static func render(_ prepared: [PreparedDiff], timings: inout PhaseTimings) -> [RenderedDiff] {
        let split = DiffRenderer.Options(
            granularity: .syntax, palette: .system, lineHeightMultiple: 0, sides: [.old, .new])
        let inline = DiffRenderer.Options(
            granularity: .syntax, palette: .system, lineHeightMultiple: 0, sides: [.unified])
        var rendered: [RenderedDiff] = []
        for (index, file) in prepared.enumerated() {
            _ = timings.time("render inline, changes", file.title) {
                DiffRenderer.render(
                    prepared: [file], options: inline, layout: .changes(context: 3, expansions: [:]),
                    withHeaders: false, firstFileIndex: index)
            }
            _ = timings.time("render split, full", file.title) {
                DiffRenderer.render(
                    prepared: [file], options: split, layout: .full, withHeaders: false, firstFileIndex: index)
            }
            rendered.append(
                timings.time("render split, changes", file.title) {
                    DiffRenderer.render(
                        prepared: [file], options: split, layout: .changes(context: 3, expansions: [:]),
                        withHeaders: false, firstFileIndex: index)
                })
        }
        return rendered
    }

    private static func ms(_ d: Duration) -> String {
        String(format: "%7.1f", Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
    }
}
