import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A reload or an auto-refresh re-comparison must not discard already-loaded files: only files whose comparison
/// state actually changed re-render, and fold state and scroll position survive for the rest.
@MainActor
struct DiffViewerModelReloadContinuityTests {
    private let harness = ModelTestHarness()

    @Test
    func `cards fold per file, all at once, and stay folded through a reload`() async throws {
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

        // Re-compares, as a reload or an auto-refresh does.
        sut.sourcesChanged()
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.collapsedFiles == ["a.swift", "b.swift"])
    }

    @Test
    func `a reload keeps an unchanged card's identity and re-renders only the file whose blob changed`()
        async throws
    {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4")
        ]
        try await harness.load(sut)
        for _ in 0 ..< 4 { _ = try await harness.reader.contentRequests.next() }
        let beforeA = try #require(sut.renderedFiles.first { $0.path == "a.swift" })
        let beforeB = try #require(sut.renderedFiles.first { $0.path == "b.swift" })

        // Only b.swift's new side changes.
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "9")
        ]
        sut.right.reload()
        try await harness.taskProvider.waitForAllTasks()

        let afterA = try #require(sut.renderedFiles.first { $0.path == "a.swift" })
        let afterB = try #require(sut.renderedFiles.first { $0.path == "b.swift" })
        #expect(afterA.rendered.id == beforeA.rendered.id)
        #expect(afterB.rendered.id != beforeB.rendered.id)

        // a.swift was neither re-read nor re-diffed; only b.swift's two sides were.
        var requested: [String] = []
        for _ in 0 ..< 2 { requested.append(try #require(try await harness.reader.contentRequests.next())) }
        #expect(requested.sorted() == ["b.swift", "b.swift"])
        try harness.reader.contentRequests.expectNoBufferedElements()
    }

    @Test
    func `a reload that adds and removes files keeps the untouched cards' identity`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2"), harness.entry("c.swift", "3")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "4"), harness.entry("b.swift", "5"), harness.entry("c.swift", "6")
        ]
        try await harness.load(sut)
        let beforeA = try #require(sut.renderedFiles.first { $0.path == "a.swift" })
        let beforeB = try #require(sut.renderedFiles.first { $0.path == "b.swift" })

        // c.swift disappears and z.swift, sorting after it, appears; a.swift and b.swift keep their positions.
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2"), harness.entry("z.swift", "7")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "4"), harness.entry("b.swift", "5"), harness.entry("z.swift", "8")
        ]
        sut.left.reload()
        try await harness.taskProvider.waitForAllTasks()
        sut.right.reload()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.renderedFiles.map(\.path) == ["a.swift", "b.swift", "z.swift"])
        let afterA = try #require(sut.renderedFiles.first { $0.path == "a.swift" })
        let afterB = try #require(sut.renderedFiles.first { $0.path == "b.swift" })
        #expect(afterA.rendered.id == beforeA.rendered.id)
        #expect(afterB.rendered.id == beforeB.rendered.id)
    }

    @Test
    func `changing the granularity re-renders every card even though no pair changed`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4")
        ]
        try await harness.load(sut)
        let beforeA = try #require(sut.renderedFiles.first { $0.path == "a.swift" })
        let beforeB = try #require(sut.renderedFiles.first { $0.path == "b.swift" })

        sut.settings.granularity = .character
        try await harness.taskProvider.waitForAllTasks()

        let afterA = try #require(sut.renderedFiles.first { $0.path == "a.swift" })
        let afterB = try #require(sut.renderedFiles.first { $0.path == "b.swift" })
        #expect(afterA.rendered.id != beforeA.rendered.id)
        #expect(afterB.rendered.id != beforeB.rendered.id)
    }

    @Test
    func `a fold made on one file survives a reload that only re-renders another`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "3"), harness.entry("b.swift", "4")
        ]
        try await harness.load(sut)
        sut.toggleCollapsed("b.swift")
        #expect(sut.collapsedFiles == ["b.swift"])

        // Only a.swift's new side changes; b.swift is untouched.
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "9"), harness.entry("b.swift", "4")
        ]
        sut.right.reload()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.collapsedFiles == ["b.swift"])
    }

    @Test
    func `reloading a selected file that did not change is a no-op, and its scroll survives when it did change`()
        async throws
    {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()
        let unchanged = try #require(sut.rendered)

        // A reload that changes nothing keeps the very same `RenderedDiff`.
        sut.right.reload()
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.rendered?.id == unchanged.id)

        // A reload that changes it re-renders it and keeps the pane's scroll position.
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "9")]
        sut.right.reload()
        try await harness.taskProvider.waitForAllTasks()
        let changed = try #require(sut.rendered)
        #expect(changed.id != unchanged.id)
        #expect(changed.keepsScrollPosition)
    }

    @Test
    func `a file whose content lacks a blob hash on both sides never reuses stale content across a reload`()
        async throws
    {
        let sut = harness.makeSUT()
        // Past `SourceLoader`'s hashing limit an entry has no blob id, so blobs cannot tell its versions apart.
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            SourceEntry(relativePath: "big.swift", blobID: nil, size: 9_000_000)
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            SourceEntry(relativePath: "big.swift", blobID: nil, size: 9_000_000)
        ]
        harness.reader.contents["big.swift"] = "before"
        try await harness.load(sut)
        sut.select("big.swift")
        try await harness.taskProvider.waitForAllTasks()
        let before = try #require(sut.rendered)

        harness.reader.contents["big.swift"] = "after"
        sut.right.reload()
        try await harness.taskProvider.waitForAllTasks()

        let after = try #require(sut.rendered)
        #expect(after.id != before.id)
    }

    @Test
    func `detailState keeps the previous cards mounted while a reload is still fetching entries`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)
        #expect(sut.detailState == .cards)

        // The held reload leaves the side loading; the published cards must stay mounted meanwhile.
        let rightListing = harness.holdListing(of: ModelTestHarness.rightURL)
        sut.right.reload()
        #expect(sut.right.isLoading)
        #expect(sut.detailState == .cards)

        rightListing.send(())
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.detailState == .cards)
    }

    @Test
    func `a one-sided reload that changes the selected file keeps it on screen until its new version lands`()
        async throws
    {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        try await harness.load(sut)
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()
        for _ in 0 ..< 2 { _ = try await harness.reader.contentRequests.next() }
        let before = try #require(sut.rendered)
        harness.reader.gate["a.swift"] = AsyncProbe<Void>()

        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "9")]
        sut.right.reload()
        _ = try await harness.reader.contentRequests.next()

        #expect(sut.rendered?.id == before.id)
        #expect(sut.detailState == .file(before))
        #expect(sut.isRendering)
        harness.reader.gate["a.swift"]?.send(())
        harness.reader.gate["a.swift"]?.send(())
        try await harness.taskProvider.waitForAllTasks()
        let after = try #require(sut.rendered)
        #expect(after.id != before.id)
        #expect(after.keepsScrollPosition)
    }

    @Test
    func `a gap expansion survives a reload that reuses the selected file`() async throws {
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "1")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "2")]
        harness.serveOneChangeInTheMiddle()
        try await harness.load(sut)
        sut.settings.isolatesChanges = true
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()
        let marker = try #require(sut.rendered?.old?.rows.first?.gap)
        harness.drag(sut, .extendsChangeBelow, of: marker, rows: 4)
        try await harness.taskProvider.waitForAllTasks()
        #expect(sut.expansion(of: marker.key) == GapExpansion(below: 0, above: 4))

        // Neither blob changes, so the reload reuses the `RenderedDiff` with its expanded rows baked in.
        sut.right.reload()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.expansion(of: marker.key) == GapExpansion(below: 0, above: 4))
    }
}
