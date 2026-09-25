import AppKit
import AtelierHighlighting
import AtelierSwiftSyntax
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Opt-in timing of the syntactic tier (PERF-11 steps 1 to 3) against its budgets (design note, section 4.7):
/// swift-syntax's parse of one side of about 71 KB through the tier job, with every fact the app keeps of it, cut into
/// line tokens, within 50 ms; and applying what lands to one screen of a pane, within 1 ms of the main thread. The
/// budgets hold CPU time, which a loaded machine does not inflate; the wall times are printed beside it, and the tier's
/// cost for colour alone, interleaved with it.
///
/// `GDV_BENCH=1 swift test -c release --filter SwiftColorRefinementBenchmark`. `GDV_BENCH_SWIFT` names the Swift file;
/// without it, KittyCode's `EditorStateCore.swift`, 71 KB when the budget was set, stands in.
@MainActor
@Suite(.mainActorLane)
struct SwiftColorRefinementBenchmark {
    private static let iterations = 15
    private static let warmUps = 3
    private static let tierBudget = 50.0
    private static let applicationBudget = 1.0

    private static func sample() throws -> String {
        let path =
            ProcessInfo.processInfo.environment["GDV_BENCH_SWIFT"]
            ?? URL(filePath: #filePath).deletingLastPathComponent()
            .appending(
                path: "../../../KittyCode/Sources/KittyEditor/EditorStateCore.swift"
            )
            .standardized.path(percentEncoded: false)
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func median(_ samples: [Double]) -> Double {
        samples.sorted()[samples.count / 2]
    }

    private static func milliseconds(_ elapsed: Duration) -> Double {
        Double(elapsed.components.seconds) * 1e3 + Double(elapsed.components.attoseconds) / 1e15
    }

    /// CPU time of `clock`, `CLOCK_PROCESS_CPUTIME_ID` or `CLOCK_THREAD_CPUTIME_ID`, in milliseconds: unlike wall time,
    /// it does not grow when other work shares the machine.
    private static func cpuMilliseconds(_ clock: clockid_t) -> Double {
        Double(clock_gettime_nsec_np(clock)) / 1e6
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `refines a seventy kilobyte side and applies a screen within budget`() async throws {
        let text = try Self.sample()
        let lines = DiffModel.lines(of: text)
        var tier: [Double] = []
        var tierCPU: [Double] = []
        var colourOnlyCPU: [Double] = []
        var refined = LayeredLineTokens(lineCount: 0)
        let request = TierRequest(
            revision: SourceRevision(documentID: "sample.swift", language: .swift, key: .content("sample")), text: text,
            lineRanges: DiffRenderer.lineRanges(of: text, lines: lines), visibleLines: 0 ..< 80, unit: .utf16)
        /// Runs the tier through the job, returning the side's layers.
        func refine(_ tier: SwiftSyntaxTier) async -> LayeredLineTokens {
            let updates = Mutex([TierUpdate]())
            await HighlightTiers.run(request, tiers: [tier], clock: ContinuousClock()) { event in
                if case .update(let update) = event { updates.withLock { $0.append(update) } }
            }
            var layered = LayeredLineTokens(lineCount: lines.count)
            for update in updates.withLock({ $0 }) { layered.apply(update) }
            return layered
        }
        for iteration in 0 ..< Self.iterations {
            // The parse runs on threads of its own, so the process's CPU time counts it; nothing else runs meanwhile.
            // The app's path first, a fresh store extracting every fact (step 3), then colour alone, interleaved.
            let cpu = Self.cpuMilliseconds(CLOCK_PROCESS_CPUTIME_ID)
            let start = ContinuousClock.now
            refined = await refine(SwiftSyntaxTier(deadline: nil, store: SyntaxFactsStore()))
            let elapsed = ContinuousClock.now - start
            let facts = Self.cpuMilliseconds(CLOCK_PROCESS_CPUTIME_ID)
            _ = await refine(SwiftSyntaxTier(deadline: nil))
            guard iteration >= Self.warmUps else { continue }
            tier.append(Self.milliseconds(elapsed))
            tierCPU.append(facts - cpu)
            colourOnlyCPU.append(Self.cpuMilliseconds(CLOCK_PROCESS_CPUTIME_ID) - facts)
        }

        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .swift).new)
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 900, height: 800)
        textView.textStorage?.setAttributedString(rendered.attributed)
        let layoutManager = try #require(textView.textLayoutManager)
        var fragments: [NSTextLayoutFragment] = []
        _ = layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location, options: .ensuresLayout
        ) { fragment in
            fragments.append(fragment)
            return true
        }
        // The last screen, 800 points of rows: the farthest from the document's start, where locations cost most.
        let rowHeight = try #require(fragments.first).layoutFragmentFrame.height
        let screen = Array(fragments.suffix(Int((800 / rowHeight).rounded(.up))))
        let colors = DecorationStore()
        colors.install(on: layoutManager)
        let decorations = DecorationFixtures.colors(old: refined, new: refined)
        var application: [Double] = []
        var applicationCPU: [Double] = []
        var landingCPU: [Double] = []
        for iteration in 0 ..< Self.iterations {
            // Each landing starts from the plain text, as a new text's does: every token paints (PERF-09).
            colors.update(rendered: rendered, decorations: nil, view: textView)
            let cpu = Self.cpuMilliseconds(CLOCK_THREAD_CPUTIME_ID)
            let start = ContinuousClock.now
            colors.update(rendered: rendered, decorations: decorations, view: textView)
            let landed = Self.cpuMilliseconds(CLOCK_THREAD_CPUTIME_ID)
            for fragment in screen { colors.validate(fragment, in: layoutManager) }
            guard iteration >= Self.warmUps else { continue }
            application.append(Self.milliseconds(ContinuousClock.now - start))
            applicationCPU.append(Self.cpuMilliseconds(CLOCK_THREAD_CPUTIME_ID) - cpu)
            landingCPU.append(landed - cpu)
        }
        let tokenCount = (0 ..< lines.count).map { refined.merged(line: $0)?.count ?? 0 }.reduce(0, +)
        let lexical = LexicalHighlightEngine().highlight(utf8: Array(text.utf8), language: .swift).count

        print(
            "SwiftColorRefinementBenchmark: \(text.utf8.count) bytes, \(lines.count) lines, "
                + "\(tokenCount) tokens; tier median \(Self.median(tierCPU)) ms CPU with every fact, "
                + "\(Self.median(tier)) ms wall (budget \(Self.tierBudget)), \(Self.median(colourOnlyCPU)) ms CPU for "
                + "colour alone; \(screen.count) rows, application median "
                + "\(Self.median(applicationCPU)) ms CPU, \(Self.median(application)) ms wall "
                + "(budget \(Self.applicationBudget)), of which the landing's own \(Self.median(landingCPU)) ms CPU; "
                + "the lexer finds \(lexical) tokens")
        #expect(Self.median(tierCPU) <= Self.tierBudget)
        #expect(Self.median(applicationCPU) <= Self.applicationBudget)
    }
}
