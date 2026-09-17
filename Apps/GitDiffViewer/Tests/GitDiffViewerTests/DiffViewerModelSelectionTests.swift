import AemiCore
import AemiTesting
import AtelierFileTree
import DiffCore
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// Selection, tabs, settings changes, re-layout and the races between loads and renders.
@MainActor
struct DiffViewerModelSelectionTests {
    private let harness = ModelTestHarness()

    @Test
    func `changing the granularity re-renders the current selection`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        harness.reader.contents["a.swift"] = "let value = count\n"
        try await harness.load(sut)
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()
        let before = try #require(sut.rendered?.old?.id)

        sut.settings.granularity = .syntax
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.rendered?.old?.id != before)
        #expect(sut.rendered != nil)
    }

    @Test
    func `the detail state follows loading, selection and results`() async throws {
        let sut = harness.makeSUT()
        #expect(sut.detailState == .noSources)

        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "1")]
        try await harness.load(sut)
        #expect(sut.detailState == .noChanges)

        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()
        if case .file = sut.detailState {} else { Issue.record("expected a rendered file, got \(sut.detailState)") }

        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        sut.right.reload()
        try await harness.taskProvider.waitForAllTasks()
        if case .file = sut.detailState {} else { Issue.record("expected the changed file, got \(sut.detailState)") }
        sut.select(nil)
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
    }

    @Test
    func `a re-layout while cards are still streaming keeps the remaining cards coming`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4")
        ]
        harness.reader.gate["b.swift"] = AsyncProbe<Void>()
        sut.left.load(.directory(ModelTestHarness.leftURL), repository: nil)
        sut.right.load(.directory(ModelTestHarness.rightURL), repository: nil)
        try await harness.taskProvider.waitForSpawnedTasks(atLeast: 3)
        for _ in 0 ..< 4 { _ = try await harness.reader.contentRequests.next() }
        #expect(sut.renderedFiles.map(\.path) == ["a.swift"])
        #expect(sut.isRendering)

        sut.settings.mode = .inline
        harness.reader.gate["b.swift"]?.send(())
        harness.reader.gate["b.swift"]?.send(())
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.renderedFiles.map(\.path) == ["a.swift", "b.swift"])
        #expect(sut.renderedFiles.allSatisfy { $0.rendered.unified != nil })
        #expect(!sut.isRendering)
    }

    @Test
    func `a render finishing during a reload is not shown as current`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)
        harness.reader.gate["a.swift"] = AsyncProbe<Void>()
        sut.settings.granularity = .character
        try await harness.taskProvider.waitForSpawnedTasks(atLeast: 1)
        _ = try await harness.reader.contentRequests.next()

        harness.reader.gate["/right"] = AsyncProbe<Void>()
        sut.right.reload()
        harness.reader.gate["a.swift"]?.send(())
        harness.reader.gate["a.swift"]?.send(())
        try await harness.taskProvider.waitForSpawnedTasks(atLeast: 1)

        #expect(sut.detailState == .loading)
        harness.reader.gate["/right"]?.send(())
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
    }

    @Test
    func `a new selection cancels the prefetch of the previous one`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2"), harness.entry("c.swift", "3")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "4"), harness.entry("b.swift", "5"), harness.entry("c.swift", "6")
        ]
        sut.left.load(.directory(ModelTestHarness.leftURL), repository: nil)
        sut.right.load(.directory(ModelTestHarness.rightURL), repository: nil)
        try await harness.taskProvider.waitForAllTasks()
        for _ in 0 ..< 6 { _ = try await harness.reader.contentRequests.next() }
        harness.reader.gate["c.swift"] = AsyncProbe<Void>()
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "4"), harness.entry("b.swift", "5"), harness.entry("c.swift", "7")
        ]
        sut.right.reload()
        try await harness.taskProvider.waitForSpawnedTasks(atLeast: 2)
        for _ in 0 ..< 2 { _ = try await harness.reader.contentRequests.next() }
        try harness.reader.contentRequests.expectNoBufferedElements()

        sut.select("a.swift")
        #expect(sut.rendered != nil)
        harness.reader.gate["c.swift"]?.send(())
        harness.reader.gate["c.swift"]?.send(())
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.renderedFiles.isEmpty)
        try harness.reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `changing a setting recomputes only what it affects`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("z/same.swift", "1"), harness.entry("a/changed.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("z/same.swift", "1"), harness.entry("a/changed.swift", "8")
        ]
        try await harness.load(sut)
        for _ in 0 ..< 2 { _ = try await harness.reader.contentRequests.next() }
        let firstRender = try #require(sut.renderedFiles.first?.rendered.id)

        sut.settings.showsChangesOnly = true
        #expect(sut.leftTree.map(\.id) == ["a"])
        #expect(sut.renderedFiles.first?.rendered.id == firstRender)

        sut.settings.contextLines = 1
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.renderedFiles.first?.rendered.id != firstRender)
        try harness.reader.contentRequests.expectNoBufferedElements()

        sut.settings.granularity = .character
        try await harness.taskProvider.waitForAllTasks()
        for _ in 0 ..< 2 { _ = try await harness.reader.contentRequests.next() }
        try harness.reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `changing a diff heuristic re-diffs the selection with the new pipeline`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)
        for _ in 0 ..< 2 { _ = try await harness.reader.contentRequests.next() }
        let before = try #require(sut.renderedFiles.first?.rendered.id)

        sut.settings.diffHeuristics.whitespace = .ignoreAll
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.renderedFiles.first?.rendered.id != before)
        for _ in 0 ..< 2 { _ = try await harness.reader.contentRequests.next() }
        try harness.reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `selecting opens a temporary tab, pinning keeps it, and closing the last tab shows every file`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4")
        ]
        try await harness.load(sut)

        sut.select("a.swift")
        sut.select("b.swift")
        #expect(sut.tabs.tabs.map(\.path) == ["b.swift"])
        #expect(sut.selectedPath == "b.swift")

        sut.pin("a.swift")
        #expect(sut.tabs.tabs.map(\.path) == ["b.swift", "a.swift"])
        #expect(sut.selectedPath == "a.swift")

        for tab in sut.tabs.tabs { sut.closeTab(tab.id) }
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.selectedPath == nil)
        #expect(sut.detailState == .cards)
    }

    @Test
    func `opening a file focuses its first change`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)

        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.currentChange == 1)
        #expect(sut.scrollRequest?.row == sut.rendered?.splitChangeStarts.first)
    }

    @Test
    func `only the sides of the current layout are rendered`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.rendered?.unified == nil)
        #expect(sut.rendered?.old != nil)

        sut.settings.mode = .inline
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.rendered?.unified != nil)
        #expect(sut.rendered?.old == nil)
    }

    @Test
    func `a selection made while the previous one is still loading discards the stale result`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("slow.swift", "1"), harness.entry("fast.swift", "3")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("slow.swift", "2"), harness.entry("fast.swift", "4")
        ]
        try await harness.load(sut)
        harness.reader.gate["slow.swift"] = AsyncProbe<Void>()

        sut.select("slow.swift")
        try await harness.taskProvider.waitForSpawnedTasks(atLeast: 1)
        sut.select("fast.swift")
        harness.reader.gate["slow.swift"]?.send(())
        harness.reader.gate["slow.swift"]?.send(())
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.selectedPath == "fast.swift")
        #expect(sut.rendered?.old?.rows.contains { $0.kind == .removed } == true)
        #expect(sut.rendered?.old?.attributed.string.contains("fast.swift") == true)
    }

    @Test
    func `nothing renders while a side is still loading`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        harness.reader.gate["/right"] = AsyncProbe<Void>()

        sut.left.load(.directory(ModelTestHarness.leftURL), repository: nil)
        sut.right.load(.directory(ModelTestHarness.rightURL), repository: nil)
        try await harness.taskProvider.waitForSpawnedTasks(atLeast: 2)
        sut.sourcesChanged()
        #expect(sut.detailState == .loading)
        #expect(sut.renderedFiles.isEmpty)
        #expect(sut.leftTree.isEmpty)
        #expect(sut.statuses.isEmpty)

        harness.reader.gate["/right"]?.send(())
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
    }
}
