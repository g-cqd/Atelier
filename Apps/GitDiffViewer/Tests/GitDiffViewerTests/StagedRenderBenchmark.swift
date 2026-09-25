import AppKit
import AtelierHighlighting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffRendering
@testable import DiffTextKit

/// Opt-in timing of each stage of the text-first pipeline (PERF-09) against the budget review §7.4 sets it, in CPU time,
/// on an L file (KittyCode's `EditorStateCore.swift`, one line in 23 edited) and an XL one (9,000 generated lines, one in
/// 7 edited): `GDV_BENCH=1 swift test -c release --filter StagedRenderBenchmark`.
///
/// - Stage 0, off the main actor: the file prepared and its plain text rendered, within the 100 ms from a click to the
///   text. Interleaved with the work the preparation did before the text came first, the whole diff's emphasis and
///   moved lines and both sides lexed, which it now leaves to the stages after the text.
/// - Stage 0, on the main actor: the plain text put in a pane and its first screen laid out and drawn, within 16 ms.
/// - Stage 1: the lexer's colour of one screen applied to the pane, within 1 ms.
/// - Stage 2: every change's emphasis and the moved lines of the L file, within the 250 ms of its deadline.
@MainActor
@Suite(.mainActorLane, .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
struct StagedRenderBenchmark {
    private static let rounds = 11

    /// The two sides of the L file.
    private static func large() throws -> (old: String, new: String) {
        let path = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../KittyCode/Sources/KittyEditor/EditorStateCore.swift").standardized
        let old = try String(contentsOf: path, encoding: .utf8)
        let new = old.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .map { $0.offset % 23 == 5 ? $0.element + " // edited" : String($0.element) }.joined(separator: "\n")
        return (old, new)
    }

    /// The two sides of the XL file.
    private static func extraLarge() -> (old: String, new: String) {
        var old = ""
        var new = ""
        for index in 0 ..< 9_000 {
            let line = "    let value\(index) = compute(\(index), \"label \(index)\") // note \(index)\n"
            old += line
            new += index % 7 == 3 ? line.replacingOccurrences(of: "compute", with: "evaluate") : line
        }
        return (old, new)
    }

    @Test
    func `each stage within its budget`() async throws {
        let options = DiffRenderer.Options(granularity: .word, sides: [.old, .new])
        var preparedL: PreparedDiff?
        for (name, pair, budget) in [("L", try Self.large(), 100.0), ("XL", Self.extraLarge(), 100.0)] {
            let input = FileDiffInput(title: "\(name).swift", oldText: pair.old, newText: pair.new, language: .swift)
            var textFirst: [Double] = []
            var before: [Double] = []
            var rendered: RenderedDiff?
            for round in 0 ..< Self.rounds {
                for current in round.isMultiple(of: 2) ? [true, false] : [false, true] {
                    let start = Self.cpu()
                    let prepared = PreparedDiff(input, granularity: .word)
                    let diff = DiffRenderer.render(
                        prepared: [prepared], options: options, layout: .full, withHeaders: false)
                    if !current {
                        // What the preparation ran before the text came first.
                        _ = DiffModel(
                            oldText: pair.old, newText: pair.new, granularity: .word, language: .swift,
                            tokenRanges: CodeTokenRanges())
                        let engine = LexicalHighlightEngine()
                        _ = DecorationFixtures.byLine(
                            engine.highlight(utf8: Array(pair.old.utf8), language: .swift), text: pair.old,
                            lines: prepared.model.oldLines)
                        _ = DecorationFixtures.byLine(
                            engine.highlight(utf8: Array(pair.new.utf8), language: .swift), text: pair.new,
                            lines: prepared.model.newLines)
                    }
                    let elapsed = Self.cpu() - start
                    if round > 0, current { textFirst.append(elapsed) }
                    if round > 0, !current { before.append(elapsed) }
                    rendered = diff
                    if name == "L" { preparedL = prepared }
                }
            }
            print(
                "BENCH staged \(name) stage 0 off the main actor: text first \(Self.summary(textFirst)) ms CPU, "
                    + "before \(Self.summary(before)) ms CPU (budget \(budget))")
            #expect(Self.median(textFirst) <= budget)
            if name == "L", let text = rendered?.new { try await Self.measureMainActor(text, pair: pair) }
        }
        let prepared = try #require(preparedL)
        var marks: [Double] = []
        for round in 0 ..< Self.rounds {
            let start = Self.cpu()
            await RenderPipeline.findMarks(of: prepared, first: [], clock: ContinuousClock()) { _ in }
            if round > 0 { marks.append(Self.cpu() - start) }
        }
        print(
            "BENCH staged L stage 2: \(prepared.model.structure.changes.count) changes' emphasis and moved lines "
                + "\(Self.summary(marks)) ms CPU (budget 250)")
        #expect(Self.median(marks) <= 250)
    }

    /// Stage 0 on the main actor, and stage 1, for `text`, the new side of `pair`.
    private static func measureMainActor(_ text: RenderedText, pair: (old: String, new: String)) async throws {
        let pane = try NewDocumentPane(showing: text)
        var shown: [Double] = []
        for round in 0 ..< rounds {
            let start = threadCPU()
            _ = pane.show(text, emptyingFirst: true)
            if round > 0 { shown.append(threadCPU() - start) }
        }
        let layers = await DecorationFixtures.lexed(pair.new, language: .swift)
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 900, height: 800)
        textView.textStorage?.setAttributedString(text.attributed)
        let layoutManager = try #require(textView.textLayoutManager)
        // The first screen's fragments, which a window's viewport would validate: a detached view has no viewport.
        var screen: [NSTextLayoutFragment] = []
        _ = layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location, options: .ensuresLayout
        ) { fragment in
            screen.append(fragment)
            return fragment.layoutFragmentFrame.maxY < 800
        }
        let store = DecorationStore()
        store.install(on: layoutManager)
        var applied: [Double] = []
        for round in 0 ..< rounds {
            store.update(rendered: text, decorations: nil, view: textView)
            let start = threadCPU()
            store.update(
                rendered: text, decorations: DecorationFixtures.colors(old: nil, new: layers, version: round + 1),
                view: textView)
            for fragment in screen { store.validate(fragment, in: layoutManager) }
            if round > 0 { applied.append(threadCPU() - start) }
        }
        print(
            "BENCH staged L stage 0 on the main actor \(summary(shown)) ms CPU (budget 16); stage 1, one screen of "
                + "the lexer's colour \(summary(applied)) ms CPU (budget 1)")
        #expect(median(shown) <= 16)
        #expect(median(applied) <= 1)
    }

    private static func cpu() -> Double { Double(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID)) / 1e6 }
    private static func threadCPU() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e6 }
    private static func median(_ samples: [Double]) -> Double { samples.sorted()[samples.count / 2] }

    private static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        return String(format: "median %.2f (min %.2f, max %.2f)", sorted[sorted.count / 2], sorted[0], sorted.last ?? 0)
    }
}
