import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// The file list as a fixed first tab while files or folders are open in tabs (book TAB-10): showing it closes no tab.
@MainActor
struct DiffViewerModelFileListTabTests {
    private let harness = ModelTestHarness()

    /// A model comparing a.swift, b.swift and src/c.swift, each changed, with the list on screen.
    private func makeLoadedSUT() async throws -> DiffViewerModel {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2"), harness.entry("src/c.swift", "3")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "4"), harness.entry("b.swift", "5"), harness.entry("src/c.swift", "6")
        ]
        try await harness.load(sut)
        return sut
    }

    @Test
    func `opening a tab makes the file list a fixed first tab`() async throws {
        let sut = try await makeLoadedSUT()
        #expect(sut.tabs.stops.isEmpty)

        sut.select("a.swift")

        #expect(sut.tabs.stops.first == .fileList)
        #expect(sut.tabs.stops.map(\.path) == [nil, "a.swift"])
        #expect(!sut.tabs.isShowingFileList)
    }

    @Test
    func `showing the file list shows every changed file and closes no tab`() async throws {
        let sut = try await makeLoadedSUT()
        sut.pin("a.swift")
        sut.select("src")
        try await harness.taskProvider.waitForAllTasks()
        let open = sut.tabs.tabs

        sut.showFileList()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.tabs.tabs == open)
        #expect(sut.tabs.isShowingFileList)
        #expect(sut.selectedPath == nil)
        #expect(sut.detailState == .cards)
        #expect(sut.combinedFiles == ["a.swift", "b.swift", "src/c.swift"])
    }

    @Test
    func `the next and previous tab commands stop at the file list`() async throws {
        let sut = try await makeLoadedSUT()
        sut.pin("a.swift")
        sut.pin("b.swift")
        try await harness.taskProvider.waitForAllTasks()

        sut.showTab(.next)
        #expect(sut.tabs.isShowingFileList)
        #expect(sut.selectedPath == nil)

        sut.showTab(.next)
        #expect(sut.selectedPath == "a.swift")
        sut.showTab(.previous)
        #expect(sut.tabs.isShowingFileList)
        sut.showTab(.previous)
        #expect(sut.selectedPath == "b.swift")
        #expect(sut.tabs.tabs.map(\.path) == ["a.swift", "b.swift"])
    }

    @Test
    func `the file list tab cannot be closed, and closing every other tab takes it away`() async throws {
        let sut = try await makeLoadedSUT()
        sut.pin("a.swift")
        sut.pin("b.swift")
        sut.showFileList()

        sut.closeTab(try #require(sut.tabs.tabs.first?.id))
        #expect(sut.tabs.stops.map(\.path) == [nil, "b.swift"])
        #expect(sut.tabs.isShowingFileList)
        #expect(sut.selectedPath == nil)

        sut.closeTab(try #require(sut.tabs.tabs.first?.id))
        #expect(sut.tabs.stops.isEmpty)
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
    }

    @Test
    func `a comparison of two single files keeps the file list on screen when the sources reload`() async throws {
        let sut = harness.makeSUT()
        let leftFile = URL(filePath: "/left/a.swift")
        let rightFile = URL(filePath: "/right/a.swift")
        harness.reader.entries[.file(leftFile)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.file(rightFile)] = [harness.entry("a.swift", "2")]
        sut.left.load(.file(leftFile), repository: nil)
        sut.right.load(.file(rightFile), repository: nil)
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.selectedPath == "a.swift")

        sut.showFileList()
        sut.reloadSources()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.tabs.isShowingFileList)
        #expect(sut.selectedPath == nil)
        #expect(sut.tabs.tabs.map(\.path) == ["a.swift"])
    }
}
