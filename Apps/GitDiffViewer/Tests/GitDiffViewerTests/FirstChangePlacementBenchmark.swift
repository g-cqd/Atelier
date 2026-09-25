import AppKit
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Opening a long file at its first change (book DIFF-08): the change near the file's top, then near its end, shown in
/// turn in the same panes as the temporary tab shows them, each timed from the new file to the end of the layout and
/// display passes that place it. The difference between the two is what placing a deep row costs. A short file shows
/// between the two and is timed too: it drops the rows TextKit laid out for the long one.
///
/// Run in release, alone on the machine: `GDV_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter
/// FirstChangePlacementBenchmark`. GDV_BENCH_ROWS sets the file's length and GDV_BENCH_RUNS the openings timed per
/// side.
@MainActor
@Suite(.mainActorLane)
struct FirstChangePlacementBenchmark {
    // Serialized: the layouts would otherwise share the main thread and time each other.
    @Test(
        .serialized, .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil),
        arguments: [(PaneLayout.inline, true), (.inline, false), (.sideBySide, true)])
    func `opening a long file at a change near its top and near its end`(layout: PaneLayout, wrapsLines: Bool)
        throws
    {
        let environment = ProcessInfo.processInfo.environment
        let rows = environment["GDV_BENCH_ROWS"].flatMap(Int.init) ?? 10_000
        let runs = environment["GDV_BENCH_RUNS"].flatMap(Int.init) ?? 15
        let near = PaneText.longLines(rows, changedAt: 30)
        let deep = PaneText.longLines(rows, changedAt: rows - 50)
        let short = PaneText.lines(40)
        let sut = HostedPanes(showing: short, layout: layout, wrapsLines: wrapsLines)

        var samples = Samples()
        // One opening each first, which the samples leave out.
        for run in 0 ... runs {
            for isDeep in run.isMultiple(of: 2) ? [false, true] : [true, false] {
                let opening = Self.time { sut.show(isDeep ? deep : near) }
                try Self.expectChangeNearTop(of: sut)
                // The short file in between drops what the long one laid out, which its own opening would pay for.
                let leaving = Self.time { sut.show(short) }
                guard run > 0 else { continue }
                samples.append(opening: opening, leaving: leaving, isDeep: isDeep)
            }
        }
        print(
            "BENCH first change \(layout.rawValue) wraps \(wrapsLines), \(rows) rows: "
                + "opening near the top \(Self.summary(samples.nearOpening)), "
                + "near the end \(Self.summary(samples.deepOpening)); "
                + "leaving near the top \(Self.summary(samples.nearLeaving)), "
                + "near the end \(Self.summary(samples.deepLeaving))")
    }

    /// Milliseconds per opening and per leaving, by where the change was.
    private struct Samples {
        var nearOpening: [Double] = []
        var deepOpening: [Double] = []
        var nearLeaving: [Double] = []
        var deepLeaving: [Double] = []

        mutating func append(opening: Double, leaving: Double, isDeep: Bool) {
            if isDeep {
                deepOpening.append(opening)
                deepLeaving.append(leaving)
            } else {
                nearOpening.append(opening)
                nearLeaving.append(leaving)
            }
        }
    }

    private static func time(_ work: () throws -> Void) rethrows -> Double {
        let start = ContinuousClock.now
        try work()
        let elapsed = start.duration(to: .now)
        return Double(elapsed.components.seconds) * 1e3 + Double(elapsed.components.attoseconds) / 1e15
    }

    /// Each pane shows the change three lines below its top, as `FilePaneScrollToRowTests` checks.
    private static func expectChangeNearTop(of sut: HostedPanes) throws {
        let row = try #require(sut.requestedRow)
        for pane in try sut.panes() {
            let below = try pane.top(ofRow: row) - pane.clip.bounds.minY
            #expect(abs(below - 3 * pane.lineHeight) < 1, "the row is \(below) below the pane's top")
        }
    }

    /// The median and the 10th to 90th percentiles, in milliseconds.
    private static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        let pick = { (fraction: Double) in sorted[Int((Double(sorted.count - 1) * fraction).rounded())] }
        return String(format: "median %.2f ms (p10 %.2f, p90 %.2f)", pick(0.5), pick(0.1), pick(0.9))
    }
}
