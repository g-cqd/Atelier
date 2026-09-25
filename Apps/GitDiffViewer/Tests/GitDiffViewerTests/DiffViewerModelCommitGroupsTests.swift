import AemiCore
import AemiTesting
import AtelierFileTree
import AtelierTestSupport
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit

/// A linear history `c0` … `cN` that git is scripted to answer from: refs, ancestry, pages of `log` and counts. Commit
/// `ci` changes `a.swift` and adds `file<i>.swift`; the working tree has `a.swift` changed and `new.swift` untracked.
final class ScriptedHistory: Sendable {
    let length: Int
    private let refs: Mutex<[String: String]>
    private let diverged: Bool
    private let logRanges = Mutex<[String]>([])
    private static let commands: Set<String> = ["rev-parse", "merge-base", "log", "rev-list", "diff", "ls-files"]

    init(length: Int, refs: [String: String] = [:], diverged: Bool = false) {
        self.length = length
        self.refs = Mutex(
            ["main": "c0", "feature": "c\(length)", "HEAD": "c\(length)"].merging(refs) { _, new in new })
        self.diverged = diverged
    }

    /// Points `ref` at another commit, as a commit on a branch does.
    func move(_ ref: String, to id: String) {
        refs.withLock { $0[ref] = id }
    }

    /// The ranges `log` was asked for, in order.
    var listedRanges: [String] { logRanges.withLock { $0 } }

    private func index(_ id: String) -> Int? { Int(id.dropFirst()) }

    func answer(_ spec: ProcessSpec) -> ProcessOutput {
        let arguments = Array(spec.arguments.drop(while: { !Self.commands.contains($0) }))
        switch arguments.first {
            case "rev-parse":
                let ref = String(arguments.last?.dropLast("^{commit}".count) ?? "")
                return refs.withLock { $0[ref] }.map { .success("\($0)\n") }
                    ?? .failure(128, error: "fatal: bad revision")
            case "merge-base" where arguments.contains("--is-ancestor"):
                let (a, b) = (arguments[arguments.count - 2], arguments[arguments.count - 1])
                if diverged, a != b { return .failure(1, error: "") }
                guard let from = index(a), let to = index(b) else { return .failure(128, error: "fatal: bad object") }
                return from <= to ? .success("") : .failure(1, error: "")
            case "merge-base":
                return .success("c0\n")
            case "rev-list":
                let ends = arguments.last?.components(separatedBy: "..") ?? []
                return .success("\((index(ends[1]) ?? 0) - (index(ends[0]) ?? 0))\n")
            case "log":
                return log(arguments)
            case "diff":
                return .success(
                    ":100644 100644 \(String(repeating: "a", count: 40)) \(String(repeating: "0", count: 40)) M\0a.swift\0"
                )
            case "ls-files":
                return .success("new.swift\0")
            default:
                return .failure(128, error: "unscripted: \(arguments)")
        }
    }

    private func log(_ arguments: [String]) -> ProcessOutput {
        guard let range = arguments.dropLast().last, let limitIndex = arguments.firstIndex(of: "-n"),
            let limit = Int(arguments[limitIndex + 1])
        else { return .failure(128, error: "bad log") }
        logRanges.withLock { $0.append(range) }
        let ends = range.components(separatedBy: "..")
        guard let from = index(ends[0]), let to = index(ends[1]) else { return .failure(128, error: "bad range") }
        var output = ""
        for number in stride(from: to, to: max(from, to - limit), by: -1) {
            let blob = String(repeating: "b", count: 40)
            output +=
                "\u{1e}c\(number)\0c\(number - 1)\0\(1_790_000_000 + number)\0Tess\0Commit \(number)\0"
                + "\n:100644 100644 \(blob) \(blob) M\0a.swift\0"
                + ":000000 100644 \(String(repeating: "0", count: 40)) \(blob) A\0file\(number).swift\0"
        }
        return .success(output)
    }
}

/// `DiffViewerModel`'s grouping by commit: when it loads, what it asks git, how it pages, and what it keeps.
@MainActor
struct DiffViewerModelCommitGroupsTests {
    private let harness = ModelTestHarness()
    private static let repository = URL(filePath: "/repo", directoryHint: .isDirectory)
    private static let main = ComparisonSource.gitRef(repository: repository, ref: "main")
    private static let feature = ComparisonSource.gitRef(repository: repository, ref: "feature")
    private static let workingTree = ComparisonSource.directory(repository)

    private func makeSUT(_ history: ScriptedHistory, grouping: Bool = true) -> (DiffViewerModel, FakeProcessRunner) {
        let runner = FakeProcessRunner.gated { history.answer($0) }
        let sut = DiffViewerModel(
            settings: ViewerSettings(defaults: harness.scratchDefaults.defaults), reader: harness.reader,
            history: CommitHistory(runner: runner, gate: GitConfigGate()), taskProvider: harness.taskProvider,
            uptime: harness.uptime.provider, clock: harness.clock)
        sut.settings.explorerPlacement = .unifiedSidebar
        sut.settings.treeStyle = .flat
        sut.settings.groupsByCommit = grouping
        return (sut, runner)
    }

    /// Both ends of `history`: `a.swift` changed and every `file<i>.swift` added.
    private func serve(_ history: ScriptedHistory, right: ComparisonSource = feature) {
        harness.reader.entries[Self.main] = [harness.entry("a.swift", "1")]
        harness.reader.entries[right] =
            [harness.entry("a.swift", "2")]
            + (1 ... max(1, history.length)).map { harness.entry("file\($0).swift", "f\($0)") }
    }

    private func load(_ sut: DiffViewerModel, right: ComparisonSource = feature) async throws {
        sut.left.load(Self.main, repository: nil)
        sut.right.load(right, repository: nil)
        try await harness.taskProvider.waitForAllTasks()
    }

    private func logSpecs(_ runner: FakeProcessRunner) -> [ProcessSpec] {
        runner.commandSpecs.filter { $0.arguments.contains("log") }
    }

    @Test
    func `with the setting off nothing is asked of git and the list stays plain`() async throws {
        let history = ScriptedHistory(length: 3)
        let (sut, runner) = makeSUT(history, grouping: false)
        serve(history)

        try await load(sut)

        #expect(sut.commitGroups == .off)
        #expect(runner.commandSpecs.isEmpty)
        #expect(sut.unifiedSections.map(\.id) == ["changes"])
    }

    @Test
    func `two refs of one history group newest first, each commit with its own files`() async throws {
        let history = ScriptedHistory(length: 3)
        let (sut, _) = makeSUT(history)
        serve(history)

        try await load(sut)

        #expect(
            sut.commitGroups.eligibility
                == .applies(
                    CommitGroupingRange(
                        repository: Self.repository, base: "main", tip: "feature", includesWorkingTree: false)))
        #expect(sut.unifiedSections.map(\.id) == ["commit:c3", "commit:c2", "commit:c1"])
        #expect(sut.unifiedSections.first?.nodes.map(\.id) == ["a.swift", "file3.swift"])
        #expect(sut.unifiedSections.first?.title == "Commit 3")
        #expect(!sut.commitGroups.isUpdating)
    }

    @Test
    func `a long range loads in pages of 200, each continuing from the last page's oldest first parent`() async throws {
        let history = ScriptedHistory(length: 450)
        let (sut, runner) = makeSUT(history)
        serve(history)

        try await load(sut)

        #expect(history.listedRanges == ["c0..c450", "c0..c250", "c0..c50"])
        #expect(logSpecs(runner).allSatisfy { $0.arguments.contains("--first-parent") })
        #expect(sut.commitGroups.grouping?.sections.count == 450)
        #expect(!sut.unifiedSections.contains { $0.id == "earlier" })
    }

    @Test
    func `past the cap the rest of the range is counted into Earlier Changes`() async throws {
        let history = ScriptedHistory(length: 1_300)
        let (sut, runner) = makeSUT(history)
        serve(history)

        try await load(sut)

        #expect(history.listedRanges.count == 5)
        #expect(runner.commandSpecs.contains { $0.arguments.contains("rev-list") })
        let earlier = try #require(sut.commitGroups.grouping?.sections.last)
        #expect(earlier.kind == .earlier(unlistedCommitCount: 300))
        #expect(earlier.rows.count == 300)
        #expect(sut.commitGroups.grouping?.sections.count == 1_001)
    }

    @Test
    func `a reload of the same range lists no commit again`() async throws {
        let history = ScriptedHistory(length: 3)
        let (sut, _) = makeSUT(history)
        serve(history)
        try await load(sut)

        sut.reloadSources()
        try await harness.taskProvider.waitForAllTasks()

        #expect(history.listedRanges == ["c0..c3"])
        #expect(sut.unifiedSections.map(\.id) == ["commit:c3", "commit:c2", "commit:c1"])
    }

    @Test
    func `a right side moved forward lists only its new commits and puts them on top`() async throws {
        let history = ScriptedHistory(length: 5, refs: ["feature": "c3"])
        let (sut, _) = makeSUT(history)
        serve(history)
        try await load(sut)

        history.move("feature", to: "c5")
        sut.reloadSources()
        try await harness.taskProvider.waitForAllTasks()

        #expect(history.listedRanges == ["c0..c3", "c3..c5"])
        #expect(sut.unifiedSections.map(\.id) == (1 ... 5).reversed().map { "commit:c\($0)" })
    }

    @Test
    func `the working tree on the right puts Uncommitted Changes first`() async throws {
        let history = ScriptedHistory(length: 2)
        let (sut, _) = makeSUT(history)
        serve(history, right: Self.workingTree)
        harness.reader.entries[Self.workingTree]?.append(harness.entry("new.swift", "n"))

        try await load(sut, right: Self.workingTree)

        #expect(sut.unifiedSections.map(\.id) == ["uncommitted", "commit:c2", "commit:c1"])
        #expect(sut.unifiedSections.first?.nodes.map(\.id) == ["a.swift", "new.swift"])
    }

    @Test
    func `diverged sides stay ungrouped and offer the merge base`() async throws {
        let history = ScriptedHistory(length: 2, diverged: true)
        let (sut, runner) = makeSUT(history)
        serve(history)

        try await load(sut)

        #expect(sut.commitGroups.eligibility?.ineligibility == .diverged(base: "main", tip: "feature", mergeBase: "c0"))
        #expect(sut.commitGroups.unavailableReason == "main is not an ancestor of feature.")
        #expect(logSpecs(runner).isEmpty)
        #expect(sut.unifiedSections.map(\.id) == ["changes"])
    }

    @Test
    func `outside the merged sidebar's flat list no git runs and the reason is given`() async throws {
        let history = ScriptedHistory(length: 2)
        let (sut, runner) = makeSUT(history)
        sut.settings.treeStyle = .hierarchy
        serve(history)

        try await load(sut)

        #expect(sut.commitGroups.eligibility == .doesNotApply(.needsFlatList))
        #expect(runner.commandSpecs.isEmpty)
    }

    @Test
    func `turning the setting on groups, and off drops the groups`() async throws {
        let history = ScriptedHistory(length: 2)
        let (sut, _) = makeSUT(history, grouping: false)
        serve(history)
        try await load(sut)

        sut.settings.groupsByCommit = true
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.unifiedSections.map(\.id) == ["commit:c2", "commit:c1"])

        sut.settings.groupsByCommit = false
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.commitGroups == .off)
        #expect(sut.unifiedSections.map(\.id) == ["changes"])
    }

    @Test
    func `an unrelated setting change runs no git`() async throws {
        let history = ScriptedHistory(length: 2)
        let (sut, runner) = makeSUT(history)
        serve(history)
        try await load(sut)
        let before = runner.commandSpecs.count

        sut.settings.showsChangesOnly = true
        sut.settings.wrapsLines = false
        try await harness.taskProvider.waitForAllTasks()

        #expect(runner.commandSpecs.count == before)
    }

    // MARK: Selecting a section (step 8)

    @Test
    func `selecting a commit section opens its own change in the temporary tab, titled by its subject and id`()
        async throws
    {
        let history = ScriptedHistory(length: 3)
        let (sut, _) = makeSUT(history)
        serve(history)
        try await load(sut)
        let key = ExplorerSection.selectionKey(forGroup: "commit:c2")

        sut.select(key)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.tabs.activePath == key)
        #expect(sut.isShowingCombinedFiles)
        #expect(sut.combinedFiles == ["a.swift", "file2.swift"])
        #expect(
            sut.pipeline.publishedSources
                == RenderPipeline.Sources(
                    left: .gitRef(repository: Self.repository, ref: "c1"),
                    right: .gitRef(repository: Self.repository, ref: "c2")))
        #expect(sut.selectionTitle(key) == "Commit 2 · c2")
        #expect(sut.selectionLabel(key) == "Commit 2 · c2")
        #expect(sut.selectionDetail(key).contains("Tess"))
    }

    @Test
    func `a double click pins a commit section's tab`() async throws {
        let history = ScriptedHistory(length: 2)
        let (sut, _) = makeSUT(history)
        serve(history)
        try await load(sut)

        sut.pin(ExplorerSection.selectionKey(forGroup: "commit:c1"))
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.tabs.tabs.map(\.path) == [ExplorerSection.selectionKey(forGroup: "commit:c1"), "a.swift"])
        #expect(sut.tabs.tabs.first?.isPinned == true)
    }

    @Test
    func `a commit section's tab closes once grouping stops`() async throws {
        let history = ScriptedHistory(length: 2)
        let (sut, _) = makeSUT(history)
        serve(history)
        try await load(sut)
        sut.select(ExplorerSection.selectionKey(forGroup: "commit:c2"))
        try await harness.taskProvider.waitForAllTasks()

        sut.settings.groupsByCommit = false
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.tabs.tabs.isEmpty)
        #expect(sut.selectedPath == nil)
    }

    @Test
    func `a commit's menu compares its first parent with it and copies its id`() async throws {
        let history = ScriptedHistory(length: 2)
        let (sut, _) = makeSUT(history)
        serve(history)
        try await load(sut)

        let menu = sut.commitGroupMenu(forSelection: ExplorerSection.selectionKey(forGroup: "commit:c2"))

        #expect(
            menu == [
                CommitGroupMenuItem(
                    title: "Compare This Commit",
                    action: .compare(.repository(Self.repository, leftRef: "c1", rightRef: "c2"))),
                CommitGroupMenuItem(title: "Copy Commit ID", action: .copy("c2"))
            ])
        #expect(sut.commitGroupMenu(forSelection: "a.swift").isEmpty)
    }

    @Test
    func `Earlier Changes compares the left side with the oldest listed commit's first parent`() async throws {
        let history = ScriptedHistory(length: 1_300)
        let (sut, _) = makeSUT(history)
        serve(history)
        try await load(sut)

        let menu = sut.commitGroupMenu(forSelection: ExplorerSection.selectionKey(forGroup: "earlier"))

        #expect(
            menu == [
                CommitGroupMenuItem(
                    title: "Compare This Range",
                    action: .compare(.repository(Self.repository, leftRef: "main", rightRef: "c300")))
            ])
    }

    // MARK: The "doesn't apply" actions (step 9)

    @Test
    func `Use Merged Sidebar and Use Flat List set what grouping needs, and then it applies`() async throws {
        let history = ScriptedHistory(length: 2)
        let (sut, _) = makeSUT(history)
        sut.settings.explorerPlacement = .sidebar
        sut.settings.treeStyle = .compact
        serve(history)
        try await load(sut)
        #expect(sut.commitGroups.eligibility?.ineligibility?.action == .useMergedSidebar)

        sut.perform(.useMergedSidebar)
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.settings.explorerPlacement == .unifiedSidebar)
        #expect(sut.commitGroups.eligibility?.ineligibility?.action == .useFlatList)

        sut.perform(.useFlatList)
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.settings.treeStyle == .flat)
        #expect(sut.unifiedSections.map(\.id) == ["commit:c2", "commit:c1"])
    }

    @Test
    func `Swap Sides puts the older state on the left`() async throws {
        let history = ScriptedHistory(length: 2)
        let (sut, _) = makeSUT(history)
        serve(history)
        sut.left.load(Self.feature, repository: nil)
        sut.right.load(Self.main, repository: nil)
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.commitGroups.eligibility?.ineligibility == .newerStateOnLeft)

        sut.perform(.swapSides)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.left.source == Self.main)
        #expect(sut.unifiedSections.map(\.id) == ["commit:c2", "commit:c1"])
    }

    @Test
    func `Compare from Merge Base moves the left side to the merge base's commit`() async throws {
        let history = ScriptedHistory(length: 2, diverged: true)
        let (sut, _) = makeSUT(history)
        serve(history)
        try await load(sut)
        let action = try #require(sut.commitGroups.eligibility?.ineligibility?.action)

        sut.perform(action)
        try await harness.taskProvider.waitForAllTasks()

        #expect(action == .compareFromMergeBase("c0"))
        #expect(sut.left.source == .gitRef(repository: Self.repository, ref: "c0"))
    }
}
