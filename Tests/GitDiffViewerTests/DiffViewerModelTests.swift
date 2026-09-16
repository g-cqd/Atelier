import DiffConcurrency
import DiffCore
import DiffTestSupport
import Foundation
@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit
import Synchronization
import Testing

@MainActor
struct DiffViewerModelTests {
    private let taskProvider = TaskProviderSpy()
    private let reader = FakeSourceReader()
    private let uptime = FakeUptime()

    @Test
    func `statuses compare blob ids and report files present on one side only`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1"), entry("b.swift", "2"), entry("only-left.swift", "3")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "1"), entry("b.swift", "9"), entry("only-right.swift", "4")]

        try await load(sut)

        #expect(sut.status(of: "a.swift", in: .left) == .same)
        #expect(sut.status(of: "b.swift", in: .left) == .different)
        #expect(sut.status(of: "only-left.swift", in: .left) == .onlyLeft)
        #expect(sut.status(of: "only-right.swift", in: .right) == .onlyRight)
        #expect(sut.changedPathCount == 3)
    }

    @Test
    func `with nothing selected every changed file is rendered one after another`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("z/same.swift", "1"), entry("a/changed.swift", "2"), entry("b.swift", "3")]
        reader.entries[.directory(Self.rightURL)] = [entry("z/same.swift", "1"), entry("a/changed.swift", "8"), entry("b.swift", "4")]

        try await load(sut)

        #expect(sut.selectedPath == nil)
        #expect(sut.isShowingCombinedFiles)
        #expect(sut.combinedFiles == ["a/changed.swift", "b.swift"])
        #expect(sut.renderedFiles.map(\.path) == ["a/changed.swift", "b.swift"])
        #expect(sut.renderedFiles.allSatisfy { $0.rendered.old?.rows.allSatisfy { $0.kind != .header } == true })
        var requests: [String] = []
        for _ in 0..<4 { requests.append(try #require(try await reader.contentRequests.next())) }
        #expect(requests.sorted() == ["a/changed.swift", "a/changed.swift", "b.swift", "b.swift"])
        try reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `cards fold per file, all at once, and unfold when the sources change`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1"), entry("b.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "8"), entry("b.swift", "9")]
        try await load(sut)

        sut.toggleCollapsed("a.swift")
        #expect(sut.collapsedFiles == ["a.swift"])
        sut.toggleCollapsed("a.swift")
        #expect(sut.collapsedFiles.isEmpty)
        sut.setAllCollapsed(true)
        #expect(sut.collapsedFiles == ["a.swift", "b.swift"])

        sut.sourcesChanged()
        #expect(sut.collapsedFiles.isEmpty)
    }

    @Test
    func `added and deleted files start folded in the card list`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("gone.swift", "1"), entry("kept.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("kept.swift", "3"), entry("new.swift", "4")]

        try await load(sut)

        #expect(sut.renderedFiles.map(\.path) == ["gone.swift", "kept.swift", "new.swift"])
        #expect(sut.collapsedFiles == ["gone.swift", "new.swift"])

        sut.toggleCollapsed("gone.swift")
        sut.relayout()
        try await taskProvider.waitForAllTasks()

        #expect(sut.collapsedFiles == ["new.swift"])
    }

    @Test
    func `a comparison is timed from the source change to the render and to the first card on screen`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1"), entry("b.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "3"), entry("b.swift", "4")]
        uptime.now = .milliseconds(100)
        sut.left.load(.directory(Self.leftURL), repository: nil)
        sut.right.load(.directory(Self.rightURL), repository: nil)
        uptime.now = .milliseconds(140)
        try await taskProvider.waitForAllTasks()

        #expect(sut.timing == RenderTiming(firstDisplay: nil, rendered: .milliseconds(40)))

        uptime.now = .milliseconds(155)
        sut.noteDisplayed(try #require(sut.renderedFiles.last?.rendered.id))
        sut.noteDisplayed(try #require(sut.renderedFiles.first?.rendered.id))
        try await taskProvider.waitForAllTasks()

        #expect(sut.timing == RenderTiming(firstDisplay: .milliseconds(55), rendered: .milliseconds(40)))
    }

    @Test
    func `a file is timed from its selection to its appearance on screen`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        try await load(sut)
        sut.select("a.swift")
        sut.settings.granularity = .character

        uptime.now = .milliseconds(200)
        sut.renderSelection()
        uptime.now = .milliseconds(230)
        try await taskProvider.waitForAllTasks()
        uptime.now = .milliseconds(245)
        sut.noteDisplayed(try #require(sut.rendered?.id))
        try await taskProvider.waitForAllTasks()

        #expect(sut.timing == RenderTiming(firstDisplay: .milliseconds(45), rendered: .milliseconds(30)))
    }

    @Test
    func `a file already compared in the card list is shown at once without reading it again`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1"), entry("b.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "3"), entry("b.swift", "4")]
        try await load(sut)
        for _ in 0..<4 { _ = try await reader.contentRequests.next() }

        sut.select("b.swift")

        #expect(sut.rendered != nil)
        #expect(sut.detailState == .file(try #require(sut.rendered)))
        #expect(sut.timing.rendered != nil)
        try await taskProvider.waitForAllTasks()
        try reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `changed files are prefetched after a selection so the next one is instant`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1"), entry("b.swift", "2"), entry("c.swift", "5")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "3"), entry("b.swift", "4"), entry("c.swift", "5")]
        sut.left.load(.directory(Self.leftURL), repository: nil)
        sut.right.load(.directory(Self.rightURL), repository: nil)
        try await taskProvider.waitForAllTasks()
        sut.select("a.swift")
        try await taskProvider.waitForAllTasks()

        var requested: [String] = []
        for _ in 0..<4 { requested.append(try #require(try await reader.contentRequests.next())) }
        #expect(requested.sorted() == ["a.swift", "a.swift", "b.swift", "b.swift"])
        try reader.contentRequests.expectNoBufferedElements()

        sut.select("b.swift")
        #expect(sut.rendered != nil)
        try await taskProvider.waitForAllTasks()
        try reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `opening a patch compares its old and new sides`() async throws {
        let sut = makeSUT()
        let url = URL(filePath: "/tmp/changes.patch")
        reader.entries[.patch(url, side: .old)] = [entry("a.swift", "1"), entry("gone.swift", "2")]
        reader.entries[.patch(url, side: .new)] = [entry("a.swift", "3"), entry("new.swift", "4")]

        sut.openPatch(url)
        try await taskProvider.waitForAllTasks()

        #expect(sut.left.source == .patch(url, side: .old))
        #expect(sut.right.source == .patch(url, side: .new))
        #expect(sut.renderedFiles.map(\.path) == ["a.swift", "gone.swift", "new.swift"])
        #expect(sut.collapsedFiles == ["gone.swift", "new.swift"])
    }

    @Test
    func `renamed files are shown under their destination path`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("old/name.swift", "1"), entry("same.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("new/name.swift", "1"), entry("same.swift", "2")]

        try await load(sut)

        #expect(sut.displayPath(for: "old/name.swift") == "new/name.swift")
        #expect(sut.displayPath(for: "same.swift") == "same.swift")
    }

    @Test
    func `selecting a folder renders only the changed files underneath it`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a/x.swift", "1"), entry("a/y.swift", "2"), entry("b/z.swift", "3")]
        reader.entries[.directory(Self.rightURL)] = [entry("a/x.swift", "1"), entry("a/y.swift", "9"), entry("b/z.swift", "9")]
        try await load(sut)

        sut.select("a")
        try await taskProvider.waitForAllTasks()

        #expect(sut.isShowingCombinedFiles)
        #expect(sut.combinedFiles == ["a/y.swift"])
        #expect(sut.renderedFiles.first?.rendered.changeCount == 1)
    }

    @Test
    func `dragging a gap reveals rows and keeps the pane where it was`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        reader.contents["a.swift"] = (1...30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try await load(sut)
        sut.settings.isolatesChanges = true
        sut.select("a.swift")
        try await taskProvider.waitForAllTasks()
        let marker = try #require(sut.rendered?.old?.rows.first?.gap)
        #expect(marker.isLeading)

        sut.adjustGap(marker, from: GapExpansion(), byLines: 4)
        try await taskProvider.waitForAllTasks()

        #expect(sut.expansion(of: marker.key) == GapExpansion(below: 0, above: 4))
        #expect(sut.rendered?.keepsScrollPosition == true)
    }

    @Test
    func `changes only filter keeps the directories leading to changed files`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("z/same.swift", "1"), entry("a/x/changed.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("z/same.swift", "1"), entry("a/x/changed.swift", "8")]
        try await load(sut)

        sut.settings.showsChangesOnly = true

        #expect(sut.leftTree.map(\.id) == ["a"])
        #expect(sut.leftTree.first?.children?.first?.children?.map(\.id) == ["a/x/changed.swift"])
    }

    @Test
    func `two single files compare with each other whatever their names`() async throws {
        let sut = makeSUT()
        let left = ComparisonSource.file(Self.leftURL.appending(path: "old.txt"))
        let right = ComparisonSource.file(Self.rightURL.appending(path: "new.txt"))
        reader.entries[left] = [entry("old.txt", "1")]
        reader.entries[right] = [entry("new.txt", "2")]
        reader.contents["old.txt"] = "one\ntwo\n"
        reader.contents["new.txt"] = "one\ntwo!\n"

        sut.left.load(left, repository: nil)
        sut.right.load(right, repository: nil)
        try await taskProvider.waitForAllTasks()

        #expect(sut.status(of: "old.txt", in: .left) == .different)
        #expect(sut.status(of: "new.txt", in: .right) == .different)
        #expect(sut.rendered?.changeCount == 1)
        #expect(sut.rendered?.old?.rows.map(\.kind) == [.context, .removed])
        #expect(sut.rendered?.new?.rows.map(\.kind) == [.context, .added])
        #expect(sut.rendered?.unified == nil)
    }

    @Test
    func `changing the granularity re-renders the current selection`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        reader.contents["a.swift"] = "let value = count\n"
        try await load(sut)
        sut.select("a.swift")
        try await taskProvider.waitForAllTasks()
        let before = try #require(sut.rendered?.old?.id)

        sut.settings.granularity = .syntax
        try await taskProvider.waitForAllTasks()

        #expect(sut.rendered?.old?.id != before)
        #expect(sut.rendered != nil)
    }

    @Test
    func `the detail state follows loading, selection and results`() async throws {
        let sut = makeSUT()
        #expect(sut.detailState == .noSources)

        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "1")]
        try await load(sut)
        #expect(sut.detailState == .noChanges)

        sut.select("a.swift")
        try await taskProvider.waitForAllTasks()
        if case .file = sut.detailState {} else { Issue.record("expected a rendered file, got \(sut.detailState)") }

        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        sut.right.reload()
        try await taskProvider.waitForAllTasks()
        if case .file = sut.detailState {} else { Issue.record("expected the changed file, got \(sut.detailState)") }
        sut.select(nil)
        try await taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
    }

    @Test
    func `a re-layout while cards are still streaming keeps the remaining cards coming`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1"), entry("b.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "3"), entry("b.swift", "4")]
        reader.gate["b.swift"] = AsyncProbe<Void>()
        sut.left.load(.directory(Self.leftURL), repository: nil)
        sut.right.load(.directory(Self.rightURL), repository: nil)
        try await taskProvider.waitForSpawnedTasks(atLeast: 3)
        for _ in 0..<4 { _ = try await reader.contentRequests.next() }
        #expect(sut.renderedFiles.map(\.path) == ["a.swift"])
        #expect(sut.isRendering)

        sut.settings.mode = .inline
        reader.gate["b.swift"]?.send(())
        reader.gate["b.swift"]?.send(())
        try await taskProvider.waitForAllTasks()

        #expect(sut.renderedFiles.map(\.path) == ["a.swift", "b.swift"])
        #expect(sut.renderedFiles.allSatisfy { $0.rendered.unified != nil })
        #expect(!sut.isRendering)
    }

    @Test
    func `a render finishing during a reload is not shown as current`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        try await load(sut)
        reader.gate["a.swift"] = AsyncProbe<Void>()
        sut.settings.granularity = .character
        try await taskProvider.waitForSpawnedTasks(atLeast: 1)
        _ = try await reader.contentRequests.next()

        reader.gate["/right"] = AsyncProbe<Void>()
        sut.right.reload()
        reader.gate["a.swift"]?.send(())
        reader.gate["a.swift"]?.send(())
        try await taskProvider.waitForSpawnedTasks(atLeast: 1)

        #expect(sut.detailState == .loading)
        reader.gate["/right"]?.send(())
        try await taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
    }

    @Test
    func `a new selection cancels the prefetch of the previous one`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1"), entry("b.swift", "2"), entry("c.swift", "3")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "4"), entry("b.swift", "5"), entry("c.swift", "6")]
        sut.left.load(.directory(Self.leftURL), repository: nil)
        sut.right.load(.directory(Self.rightURL), repository: nil)
        try await taskProvider.waitForAllTasks()
        for _ in 0..<6 { _ = try await reader.contentRequests.next() }
        reader.gate["c.swift"] = AsyncProbe<Void>()
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "4"), entry("b.swift", "5"), entry("c.swift", "7")]
        sut.right.reload()
        try await taskProvider.waitForSpawnedTasks(atLeast: 2)
        for _ in 0..<2 { _ = try await reader.contentRequests.next() }
        try reader.contentRequests.expectNoBufferedElements()

        sut.select("a.swift")
        #expect(sut.rendered != nil)
        reader.gate["c.swift"]?.send(())
        reader.gate["c.swift"]?.send(())
        try await taskProvider.waitForAllTasks()

        #expect(sut.renderedFiles.isEmpty)
        try reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `changing a setting recomputes only what it affects`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("z/same.swift", "1"), entry("a/changed.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("z/same.swift", "1"), entry("a/changed.swift", "8")]
        try await load(sut)
        for _ in 0..<2 { _ = try await reader.contentRequests.next() }
        let firstRender = try #require(sut.renderedFiles.first?.rendered.id)

        sut.settings.showsChangesOnly = true
        #expect(sut.leftTree.map(\.id) == ["a"])
        #expect(sut.renderedFiles.first?.rendered.id == firstRender)

        sut.settings.contextLines = 1
        try await taskProvider.waitForAllTasks()
        #expect(sut.renderedFiles.first?.rendered.id != firstRender)
        try reader.contentRequests.expectNoBufferedElements()

        sut.settings.granularity = .character
        try await taskProvider.waitForAllTasks()
        for _ in 0..<2 { _ = try await reader.contentRequests.next() }
        try reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `changing a diff heuristic re-diffs the selection with the new pipeline`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        try await load(sut)
        for _ in 0..<2 { _ = try await reader.contentRequests.next() }
        let before = try #require(sut.renderedFiles.first?.rendered.id)

        sut.settings.diffHeuristics.whitespace = .ignoreAll
        try await taskProvider.waitForAllTasks()

        #expect(sut.renderedFiles.first?.rendered.id != before)
        for _ in 0..<2 { _ = try await reader.contentRequests.next() }
        try reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `selecting opens a temporary tab, pinning keeps it, and closing the last tab shows every file`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1"), entry("b.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "3"), entry("b.swift", "4")]
        try await load(sut)

        sut.select("a.swift")
        sut.select("b.swift")
        #expect(sut.tabs.tabs.map(\.path) == ["b.swift"])
        #expect(sut.selectedPath == "b.swift")

        sut.pin("a.swift")
        #expect(sut.tabs.tabs.map(\.path) == ["b.swift", "a.swift"])
        #expect(sut.selectedPath == "a.swift")

        for tab in sut.tabs.tabs { sut.closeTab(tab.id) }
        try await taskProvider.waitForAllTasks()
        #expect(sut.selectedPath == nil)
        #expect(sut.detailState == .cards)
    }

    @Test
    func `opening a file focuses its first change`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        try await load(sut)

        sut.select("a.swift")
        try await taskProvider.waitForAllTasks()

        #expect(sut.currentChange == 1)
        #expect(sut.scrollRequest?.row == sut.rendered?.splitChangeStarts.first)
    }

    @Test
    func `only the sides of the current layout are rendered`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        try await load(sut)
        sut.select("a.swift")
        try await taskProvider.waitForAllTasks()
        #expect(sut.rendered?.unified == nil)
        #expect(sut.rendered?.old != nil)

        sut.settings.mode = .inline
        try await taskProvider.waitForAllTasks()
        #expect(sut.rendered?.unified != nil)
        #expect(sut.rendered?.old == nil)
    }

    @Test
    func `a selection made while the previous one is still loading discards the stale result`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("slow.swift", "1"), entry("fast.swift", "3")]
        reader.entries[.directory(Self.rightURL)] = [entry("slow.swift", "2"), entry("fast.swift", "4")]
        try await load(sut)
        reader.gate["slow.swift"] = AsyncProbe<Void>()

        sut.select("slow.swift")
        try await taskProvider.waitForSpawnedTasks(atLeast: 1)
        sut.select("fast.swift")
        reader.gate["slow.swift"]?.send(())
        reader.gate["slow.swift"]?.send(())
        try await taskProvider.waitForAllTasks()

        #expect(sut.selectedPath == "fast.swift")
        #expect(sut.rendered?.old?.rows.contains { $0.kind == .removed } == true)
        #expect(sut.rendered?.old?.attributed.string.contains("fast.swift") == true)
    }

    @Test
    func `nothing renders while a side is still loading`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        reader.gate["/right"] = AsyncProbe<Void>()

        sut.left.load(.directory(Self.leftURL), repository: nil)
        sut.right.load(.directory(Self.rightURL), repository: nil)
        try await taskProvider.waitForSpawnedTasks(atLeast: 2)
        sut.sourcesChanged()
        #expect(sut.detailState == .loading)
        #expect(sut.renderedFiles.isEmpty)
        #expect(sut.leftTree.isEmpty)
        #expect(sut.statuses.isEmpty)

        reader.gate["/right"]?.send(())
        try await taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
    }

    @Test
    func `a file moved without changes is a rename and its sides compare with each other`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("old/name.swift", "1"), entry("keep.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("new/name.swift", "1"), entry("keep.swift", "2")]

        try await load(sut)

        #expect(sut.renames == ["old/name.swift": "new/name.swift"])
        #expect(sut.status(ofPath: "old/name.swift") == .renamed)
        #expect(sut.status(of: "new/name.swift", in: .right) == .renamed)
        #expect(sut.counterpartPath(of: "new/name.swift", in: .right) == "old/name.swift")
        #expect(sut.changeSummary(for: "old/name.swift", rendered: nil).kind == .renamed(to: "new/name.swift"))
        #expect(sut.combinedFiles == ["old/name.swift"])
    }

    @Test
    func `renames reported by git pair changed files across paths`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("b.swift", "2")]
        reader.contents["a.swift"] = "one\ntwo\n"
        reader.contents["b.swift"] = "one\nthree\n"
        reader.gitRenames = ["a.swift": "b.swift"]

        try await load(sut)

        #expect(sut.status(ofPath: "a.swift") == .renamed)
        #expect(sut.isRenamedWithChanges("a.swift"))
        let summary = sut.changeSummary(for: "a.swift", rendered: sut.renderedFiles.first?.rendered)
        #expect(summary == FileChangeSummary(kind: .renamed(to: "b.swift"), addedLines: 1, removedLines: 1))
    }

    @Test
    func `badges classify added deleted and modified files with line counts`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("gone.swift", "1"), entry("changed.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("new.swift", "3"), entry("changed.swift", "9")]
        try await load(sut)

        #expect(sut.changeSummary(for: "gone.swift", rendered: nil).kind == .deleted)
        #expect(sut.changeSummary(for: "new.swift", rendered: nil).kind == .added)
        let changed = try #require(sut.renderedFiles.first { $0.path == "changed.swift" })
        let summary = sut.changeSummary(for: "changed.swift", rendered: changed.rendered)
        #expect(summary.kind == .modified)
        #expect(summary.addedLines == 1)
        #expect(summary.removedLines == 1)
    }

    // MARK: Helpers

    private static let leftURL = URL(filePath: "/left", directoryHint: .isDirectory)
    private static let rightURL = URL(filePath: "/right", directoryHint: .isDirectory)

    @Test
    func `compact folders folds single child chains after the changed files filter`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a/b/c/changed.swift", "1"), entry("a/other.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("a/b/c/changed.swift", "9"), entry("a/other.swift", "2")]
        try await load(sut)

        sut.settings.showsChangesOnly = true
        sut.settings.treeStyle = .compact

        #expect(sut.leftTree.map(\.name) == ["a/b/c"])
        #expect(sut.leftTree.first?.children?.map(\.id) == ["a/b/c/changed.swift"])
    }

    @Test
    func `the flat style lists every file by its full path without folders`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("b/z.swift", "1"), entry("a/x/y.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("b/z.swift", "1"), entry("a/x/y.swift", "3")]
        try await load(sut)

        sut.settings.treeStyle = .flat

        #expect(sut.leftTree.map(\.id) == ["a/x/y.swift", "b/z.swift"])
        #expect(sut.leftTree.map(\.name) == ["y.swift", "z.swift"])
        #expect(sut.leftTree.allSatisfy { !$0.isDirectory })
    }

    @Test
    func `ignored files form a section of their own only when shown, and diff as added`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]
        reader.entries[.directory(Self.rightURL)] = [entry("a.swift", "2")]
        reader.ignored[.directory(Self.rightURL)] = [SourceEntry(relativePath: "build/out.txt", blobID: nil, size: 0)]
        try await load(sut)

        #expect(sut.unifiedSections.map(\.kind) == [.changes])
        #expect(sut.right.ignoredEntries == nil)
        #expect(sut.changedPathCount == 1)

        sut.settings.showsIgnoredFiles = true
        try await taskProvider.waitForAllTasks()

        #expect(sut.unifiedSections.map(\.kind) == [.changes, .ignored])
        #expect(sut.unifiedSections[1].nodes.flatMap(\.filePaths) == ["build/out.txt"])
        #expect(sut.rightSections[1].nodes.flatMap(\.filePaths) == ["build/out.txt"])
        #expect(sut.leftSections[1].nodes.isEmpty)
        #expect(sut.unifiedSections[0].nodes.flatMap(\.filePaths) == ["a.swift"])
        #expect(sut.changedPathCount == 1)
        #expect(sut.status(ofPath: "build/out.txt") == nil)

        sut.select("build/out.txt", from: .right)
        try await taskProvider.waitForAllTasks()

        #expect(sut.selectedPath == "build/out.txt")
        #expect(sut.changeSummary(for: "build/out.txt", rendered: sut.rendered).kind == .added)
        #expect(sut.rendered?.addedLines == 1)

        sut.settings.showsIgnoredFiles = false
        #expect(sut.unifiedSections.map(\.kind) == [.changes])
    }

    @Test
    func `a folder chosen while the other side is empty puts that side on the same repository without a source`() async throws {
        let sut = makeSUT()
        let info = RepositoryInfo(root: Self.leftURL, branches: ["main", "feature"], tags: [], commits: [])
        reader.repositories[Self.leftURL] = info
        reader.entries[.directory(Self.leftURL)] = [entry("a.swift", "1")]

        sut.left.choose(Self.leftURL)
        try await taskProvider.waitForAllTasks()

        #expect(sut.left.source == .directory(Self.leftURL))
        #expect(sut.right.repository == info)
        #expect(sut.right.source == nil)
        #expect(sut.detailState == .noSources)

        reader.entries[.gitRef(repository: Self.leftURL, ref: "main")] = [entry("a.swift", "2")]
        sut.right.refChoice = .ref("main")
        try await taskProvider.waitForAllTasks()

        #expect(sut.right.source == .gitRef(repository: Self.leftURL, ref: "main"))
        #expect(sut.status(ofPath: "a.swift") == .different)
    }

    private func makeSUT() -> DiffViewerModel {
        let suite = "GitDiffViewerTests.model.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let uptime = uptime
        return DiffViewerModel(settings: ViewerSettings(defaults: defaults), reader: reader, taskProvider: taskProvider, uptime: { uptime.now })
    }

    private func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    /// Loads both folders; the model recomputes the comparison itself once both sides land.
    private func load(_ sut: DiffViewerModel) async throws {
        sut.left.load(.directory(Self.leftURL), repository: nil)
        sut.right.load(.directory(Self.rightURL), repository: nil)
        try await taskProvider.waitForAllTasks()
    }
}

/// A monotonic time the test advances by hand.
final class FakeUptime: @unchecked Sendable {
    nonisolated(unsafe) var now: Duration = .zero
}

/// In-memory source reader; records the paths whose content was requested and can hold a read until released.
final class FakeSourceReader: SourceReading, Sendable {
    private struct State {
        var entries: [ComparisonSource: [SourceEntry]] = [:]
        var ignored: [ComparisonSource: [SourceEntry]] = [:]
        var repositories: [URL: RepositoryInfo] = [:]
        var contents: [String: String] = [:]
        var gate: [String: AsyncProbe<Void>] = [:]
        var gitRenames: [String: String] = [:]
    }

    private let state = Mutex(State())
    let contentRequests = AsyncProbe<String>()

    var entries: [ComparisonSource: [SourceEntry]] {
        get { state.withLock { $0.entries } }
        set { state.withLock { $0.entries = newValue } }
    }

    var contents: [String: String] {
        get { state.withLock { $0.contents } }
        set { state.withLock { $0.contents = newValue } }
    }

    var ignored: [ComparisonSource: [SourceEntry]] {
        get { state.withLock { $0.ignored } }
        set { state.withLock { $0.ignored = newValue } }
    }

    var repositories: [URL: RepositoryInfo] {
        get { state.withLock { $0.repositories } }
        set { state.withLock { $0.repositories = newValue } }
    }

    /// Reads of a path, or entries of a directory path, wait for one element per read on their gate.
    var gate: [String: AsyncProbe<Void>] {
        get { state.withLock { $0.gate } }
        set { state.withLock { $0.gate = newValue } }
    }

    var gitRenames: [String: String] {
        get { state.withLock { $0.gitRenames } }
        set { state.withLock { $0.gitRenames = newValue } }
    }

    func repositoryInfo(containing url: URL) async -> RepositoryInfo? { repositories[url] }

    func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String] { gitRenames }

    func entries(of source: ComparisonSource) async throws -> [SourceEntry] {
        if case .directory(let url) = source, let gate = gate[url.path(percentEncoded: false)] {
            _ = try await gate.next()
        }
        return entries[source] ?? []
    }

    func ignoredEntries(of source: ComparisonSource) async throws -> [SourceEntry] {
        ignored[source] ?? []
    }

    func content(of entry: SourceEntry, in source: ComparisonSource) async throws -> String {
        contentRequests.send(entry.relativePath)
        if let gate = gate[entry.relativePath] {
            _ = try await gate.next()
        }
        return contents[entry.relativePath] ?? "\(entry.relativePath) \(entry.blobID ?? "")\n"
    }
}
