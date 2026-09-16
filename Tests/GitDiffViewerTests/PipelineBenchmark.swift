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
    @Test(
        .enabled(
            if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil
                && ProcessInfo.processInfo.environment["GDV_BENCH_PATCH"] != nil))
    func `pipeline phases over a patch`() async throws {
        let path = ProcessInfo.processInfo.environment["GDV_BENCH_PATCH"] ?? ""
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let clock = ContinuousClock()
        var totals: [String: Duration] = [:]
        var worst: [String: (String, Duration)] = [:]
        func time<T>(_ phase: String, _ file: String, _ body: () throws -> T) rethrows -> T {
            let start = clock.now
            let result = try body()
            let elapsed = clock.now - start
            totals[phase, default: .zero] += elapsed
            if elapsed > (worst[phase]?.1 ?? .zero) { worst[phase] = (file, elapsed) }
            return result
        }

        let patch = time("parse", path) { UnifiedPatch(parsing: text) }
        var prepared: [PreparedDiff] = []
        for file in patch.files where !file.isBinary {
            let name = file.newPath ?? file.oldPath ?? "?"
            let texts = file.reconstructedTexts
            let old = texts.old ?? ""
            let new = texts.new ?? ""
            let language = Language(fileExtension: (name as NSString).pathExtension)
            _ = time("split lines", name) { (DiffModel.lines(of: old), DiffModel.lines(of: new)) }
            _ = time("syntax token ranges", name) {
                (
                    SyntaxTokenizer.tokenRangesByLine(text: old, language: language),
                    SyntaxTokenizer.tokenRangesByLine(text: new, language: language)
                )
            }
            _ = time("model: word tier", name) {
                DiffModel(oldText: old, newText: new, granularity: .word, language: language)
            }
            let model = time("model: syntax tier", name) {
                DiffModel(oldText: old, newText: new, granularity: .syntax, language: language)
            }
            _ = time("highlight tokens", name) {
                (
                    DiffRenderer.tokensByLine(text: old, lines: model.oldLines, language: language),
                    DiffRenderer.tokensByLine(text: new, lines: model.newLines, language: language)
                )
            }
            prepared.append(
                time("prepare total", name) {
                    PreparedDiff(
                        FileDiffInput(title: name, oldText: old, newText: new, language: language), granularity: .syntax
                    )
                })
        }
        let split = DiffRenderer.Options(
            granularity: .syntax, palette: .system, lineHeightMultiple: 0, sides: [.old, .new])
        let inline = DiffRenderer.Options(
            granularity: .syntax, palette: .system, lineHeightMultiple: 0, sides: [.unified])
        var rendered: [RenderedDiff] = []
        for (index, file) in prepared.enumerated() {
            _ = time("render inline, changes", file.title) {
                DiffRenderer.render(
                    prepared: [file], options: inline, layout: .changes(context: 3, expansions: [:]),
                    withHeaders: false, firstFileIndex: index)
            }
            _ = time("render split, full", file.title) {
                DiffRenderer.render(
                    prepared: [file], options: split, layout: .full, withHeaders: false, firstFileIndex: index)
            }
            rendered.append(
                time("render split, changes", file.title) {
                    DiffRenderer.render(
                        prepared: [file], options: split, layout: .changes(context: 3, expansions: [:]),
                        withHeaders: false, firstFileIndex: index)
                })
        }
        for (index, diff) in rendered.enumerated() {
            let layouts = time("card layouts init", prepared[index].title) { CardLayouts(rendered: diff) }
            time("card layouts split", prepared[index].title) { layouts.prepareSplit(width: 700, mode: .viewport) }
        }
        print("BENCH files \(prepared.count)")
        for (phase, total) in totals.sorted(by: { $0.value > $1.value }) {
            let w = worst[phase]!
            print(
                "BENCH \(phase): \(Self.ms(total)) ms total, worst \(Self.ms(w.1)) ms in \(w.0.split(separator: "/").last ?? "")"
            )
        }
    }

    private static func ms(_ d: Duration) -> String {
        String(format: "%7.1f", Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
    }
}
