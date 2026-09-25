import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A gap step renders its own card and nothing else; a relayout renders off the main actor and lands only where
/// nothing newer replaced what it rendered (GDV B7).
@MainActor
@Suite(.mainActorLane)
struct RenderPipelineRelayoutTests {
    private let harness = PipelineHarness()

    /// Publishes cards for a and b, both at version 1.
    private func publishFirstVersions() async throws {
        harness.render(
            [harness.pair("a.swift", version: 1), harness.pair("b.swift", version: 1)], keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()
    }

    @Test
    func `a gap step renders only the dragged card and sends no finished event`() async throws {
        try await publishFirstVersions()
        let before = harness.sut.cards.map(\.rendered.id)
        let start = harness.events.all.count

        try harness.revealAbove(3, inCard: 0)

        #expect(harness.sut.cards[0].rendered.id != before[0])
        #expect(harness.sut.cards[1].rendered.id == before[1])
        #expect(harness.events.finishes(since: start) == 0)
    }

    @Test
    func `a relayout renders off the main actor, and a gap drag while it renders survives its landing`()
        async throws
    {
        try await publishFirstVersions()
        let hidden = try #require(harness.leadingGap(ofCard: 1)?.hiddenRows)

        harness.sut.configure(options: PipelineHarness.inline, context: 2, isolatesChanges: false)
        harness.sut.relayout(keepingScroll: false)
        #expect(harness.sut.cards.allSatisfy { $0.rendered.unified == nil })
        try harness.revealAbove(3, inCard: 1)
        try await harness.taskProvider.waitForAllTasks()

        #expect(harness.sut.cards.allSatisfy { $0.rendered.unified != nil })
        #expect(harness.leadingGap(ofCard: 1)?.hiddenRows == hidden - 3)
        #expect(harness.leadingGap(ofCard: 0)?.hiddenRows == hidden)
    }

    @Test
    func `an off-main relayout that finishes after a newer render is dropped`() async throws {
        try await publishFirstVersions()
        harness.sut.configure(options: PipelineHarness.inline, context: 2, isolatesChanges: false)
        harness.sut.relayout(keepingScroll: false)

        harness.render([harness.pair("a.swift", version: 1)], keepingPublished: false)
        let newer = harness.sut.cards.map(\.rendered.id)
        let start = harness.events.all.count
        try await harness.taskProvider.waitForAllTasks()

        #expect(harness.sut.cards.map(\.rendered.id) == newer)
        #expect(harness.events.finishes(since: start) == 0)
    }
}
