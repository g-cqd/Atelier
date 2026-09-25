import AppKit
import AtelierFileTree
import DiffGit
import Foundation
import Testing

@testable import DiffComparison
@testable import GitDiffViewer

/// The grouping by commit at its cap (GIT-06 step 10): 1,000 commits touching 10,000 rows of a comparison of 10,000
/// changed files, grouped off the main actor, turned into the explorer's sections, and laid into the merged sidebar's
/// outline, whose rebuild the app logs as its `explorer rebuilt` PhaseTrace line.
///
/// Each figure is the median of `GDV_BENCH_RUNS` runs (default 9) after one warm-up run: the grouping and the sections
/// as the model builds them off the main actor, the comparison the outline makes on every update to tell new sections
/// from old, and the outline's rebuild with the sections folded by default (the first view of a long range) and with
/// every section unfolded (every row in the outline).
///
/// Run in release, alone on the machine: `GDV_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter
/// CommitGroupingBenchmark`.
@MainActor
struct CommitGroupingBenchmark {
    private static let fileCount = 10_000
    private static let commitCount = 1_000
    private static let filesPerCommit = 10

    @Test(.timeLimit(.minutes(10)), .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `grouping and outline rebuild for 1,000 commits and 10,000 rows`() async throws {
        let runs = ProcessInfo.processInfo.environment["GDV_BENCH_RUNS"].flatMap(Int.init) ?? 9
        let (comparison, commits) = Self.fixture()

        var grouping: [Duration] = []
        var sections: [Duration] = []
        var built: (grouping: CommitGrouping, sections: [ExplorerSection])?
        for run in 0 ... runs {
            let started = ContinuousClock.now
            let groups = await Self.groupOffMain(comparison, commits)
            let grouped = ContinuousClock.now
            let explorer = groups.sections.map(ExplorerSection.init(group:))
            let listed = ContinuousClock.now
            built = (groups, explorer)
            guard run > 0 else { continue }
            grouping.append(grouped - started)
            sections.append(listed - grouped)
        }
        let result = try #require(built)
        #expect(result.grouping.sections.count >= Self.commitCount)
        let rows = result.sections.reduce(0) { $0 + $1.nodes.count }

        var comparing: [Duration] = []
        let copy = result.sections.map { ExplorerSection(kind: $0.kind, title: $0.title, nodes: $0.nodes) }
        for _ in 0 ..< runs {
            let started = ContinuousClock.now
            #expect(copy == result.sections)
            comparing.append(ContinuousClock.now - started)
        }

        let folded = Self.rebuildTimes(result.sections, unfolded: false, runs: runs)
        let unfolded = Self.rebuildTimes(result.sections, unfolded: true, runs: runs)

        print(
            "BENCH commit-grouping \(Self.commitCount) commits, \(rows) rows, \(Self.fileCount) files: "
                + "grouping \(Self.median(grouping)), sections \(Self.median(sections)), "
                + "section comparison \(Self.median(comparing)), "
                + "outline rebuild folded \(Self.median(folded.times)) (\(folded.rows) rows shown), "
                + "unfolded \(Self.median(unfolded.times)) (\(unfolded.rows) rows shown)")
    }

    @concurrent
    private static func groupOffMain(_ comparison: Comparison, _ commits: [GitCommitChanges]) async -> CommitGrouping {
        CommitGrouping.build(comparison: comparison, commits: commits, uncommitted: nil, isComplete: true)
    }

    /// A comparison of `fileCount` changed files, and `commitCount` commits newest first, each changing
    /// `filesPerCommit` of them, spread so that most files sit under one commit and some under several.
    private static func fixture() -> (Comparison, [GitCommitChanges]) {
        let paths = (0 ..< fileCount).map { "Sources/Module\($0 % 40)/File\($0).swift" }
        let comparison = Comparison(
            left: paths.map { SourceEntry(relativePath: $0, blobID: "old\($0)", size: 1) },
            right: paths.map { SourceEntry(relativePath: $0, blobID: "new\($0)", size: 1) }, leftSource: nil,
            rightSource: nil)
        let commits = (0 ..< commitCount).reversed()
            .map { index in
                GitCommitChanges(
                    id: String(format: "%040x", index + 1), parentIDs: [String(format: "%040x", index)],
                    authorName: "Tess", authorDate: Date(timeIntervalSince1970: TimeInterval(index)),
                    subject: "Commit \(index)",
                    changes: (0 ..< filesPerCommit)
                        .map { GitFileChange(status: .modified, path: paths[(index * 7 + $0 * 997) % fileCount]) })
            }
        return (comparison, commits)
    }

    /// The outline's rebuild of `sections` as the merged sidebar shows them, in an outline that is never on screen.
    private static func rebuildTimes(_ sections: [ExplorerSection], unfolded: Bool, runs: Int)
        -> (times: [Duration], rows: Int)
    {
        let uiState = ExplorerUIState()
        if unfolded {
            for section in sections { uiState.setCollapsed(false, ExplorerSection.selectionKey(forGroup: section.id)) }
        }
        let coordinator = FileOutlineView.Coordinator(uiState: uiState)
        // In a scroll view of a sidebar's size, as in the window, so only the rows in view get their cells.
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 800))
        let outline = KeyboardOutlineView(frame: scrollView.contentView.bounds)
        scrollView.documentView = outline
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.dataSource = coordinator
        outline.delegate = coordinator
        coordinator.outlineView = outline
        coordinator.applyPlacement(isSidebar: true, to: outline)
        var times: [Duration] = []
        for run in 0 ... runs {
            // A new value each time, as a reload hands the outline, so nothing is skipped as unchanged.
            coordinator.sections = sections.map { ExplorerSection(kind: $0.kind, title: $0.title, nodes: $0.nodes) }
            let started = ContinuousClock.now
            coordinator.rebuild(in: outline, selecting: nil)
            guard run > 0 else { continue }
            times.append(ContinuousClock.now - started)
        }
        withExtendedLifetime(scrollView) {}
        return (times, outline.numberOfRows)
    }

    private static func median(_ samples: [Duration]) -> String {
        guard !samples.isEmpty else { return "n/a" }
        let sorted = samples.sorted()
        let milliseconds =
            Double(sorted[sorted.count / 2].components.attoseconds) / 1e15
            + Double(sorted[sorted.count / 2].components.seconds) * 1_000
        return String(format: "%.1f ms", milliseconds)
    }
}
