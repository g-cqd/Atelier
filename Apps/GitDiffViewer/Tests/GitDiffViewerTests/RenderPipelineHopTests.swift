import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A render pipeline over the harness's reader, with a renderer the test can hold open, comparing two folders.
@MainActor
struct PipelineHarness {
    let reader = FakeSourceReader()
    let taskProvider = TaskProviderSpy.tolerant()
    let holding = HoldingPaneRenderer()
    let sut: RenderPipeline
    let events = PipelineEventLog()

    static let split = DiffRenderer.Options(sides: [.old, .new])
    static let inline = DiffRenderer.Options(sides: [.unified])
    /// Thirty lines; a version changes line 15, so each file shows one hunk between a leading and a trailing gap.
    static let base = (1 ... 30).map { "line \($0)" }

    init() {
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider)
        sut = RenderPipeline(
            preparer: preparer, taskProvider: taskProvider, options: Self.split, renderer: holding.renderer)
        sut.configure(options: Self.split, context: 2, isolatesChanges: false)
        sut.onEvent = { [events] event in events.all.append(event) }
        for version in 0 ... 3 {
            var lines = Self.base
            if version > 0 { lines[14] = "line fifteen, version \(version)" }
            let text = lines.joined(separator: "\n") + "\n"
            reader.blobContents["a\(version)"] = text
            reader.blobContents["b\(version)"] = text
        }
    }

    /// `path` compared from its base version to `version`.
    func pair(_ path: String, version: Int) -> FilePair {
        let name = String(path.prefix(1))
        return FilePair(
            path: path, old: SourceEntry(relativePath: path, blobID: "\(name)0", size: 1),
            new: SourceEntry(relativePath: path, blobID: "\(name)\(version)", size: 1))
    }

    func render(_ pairs: [FilePair], keepingPublished: Bool) {
        sut.render(
            .cards(pairs), left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .word, heuristics: DiffHeuristics(), keepingPublished: keepingPublished)
    }

    /// The gap above the first hunk of the card at `index`, on its new side, or its only side when inline.
    func leadingGap(ofCard index: Int) -> GapMarker? {
        guard sut.cards.indices.contains(index) else { return nil }
        let rendered = sut.cards[index].rendered
        return (rendered.new ?? rendered.unified)?.rows.first?.gap
    }

    /// Drags the leading gap of the card at `index` to reveal `rows` rows above its hunk.
    func revealAbove(_ rows: Int, inCard index: Int) throws {
        let marker = try #require(leadingGap(ofCard: index))
        sut.adjustGap(marker, from: sut.expansion(of: marker.key), byLines: -rows)
    }
}

/// Every event a pipeline sent, in order.
@MainActor
final class PipelineEventLog {
    var all: [RenderPipeline.Event] = []

    /// How many publishes arrived after the first `start` events.
    func publishes(since start: Int) -> Int {
        all.dropFirst(start).filter { if case .published = $0 { true } else { false } }.count
    }

    /// How many times a render or a relayout finished after the first `start` events.
    func finishes(since start: Int) -> Int {
        all.dropFirst(start).filter { if case .finished = $0 { true } else { false } }.count
    }
}

/// A render that keeps what is published leaves it on screen, and interactive, until its replacement lands whole
/// (GDV B3, S1; review 6.2).
@MainActor
struct RenderPipelineHopTests {
    private let harness = PipelineHarness()

    /// Publishes cards for a and b, both at version 1, then drains the four reads they made.
    private func publishFirstVersions() async throws {
        harness.render(
            [harness.pair("a.swift", version: 1), harness.pair("b.swift", version: 1)], keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()
        for _ in 0 ..< 4 { _ = try await harness.reader.contentRequests.next() }
    }

    @Test
    func `a render that keeps what is published leaves the cards on screen until the replacement lands in one step`()
        async throws
    {
        try await publishFirstVersions()
        let before = harness.sut.cards.map(\.rendered.id)
        harness.reader.gate["b.swift"] = AsyncProbe<Void>()
        let start = harness.events.all.count

        harness.render(
            [harness.pair("a.swift", version: 1), harness.pair("b.swift", version: 2)], keepingPublished: true)
        _ = try await harness.reader.contentRequests.next()

        #expect(harness.sut.cards.map(\.rendered.id) == before)
        #expect(harness.sut.isRendering)
        harness.reader.gate["b.swift"]?.send(())
        harness.reader.gate["b.swift"]?.send(())
        try await harness.taskProvider.waitForAllTasks()
        #expect(harness.sut.cards.first?.rendered.id == before.first)
        #expect(harness.sut.cards.last?.rendered.id != before.last)
        #expect(harness.events.publishes(since: start) == 1)
        #expect(!harness.sut.isRendering)
    }

    @Test
    func `a gap drag issued while a render prepares survives on the card that stays and on the one replaced`()
        async throws
    {
        try await publishFirstVersions()
        let hidden = try #require(harness.leadingGap(ofCard: 0)?.hiddenRows)
        harness.reader.gate["b.swift"] = AsyncProbe<Void>()

        harness.render(
            [harness.pair("a.swift", version: 1), harness.pair("b.swift", version: 2)], keepingPublished: true)
        _ = try await harness.reader.contentRequests.next()
        try harness.revealAbove(3, inCard: 0)
        try harness.revealAbove(3, inCard: 1)
        harness.reader.gate["b.swift"]?.send(())
        harness.reader.gate["b.swift"]?.send(())
        try await harness.taskProvider.waitForAllTasks()

        #expect(harness.leadingGap(ofCard: 0)?.hiddenRows == hidden - 3)
        #expect(harness.leadingGap(ofCard: 1)?.hiddenRows == hidden - 3)
        #expect(harness.sut.expansion(of: GapKey(fileIndex: 1, gapIndex: 0)) == GapExpansion(above: 3))
    }

    @Test
    func `a gap drag issued while a render step runs survives on the card that stays and on the one replaced`()
        async throws
    {
        try await publishFirstVersions()
        let hidden = try #require(harness.leadingGap(ofCard: 0)?.hiddenRows)
        harness.holding.isHolding = true

        harness.render(
            [harness.pair("a.swift", version: 1), harness.pair("b.swift", version: 2)], keepingPublished: true)
        #expect(try await harness.holding.steps.next() == [1])
        try harness.revealAbove(3, inCard: 0)
        try harness.revealAbove(3, inCard: 1)
        harness.holding.isHolding = false
        harness.holding.release.send(())
        try await harness.taskProvider.waitForAllTasks()

        #expect(harness.leadingGap(ofCard: 0)?.hiddenRows == hidden - 3)
        #expect(harness.leadingGap(ofCard: 1)?.hiddenRows == hidden - 3)
    }

    @Test
    func `a relayout while a render prepares reaches the cards that stay and the ones that replace them`()
        async throws
    {
        try await publishFirstVersions()
        harness.reader.gate["b.swift"] = AsyncProbe<Void>()

        harness.render(
            [harness.pair("a.swift", version: 1), harness.pair("b.swift", version: 2)], keepingPublished: true)
        _ = try await harness.reader.contentRequests.next()
        harness.sut.configure(options: PipelineHarness.inline, context: 2, isolatesChanges: false)
        harness.sut.relayout(keepingScroll: false)
        harness.reader.gate["b.swift"]?.send(())
        harness.reader.gate["b.swift"]?.send(())
        try await harness.taskProvider.waitForAllTasks()

        #expect(harness.sut.cards.count == 2)
        #expect(harness.sut.cards.allSatisfy { $0.rendered.unified != nil && $0.rendered.old == nil })
    }
}
