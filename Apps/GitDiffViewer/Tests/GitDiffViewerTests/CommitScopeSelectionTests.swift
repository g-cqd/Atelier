import AemiTesting
import AtelierLSP
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// What a selection under the grouping by commit shows (GIT-06 criterion 5, D39): each commit's own change, from its
/// first parent to it, and Uncommitted Changes from `HEAD` to the working tree, read from a real repository.
@MainActor
struct CommitScopeSelectionTests {
    private let harness = ModelTestHarness()

    /// The ids of the history ``history(uncommitted:)`` builds.
    private struct History {
        let fixture: GitRepositoryFixture
        let base: String
        /// Adds a line to `f.swift`.
        let first: String
        /// Adds another line to `f.swift`.
        let second: String
        /// Adds `new.swift`, deletes `gone.swift`, and renames `old.swift` to `moved.swift` with one line changed.
        let reshape: String

        var root: URL { fixture.root }

        func ref(_ id: String) -> ComparisonSource { .gitRef(repository: root, ref: id) }
    }

    private nonisolated static let movedBefore = "alpha\nbeta\ngamma\ndelta\nepsilon\n"
    private nonisolated static let movedAfter = "alpha\nbeta\ngamma\ndelta\nEPSILON\n"

    /// A base and three commits on top of it; with `uncommitted`, `f.swift` gains a fourth line in the working tree.
    private static func history(uncommitted: Bool = false) async throws -> History {
        let ids = IDs()
        let fixture = try await GitRepositoryFixture.make { repo in
            try repo.write("f.swift", "one\n")
            try repo.write("gone.swift", "bye\n")
            try repo.write("old.swift", movedBefore)
            ids.set(0, try repo.commit("Base"))
            try repo.write("f.swift", "one\ntwo\n")
            ids.set(1, try repo.commit("Add two"))
            try repo.write("f.swift", "one\ntwo\nthree\n")
            ids.set(2, try repo.commit("Add three"))
            try repo.write("new.swift", "fresh\n")
            try repo.delete("gone.swift")
            try repo.delete("old.swift")
            try repo.write("moved.swift", movedAfter)
            ids.set(3, try repo.commit("Reshape"))
            if uncommitted { try repo.write("f.swift", "one\ntwo\nthree\nfour\n") }
        }
        return History(fixture: fixture, base: ids[0], first: ids[1], second: ids[2], reshape: ids[3])
    }

    private func makeSUT(reader: (any SourceReading)? = nil, grouping: Bool = true) -> DiffViewerModel {
        let runner = HardenedProcessRunner(pool: GitRepositoryFixture.pool)
        let sut = DiffViewerModel(
            settings: ViewerSettings(defaults: harness.scratchDefaults.defaults),
            reader: reader ?? SourceLoader(runner: runner, pool: GitRepositoryFixture.pool),
            history: CommitHistory(runner: runner, gate: GitConfigGate()), taskProvider: harness.taskProvider,
            uptime: harness.uptime.provider, clock: harness.clock)
        sut.settings.explorerPlacement = .unifiedSidebar
        sut.settings.treeStyle = .flat
        sut.settings.groupsByCommit = grouping
        return sut
    }

    private func load(_ sut: DiffViewerModel, _ left: ComparisonSource, _ right: ComparisonSource) async throws {
        sut.left.load(left, repository: nil)
        sut.right.load(right, repository: nil)
        try await harness.taskProvider.waitForAllTasks()
    }

    private func show(_ sut: DiffViewerModel, _ key: String) async throws {
        sut.select(key)
        try await harness.taskProvider.waitForAllTasks()
    }

    /// Both texts of the file shown on its own, old then new.
    private func shownTexts(_ sut: DiffViewerModel) throws -> [String] {
        let diff = try #require(sut.pipeline.prepared.first)
        return [diff.model.oldText, diff.model.newText]
    }

    /// Runs `body` over a new history, and removes it however `body` ends.
    private func withHistory(uncommitted: Bool = false, _ body: (History) async throws -> Void) async throws {
        let history = try await Self.history(uncommitted: uncommitted)
        do {
            try await body(history)
        } catch {
            await history.fixture.remove()
            throw error
        }
        await history.fixture.remove()
    }

    @Test
    func `a file changed by two commits shows each commit's own change under each, never their sum`() async throws {
        try await withHistory { history in
            let sut = makeSUT()
            try await load(sut, history.ref(history.base), history.ref(history.reshape))
            let underFirst = ExplorerSection.selectionKey(forGroup: "commit:\(history.first)", path: "f.swift")
            let underSecond = ExplorerSection.selectionKey(forGroup: "commit:\(history.second)", path: "f.swift")

            try await show(sut, underFirst)
            #expect(try shownTexts(sut) == ["one\n", "one\ntwo\n"])
            #expect(sut.rendered?.addedLines == 1)
            let firstSides = RenderPipeline.Sources(left: history.ref(history.base), right: history.ref(history.first))
            #expect(sut.pipeline.publishedSources == firstSides)
            #expect(sut.shownComparison == .current)

            try await show(sut, underSecond)
            #expect(try shownTexts(sut) == ["one\ntwo\n", "one\ntwo\nthree\n"])
            #expect(sut.rendered?.addedLines == 1)
            #expect(sut.selectionTitle(underSecond) == "f.swift · Add three · \(history.second.prefix(7))")

            sut.pin(underFirst)
            sut.pin(underSecond)
            #expect(sut.tabs.tabs.map(\.path) == [underSecond, underFirst])
        }
    }

    @Test
    func `an addition, a deletion and a rename inside one commit each show that commit's two sides`() async throws {
        try await withHistory { history in
            let sut = makeSUT()
            try await load(sut, history.ref(history.base), history.ref(history.reshape))
            let section = try #require(
                sut.commitGroup(forSelection: ExplorerSection.selectionKey(forGroup: "commit:\(history.reshape)")))
            let renamedRow = try #require(section.rows.first { $0.change?.status == .renamed })
            func key(_ path: String) -> String {
                ExplorerSection.selectionKey(forGroup: section.id, path: path)
            }

            try await show(sut, key("new.swift"))
            #expect(try shownTexts(sut) == ["", "fresh\n"])
            #expect(sut.changeSummary(for: "new.swift", rendered: sut.rendered).kind == .added)

            try await show(sut, key("gone.swift"))
            #expect(try shownTexts(sut) == ["bye\n", ""])
            #expect(sut.changeSummary(for: "gone.swift", rendered: sut.rendered).kind == .deleted)

            try await show(sut, key(renamedRow.path))
            #expect(try shownTexts(sut) == [Self.movedBefore, Self.movedAfter])
            #expect(sut.cardLabel(for: "moved.swift").text == "moved.swift \(CardPathLabel.arrow) old.swift")
            #expect(sut.filePath(forSelection: key(renamedRow.path)) == "moved.swift")
        }
    }

    @Test
    func `Uncommitted Changes shows HEAD against the working tree`() async throws {
        try await withHistory(uncommitted: true) { history in
            let sut = makeSUT()
            let workingTree = ComparisonSource.directory(history.root)
            try await load(sut, history.ref(history.base), workingTree)

            try await show(sut, ExplorerSection.selectionKey(forGroup: "uncommitted", path: "f.swift"))

            #expect(try shownTexts(sut) == ["one\ntwo\nthree\n", "one\ntwo\nthree\nfour\n"])
            let sides = RenderPipeline.Sources(left: history.ref(history.reshape), right: workingTree)
            #expect(sut.pipeline.publishedSources == sides)
            #expect(sut.rendered?.addedLines == 1)
        }
    }

    @Test
    func `a commit's own change never asks a language server, while Uncommitted Changes on disk does`()
        async throws
    {
        try await withHistory(uncommitted: true) { history in
            let sut = makeSUT()
            let asked = Mutex(0)
            sut.attachHoverDocs(
                lspRegistry: LanguageServerRegistry(
                    admits: { _, _ in true },
                    makeConfiguration: { _, _ in
                        asked.withLock { $0 += 1 }
                        return nil
                    }))
            try await load(sut, history.ref(history.base), .directory(history.root))

            try await show(sut, ExplorerSection.selectionKey(forGroup: "commit:\(history.second)", path: "f.swift"))
            _ = await sut.hoverDocs?.hover(fileIndex: 0, side: .new, line: 2, utf16Column: 1)
            #expect(asked.withLock { $0 } == 0)

            try await show(sut, ExplorerSection.selectionKey(forGroup: "uncommitted", path: "f.swift"))
            _ = await sut.hoverDocs?.hover(fileIndex: 0, side: .new, line: 3, utf16Column: 1)
            #expect(asked.withLock { $0 } == 1)
        }
    }

    @Test
    func `a commit section's tab shows that commit's own files, and a double click pins it`() async throws {
        try await withHistory { history in
            let sut = makeSUT()
            try await load(sut, history.ref(history.base), history.ref(history.reshape))
            let key = ExplorerSection.selectionKey(forGroup: "commit:\(history.reshape)")

            try await show(sut, key)
            #expect(sut.isShowingCombinedFiles)
            #expect(sut.combinedFiles == ["gone.swift", "new.swift", "moved.swift"])
            #expect(sut.pipeline.prepared.map(\.model.newText) == ["", "fresh\n", Self.movedAfter])
            #expect(sut.selectionLabel(key) == "Reshape · \(history.reshape.prefix(7))")

            sut.pin(key)
            #expect(sut.tabs.tabs.map(\.path) == [key])
            #expect(sut.tabs.tabs.first?.isPinned == true)
        }
    }

    @Test
    func `a file selected under another section shows that one, and the first one's late result is dropped`()
        async throws
    {
        try await withHistory { history in
            let runner = HardenedProcessRunner(pool: GitRepositoryFixture.pool)
            let loader = SourceLoader(runner: runner, pool: GitRepositoryFixture.pool)
            let reader = HoldingSourceReader(base: loader, holding: history.ref(history.first))
            let sut = makeSUT(reader: reader)
            try await load(sut, history.ref(history.base), history.ref(history.reshape))
            let first = ExplorerSection.selectionKey(forGroup: "commit:\(history.first)", path: "f.swift")
            let later = ExplorerSection.selectionKey(forGroup: "commit:\(history.reshape)", path: "new.swift")

            sut.select(first)
            _ = try await reader.held.expectNext()
            sut.select(later)
            reader.release.open()
            try await harness.taskProvider.waitForAllTasks()

            #expect(sut.selectedPath == later)
            #expect(sut.pipeline.target?.pairs.map(\.path) == ["new.swift"])
            #expect(try shownTexts(sut) == ["", "fresh\n"])
            #expect(sut.pipeline.publishedSources?.right == history.ref(history.reshape))
        }
    }

    @Test
    func `with grouping off a file shows the comparison's own diff, as before`() async throws {
        try await withHistory { history in
            let sut = makeSUT(grouping: false)
            try await load(sut, history.ref(history.base), history.ref(history.reshape))

            try await show(sut, "f.swift")

            #expect(sut.commitScope == nil)
            #expect(try shownTexts(sut) == ["one\n", "one\ntwo\nthree\n"])
            #expect(sut.rendered?.addedLines == 2)
            #expect(sut.pipeline.target == .file(sut.comparison.pair(for: "f.swift")))
            let sides = RenderPipeline.Sources(left: history.ref(history.base), right: history.ref(history.reshape))
            #expect(sut.pipeline.publishedSources == sides)
        }
    }
}

/// Commit ids a fixture's build records from its pool thread.
private final class IDs: Sendable {
    private let ids = Mutex<[Int: String]>([:])

    func set(_ index: Int, _ id: String) {
        ids.withLock { $0[index] = id }
    }

    subscript(index: Int) -> String {
        ids.withLock { $0[index] ?? "" }
    }
}
