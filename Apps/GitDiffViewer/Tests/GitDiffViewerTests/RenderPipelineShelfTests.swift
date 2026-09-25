import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// The card list a file takes off screen comes back, when the file's tab closes, with the cards it showed rather
/// than rendered anew, unless something about how they render changed meanwhile (book PERF-10).
@MainActor
@Suite(.mainActorLane)
struct RenderPipelineShelfTests {
    private let harness = PipelineHarness()

    private var pairs: [FilePair] {
        [harness.pair("a.swift", version: 1), harness.pair("b.swift", version: 1)]
    }

    private func showFile(_ pair: FilePair) {
        harness.sut.render(
            .file(pair), left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .word, heuristics: DiffHeuristics(), keepingPublished: false)
    }

    /// Publishes the list of a and b, then opens the file at `index` on its own, and returns the list's render ids.
    private func openFileFromList(at index: Int = 1) async throws -> [RenderedDiff.ID] {
        harness.render(pairs, keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()
        let list = harness.sut.cards.map(\.rendered.id)
        showFile(pairs[index])
        try await harness.taskProvider.waitForAllTasks()
        #expect(harness.sut.file != nil)
        #expect(harness.sut.cards.isEmpty)
        return list
    }

    @Test
    func `the list a file replaced comes back whole at once, with the cards it showed`() async throws {
        let list = try await openFileFromList()
        let start = harness.events.all.count

        harness.render(pairs, keepingPublished: false)

        #expect(harness.sut.cards.map(\.rendered.id) == list)
        #expect(harness.sut.file == nil)
        #expect(!harness.sut.isRendering)
        #expect(harness.events.publishes(since: start) == 1)
        #expect(harness.events.finishes(since: start) == 1)
    }

    @Test
    func `the list comes back at once from the file of its first card, which shows at the card's place`() async throws {
        let list = try await openFileFromList(at: 0)

        harness.render(pairs, keepingPublished: false)

        #expect(harness.sut.cards.map(\.rendered.id) == list)
        #expect(!harness.sut.isRendering)
    }

    @Test
    func `the list comes back rendered again when the layout changed while the file showed`() async throws {
        let list = try await openFileFromList()
        harness.sut.configure(options: PipelineHarness.inline, context: 2, isolatesChanges: false)

        harness.render(pairs, keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()

        #expect(harness.sut.cards.count == 2)
        #expect(Set(harness.sut.cards.map(\.rendered.id)).isDisjoint(with: list))
        #expect(harness.sut.cards.allSatisfy { $0.rendered.unified != nil && $0.rendered.old == nil })
    }

    @Test
    func `a list compared with other diff options renders its cards anew`() async throws {
        let list = try await openFileFromList()

        harness.sut.render(
            .cards(pairs), left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .character, heuristics: DiffHeuristics(), keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()

        #expect(harness.sut.cards.count == 2)
        #expect(Set(harness.sut.cards.map(\.rendered.id)).isDisjoint(with: list))
    }

    @Test
    func `a card whose file changed renders again while the others come back as they were`() async throws {
        let list = try await openFileFromList()

        harness.render(
            [harness.pair("a.swift", version: 1), harness.pair("b.swift", version: 2)], keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()

        #expect(harness.sut.cards.first?.rendered.id == list.first)
        #expect(harness.sut.cards.last.map { $0.rendered.id != list.last } == true)
    }

    @Test
    func `the whole list comes back at once after a folder's list and a file showed in between`() async throws {
        harness.render(pairs, keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()
        let list = harness.sut.cards.map(\.rendered.id)
        harness.render([pairs[1]], keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()
        let folder = harness.sut.cards.map(\.rendered.id)
        showFile(pairs[0])
        try await harness.taskProvider.waitForAllTasks()
        let start = harness.events.all.count

        harness.render(pairs, keepingPublished: false)

        #expect(harness.sut.cards.map(\.rendered.id) == list)
        #expect(!harness.sut.isRendering)
        #expect(harness.events.publishes(since: start) == 1)

        showFile(pairs[0])
        try await harness.taskProvider.waitForAllTasks()
        harness.render([pairs[1]], keepingPublished: false)
        #expect(harness.sut.cards.map(\.rendered.id) == folder)
        #expect(!harness.sut.isRendering)
    }

    @Test
    func `the whole list comes back at once straight from a folder's list`() async throws {
        harness.render(pairs, keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()
        let list = harness.sut.cards.map(\.rendered.id)
        harness.render([pairs[1]], keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()
        let start = harness.events.all.count

        harness.render(pairs, keepingPublished: false)

        #expect(harness.sut.cards.map(\.rendered.id) == list)
        #expect(!harness.sut.isRendering)
        #expect(harness.events.publishes(since: start) == 1)
    }

    @Test
    func `only the lists shown last are kept, so memory stays bounded`() async throws {
        harness.render(pairs, keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()
        let list = harness.sut.cards.map(\.rendered.id)
        for folder in 1 ... RenderPipeline.shelfCapacity {
            harness.render([harness.pair("b\(folder).swift", version: 1)], keepingPublished: false)
            try await harness.taskProvider.waitForAllTasks()
        }
        showFile(pairs[0])
        try await harness.taskProvider.waitForAllTasks()

        harness.render(pairs, keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()

        #expect(Set(harness.sut.cards.map(\.rendered.id)).isDisjoint(with: list))
    }

    @Test
    func `a cleared pipeline keeps no list to go back to`() async throws {
        let list = try await openFileFromList()
        harness.sut.clear()

        harness.render(pairs, keepingPublished: false)
        try await harness.taskProvider.waitForAllTasks()

        #expect(Set(harness.sut.cards.map(\.rendered.id)).isDisjoint(with: list))
    }
}
