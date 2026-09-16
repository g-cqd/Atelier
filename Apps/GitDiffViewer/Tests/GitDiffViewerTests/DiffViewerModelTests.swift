import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// Loading, statuses, folding, timing and the card list of the window model.
@MainActor
struct DiffViewerModelTests {
    private let harness = ModelTestHarness()

    @Test
    func `statuses compare blob ids and report files present on one side only`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2"), harness.entry("only-left.swift", "3")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "9"), harness.entry("only-right.swift", "4")
        ]

        try await harness.load(sut)

        #expect(sut.status(of: "a.swift", in: .left) == .same)
        #expect(sut.status(of: "b.swift", in: .left) == .different)
        #expect(sut.status(of: "only-left.swift", in: .left) == .onlyLeft)
        #expect(sut.status(of: "only-right.swift", in: .right) == .onlyRight)
        #expect(sut.changedPathCount == 3)
    }

    @Test
    func `with nothing selected every changed file is rendered one after another`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("z/same.swift", "1"), harness.entry("a/changed.swift", "2"), harness.entry("b.swift", "3")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("z/same.swift", "1"), harness.entry("a/changed.swift", "8"), harness.entry("b.swift", "4")
        ]

        try await harness.load(sut)

        #expect(sut.selectedPath == nil)
        #expect(sut.isShowingCombinedFiles)
        #expect(sut.combinedFiles == ["a/changed.swift", "b.swift"])
        #expect(sut.renderedFiles.map(\.path) == ["a/changed.swift", "b.swift"])
        #expect(sut.renderedFiles.allSatisfy { $0.rendered.old?.rows.allSatisfy { $0.kind != .header } == true })
        var requests: [String] = []
        for _ in 0 ..< 4 { requests.append(try #require(try await harness.reader.contentRequests.next())) }
        #expect(requests.sorted() == ["a/changed.swift", "a/changed.swift", "b.swift", "b.swift"])
        try harness.reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `cards fold per file, all at once, and unfold when the sources change`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "8"), harness.entry("b.swift", "9")
        ]
        try await harness.load(sut)

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
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("gone.swift", "1"), harness.entry("kept.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("kept.swift", "3"), harness.entry("new.swift", "4")
        ]

        try await harness.load(sut)

        #expect(sut.renderedFiles.map(\.path) == ["gone.swift", "kept.swift", "new.swift"])
        #expect(sut.collapsedFiles == ["gone.swift", "new.swift"])

        sut.toggleCollapsed("gone.swift")
        sut.relayout()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.collapsedFiles == ["new.swift"])
    }

    @Test
    func `a comparison is timed from the source change to the render and to the first card on screen`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4")
        ]
        harness.uptime.now = .milliseconds(100)
        sut.left.load(.directory(ModelTestHarness.leftURL), repository: nil)
        sut.right.load(.directory(ModelTestHarness.rightURL), repository: nil)
        harness.uptime.now = .milliseconds(140)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.timing == RenderTiming(firstDisplay: nil, rendered: .milliseconds(40)))

        harness.uptime.now = .milliseconds(155)
        sut.noteDisplayed(try #require(sut.renderedFiles.last?.rendered.id))
        sut.noteDisplayed(try #require(sut.renderedFiles.first?.rendered.id))
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.timing == RenderTiming(firstDisplay: .milliseconds(55), rendered: .milliseconds(40)))
    }

    @Test
    func `a file is timed from its selection to its appearance on screen`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)
        sut.select("a.swift")
        sut.settings.granularity = .character

        harness.uptime.now = .milliseconds(200)
        sut.renderSelection()
        harness.uptime.now = .milliseconds(230)
        try await harness.taskProvider.waitForAllTasks()
        harness.uptime.now = .milliseconds(245)
        sut.noteDisplayed(try #require(sut.rendered?.id))
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.timing == RenderTiming(firstDisplay: .milliseconds(45), rendered: .milliseconds(30)))
    }

    @Test
    func `a file already compared in the card list is shown at once without reading it again`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4")
        ]
        try await harness.load(sut)
        for _ in 0 ..< 4 { _ = try await harness.reader.contentRequests.next() }

        sut.select("b.swift")

        #expect(sut.rendered != nil)
        #expect(sut.detailState == .file(try #require(sut.rendered)))
        #expect(sut.timing.rendered != nil)
        try await harness.taskProvider.waitForAllTasks()
        try harness.reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `changed files are prefetched after a selection so the next one is instant`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2"), harness.entry("c.swift", "5")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4"), harness.entry("c.swift", "5")
        ]
        sut.left.load(.directory(ModelTestHarness.leftURL), repository: nil)
        sut.right.load(.directory(ModelTestHarness.rightURL), repository: nil)
        try await harness.taskProvider.waitForAllTasks()
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()

        var requested: [String] = []
        for _ in 0 ..< 4 { requested.append(try #require(try await harness.reader.contentRequests.next())) }
        #expect(requested.sorted() == ["a.swift", "a.swift", "b.swift", "b.swift"])
        try harness.reader.contentRequests.expectNoBufferedElements()

        sut.select("b.swift")
        #expect(sut.rendered != nil)
        try await harness.taskProvider.waitForAllTasks()
        try harness.reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `opening a patch compares its old and new sides`() async throws {
        let sut = harness.makeSUT()
        let url = URL(filePath: "/tmp/changes.patch")
        harness.reader.entries[.patch(url, side: .old)] = [
            harness.entry("a.swift", "1"), harness.entry("gone.swift", "2")
        ]
        harness.reader.entries[.patch(url, side: .new)] = [
            harness.entry("a.swift", "3"), harness.entry("new.swift", "4")
        ]

        sut.openPatch(url)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.left.source == .patch(url, side: .old))
        #expect(sut.right.source == .patch(url, side: .new))
        #expect(sut.renderedFiles.map(\.path) == ["a.swift", "gone.swift", "new.swift"])
        #expect(sut.collapsedFiles == ["gone.swift", "new.swift"])
    }

    @Test
    func `dragging a gap reveals rows and keeps the pane where it was`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        harness.reader.contents["a.swift"] = (1 ... 30).map { "line \($0)" }.joined(separator: "\n") + "\n"
        try await harness.load(sut)
        sut.settings.isolatesChanges = true
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()
        let marker = try #require(sut.rendered?.old?.rows.first?.gap)
        #expect(marker.isLeading)

        sut.adjustGap(marker, from: GapExpansion(), byLines: 4)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.expansion(of: marker.key) == GapExpansion(below: 0, above: 4))
        #expect(sut.rendered?.keepsScrollPosition == true)
    }

    @Test
    func `two single files compare with each other whatever their names`() async throws {
        let sut = harness.makeSUT()
        let left = ComparisonSource.file(ModelTestHarness.leftURL.appending(path: "old.txt"))
        let right = ComparisonSource.file(ModelTestHarness.rightURL.appending(path: "new.txt"))
        harness.reader.entries[left] = [harness.entry("old.txt", "1")]
        harness.reader.entries[right] = [harness.entry("new.txt", "2")]
        harness.reader.contents["old.txt"] = "one\ntwo\n"
        harness.reader.contents["new.txt"] = "one\ntwo!\n"

        sut.left.load(left, repository: nil)
        sut.right.load(right, repository: nil)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.status(of: "old.txt", in: .left) == .different)
        #expect(sut.status(of: "new.txt", in: .right) == .different)
        #expect(sut.rendered?.changeCount == 1)
        #expect(sut.rendered?.old?.rows.map(\.kind) == [.context, .removed])
        #expect(sut.rendered?.new?.rows.map(\.kind) == [.context, .added])
        #expect(sut.rendered?.unified == nil)
    }
}
