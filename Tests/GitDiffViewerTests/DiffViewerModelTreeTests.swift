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

/// The explorer trees the model derives: statuses, renames, folders, filters and the ignored section.
@MainActor
struct DiffViewerModelTreeTests {
    private let harness = ModelTestHarness()

    @Test
    func `renamed files are shown under their destination path`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("old/name.swift", "1"), harness.entry("same.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("new/name.swift", "1"), harness.entry("same.swift", "2")
        ]

        try await harness.load(sut)

        #expect(sut.displayPath(for: "old/name.swift") == "new/name.swift")
        #expect(sut.displayPath(for: "same.swift") == "same.swift")
    }

    @Test
    func `selecting a folder renders only the changed files underneath it`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a/x.swift", "1"), harness.entry("a/y.swift", "2"), harness.entry("b/z.swift", "3")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a/x.swift", "1"), harness.entry("a/y.swift", "9"), harness.entry("b/z.swift", "9")
        ]
        try await harness.load(sut)

        sut.select("a")
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.isShowingCombinedFiles)
        #expect(sut.combinedFiles == ["a/y.swift"])
        #expect(sut.renderedFiles.first?.rendered.changeCount == 1)
    }

    @Test
    func `changes only filter keeps the directories leading to changed files`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("z/same.swift", "1"), harness.entry("a/x/changed.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("z/same.swift", "1"), harness.entry("a/x/changed.swift", "8")
        ]
        try await harness.load(sut)

        sut.settings.showsChangesOnly = true

        #expect(sut.leftTree.map(\.id) == ["a"])
        #expect(sut.leftTree.first?.children?.first?.children?.map(\.id) == ["a/x/changed.swift"])
    }

    @Test
    func `a file moved without changes is a rename and its sides compare with each other`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("old/name.swift", "1"), harness.entry("keep.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("new/name.swift", "1"), harness.entry("keep.swift", "2")
        ]

        try await harness.load(sut)

        #expect(sut.renames == ["old/name.swift": "new/name.swift"])
        #expect(sut.status(ofPath: "old/name.swift") == .renamed)
        #expect(sut.status(of: "new/name.swift", in: .right) == .renamed)
        #expect(sut.counterpartPath(of: "new/name.swift", in: .right) == "old/name.swift")
        #expect(sut.changeSummary(for: "old/name.swift", rendered: nil).kind == .renamed(to: "new/name.swift"))
        #expect(sut.combinedFiles == ["old/name.swift"])
    }

    @Test
    func `renames reported by git pair changed files across paths`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("b.swift", "2")]
        harness.reader.contents["a.swift"] = "one\ntwo\n"
        harness.reader.contents["b.swift"] = "one\nthree\n"
        harness.reader.gitRenames = ["a.swift": "b.swift"]

        try await harness.load(sut)

        #expect(sut.status(ofPath: "a.swift") == .renamed)
        #expect(sut.isRenamedWithChanges("a.swift"))
        let summary = sut.changeSummary(for: "a.swift", rendered: sut.renderedFiles.first?.rendered)
        #expect(summary == FileChangeSummary(kind: .renamed(to: "b.swift"), addedLines: 1, removedLines: 1))
    }

    @Test
    func `badges classify added deleted and modified files with line counts`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("gone.swift", "1"), harness.entry("changed.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("new.swift", "3"), harness.entry("changed.swift", "9")
        ]
        try await harness.load(sut)

        #expect(sut.changeSummary(for: "gone.swift", rendered: nil).kind == .deleted)
        #expect(sut.changeSummary(for: "new.swift", rendered: nil).kind == .added)
        let changed = try #require(sut.renderedFiles.first { $0.path == "changed.swift" })
        let summary = sut.changeSummary(for: "changed.swift", rendered: changed.rendered)
        #expect(summary.kind == .modified)
        #expect(summary.addedLines == 1)
        #expect(summary.removedLines == 1)
    }

    // MARK: Helpers

    @Test
    func `compact folders folds single child chains after the changed files filter`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a/b/c/changed.swift", "1"), harness.entry("a/other.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a/b/c/changed.swift", "9"), harness.entry("a/other.swift", "2")
        ]
        try await harness.load(sut)

        sut.settings.showsChangesOnly = true
        sut.settings.treeStyle = .compact

        #expect(sut.leftTree.map(\.name) == ["a/b/c"])
        #expect(sut.leftTree.first?.children?.map(\.id) == ["a/b/c/changed.swift"])
    }

    @Test
    func `the flat style lists every file by its full path without folders`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("b/z.swift", "1"), harness.entry("a/x/y.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("b/z.swift", "1"), harness.entry("a/x/y.swift", "3")
        ]
        try await harness.load(sut)

        sut.settings.treeStyle = .flat

        #expect(sut.leftTree.map(\.id) == ["a/x/y.swift", "b/z.swift"])
        #expect(sut.leftTree.map(\.name) == ["y.swift", "z.swift"])
        #expect(sut.leftTree.allSatisfy { !$0.isDirectory })
    }

    @Test
    func `ignored files form a section of their own only when shown, and diff as added`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        harness.reader.ignored[.directory(ModelTestHarness.rightURL)] = [
            SourceEntry(relativePath: "build/out.txt", blobID: nil, size: 0)
        ]
        try await harness.load(sut)

        #expect(sut.unifiedSections.map(\.kind) == [.changes])
        #expect(sut.right.ignoredEntries == nil)
        #expect(sut.changedPathCount == 1)

        sut.settings.showsIgnoredFiles = true
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.unifiedSections.map(\.kind) == [.changes, .ignored])
        #expect(sut.unifiedSections[1].nodes.flatMap(\.filePaths) == ["build/out.txt"])
        #expect(sut.rightSections[1].nodes.flatMap(\.filePaths) == ["build/out.txt"])
        #expect(sut.leftSections[1].nodes.isEmpty)
        #expect(sut.unifiedSections[0].nodes.flatMap(\.filePaths) == ["a.swift"])
        #expect(sut.changedPathCount == 1)
        #expect(sut.status(ofPath: "build/out.txt") == nil)

        sut.select("build/out.txt", from: .right)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.selectedPath == "build/out.txt")
        #expect(sut.changeSummary(for: "build/out.txt", rendered: sut.rendered).kind == .added)
        #expect(sut.rendered?.addedLines == 1)

        sut.settings.showsIgnoredFiles = false
        #expect(sut.unifiedSections.map(\.kind) == [.changes])
    }

    @Test
    func `a folder chosen while the other side is empty puts that side on the same repository without a source`()
        async throws
    {
        let sut = harness.makeSUT()
        let info = RepositoryInfo(root: ModelTestHarness.leftURL, branches: ["main", "feature"], tags: [], commits: [])
        harness.reader.repositories[ModelTestHarness.leftURL] = info
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]

        sut.left.choose(ModelTestHarness.leftURL)
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.left.source == .directory(ModelTestHarness.leftURL))
        #expect(sut.right.repository == info)
        #expect(sut.right.source == nil)
        #expect(sut.detailState == .noSources)

        harness.reader.entries[.gitRef(repository: ModelTestHarness.leftURL, ref: "main")] = [
            harness.entry("a.swift", "2")
        ]
        sut.right.refChoice = .ref("main")
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.right.source == .gitRef(repository: ModelTestHarness.leftURL, ref: "main"))
        #expect(sut.status(ofPath: "a.swift") == .different)
    }
}
