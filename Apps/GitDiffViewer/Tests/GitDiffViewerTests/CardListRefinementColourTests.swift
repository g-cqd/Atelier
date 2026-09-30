import AemiCore
import AemiTesting
import AtelierHighlighting
import AtelierSwiftSyntax
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// A tier that never finishes until released, for a deadline that always fires; declared complete, over `layer`.
private final class HangingTier: Sendable {
    let layer: HighlightLayer
    let started = AsyncProbe<Void>()

    init(layer: HighlightLayer) { self.layer = layer }

    var tier: Tier { Tier(spy: self) }

    struct Tier: AtelierHighlighting.HighlightTier {
        let spy: HangingTier

        var layer: HighlightLayer { spy.layer }
        var coverage: TierCoverage { .complete }
        var deadline: Duration? { .milliseconds(200) }

        func supports(_ language: Language) -> Bool { language == .swift }

        func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
            spy.started.send(())
            try await Task.sleep(for: .seconds(3_600))
        }
    }
}

/// A tier that always fails, declared complete, over `layer`: a language server that never answers, or a refinement
/// that gates every side out.
private struct AlwaysFailingTier: AtelierHighlighting.HighlightTier {
    let layer: HighlightLayer

    var coverage: TierCoverage { .complete }

    func supports(_ language: Language) -> Bool { language == .swift }

    func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        throw TierFailure.failed("the server gave no answer")
    }
}

/// A card list of real Swift files (PERF-11, PERF-09): every card keeps at least the lexer's colour once its stages
/// end, whichever tier above the lexer fails, times out, or never starts, and however many cards are shown at once.
@MainActor
@Suite(.mainActorLane)
struct CardListRefinementColourTests {
    private let reader = FakeSourceReader()

    /// A view-model-shaped Swift file of `count` lines: properties, a few methods and closures, so the parser walks a
    /// real tree rather than one repeated statement.
    private static func viewModel(_ name: String, count: Int, changedAt changed: Int) -> String {
        var lines: [String] = ["import Foundation", "", "final class \(name): ObservableObject {"]
        for index in 0 ..< count {
            lines.append(
                index == changed
                    ? "    @Published var value\(index) = \(index) * 2"
                    : "    @Published var value\(index) = \(index)")
            if index.isMultiple(of: 6) {
                lines.append("    func handle\(index)() { value\(index) += 1 }")
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// `count` files, 300 to 800 lines, modified, added or renamed in turn.
    private func serveCards(_ count: Int) -> [FilePair] {
        var left: [SourceEntry] = []
        var right: [SourceEntry] = []
        var pairs: [FilePair] = []
        for index in 0 ..< count {
            let lines = 300 + (index % 6) * 100
            let name = "ViewModel\(index)"
            let kind = index % 3
            let oldPath = kind == 2 ? "Old\(name).swift" : "\(name).swift"
            let newPath = "\(name).swift"
            let new = Self.viewModel(name, count: lines, changedAt: lines / 2)
            reader.blobContents["n\(index)"] = new
            right.append(SourceEntry(relativePath: newPath, blobID: "n\(index)", size: 1))
            pairs.append(
                FilePair(
                    path: newPath,
                    old: kind == 0 ? nil : SourceEntry(relativePath: oldPath, blobID: "o\(index)", size: 1),
                    new: SourceEntry(relativePath: newPath, blobID: "n\(index)", size: 1)))
            if kind != 0 {
                reader.blobContents["o\(index)"] = Self.viewModel(name, count: lines - 10, changedAt: 3)
                left.append(SourceEntry(relativePath: oldPath, blobID: "o\(index)", size: 1))
            }
        }
        reader.entries[.directory(ModelTestHarness.leftURL)] = left
        reader.entries[.directory(ModelTestHarness.rightURL)] = right
        return pairs
    }

    /// Renders `count` cards with `tiers` beside the lexer's, shows every one as the list scrolls to it, and lets
    /// every stage end.
    private func decorateAllCards(_ count: Int, extraTiers: [any AtelierHighlighting.HighlightTier]) async throws -> (
        RenderPipeline, TaskProviderSpy
    ) {
        let taskProvider = TaskProviderSpy.tolerant()
        let sut = RenderPipeline(
            preparer: DiffPreparer(reader: reader, taskProvider: taskProvider), taskProvider: taskProvider,
            options: DiffRenderer.Options(sides: [.old, .new]),
            decorator: DiffDecorator(tiers: [LexicalTier()] + extraTiers, clock: ContinuousClock()))
        sut.render(
            .cards(serveCards(count)), left: .directory(ModelTestHarness.leftURL),
            right: .directory(ModelTestHarness.rightURL), granularity: .word, heuristics: DiffHeuristics(),
            keepingPublished: false)
        try await taskProvider.waitForAllTasks()
        for card in sut.cards { sut.decorateDisplayed(card.rendered.id) }
        try await taskProvider.waitForAllTasks()
        return (sut, taskProvider)
    }

    /// Every card's new side, with its colours; `nil` for a side no pane shows.
    private static func newColours(_ sut: RenderPipeline) -> [LayeredLineTokens?] {
        sut.cards.map { card in card.rendered.new.flatMap { sut.decorations(forText: $0.id)?.new.colors } }
    }

    @Test
    func `a language server that never answers still leaves every card its lexer's colour`() async throws {
        let (sut, _) = try await decorateAllCards(24, extraTiers: [AlwaysFailingTier(layer: .semantic)])

        let colours = Self.newColours(sut)
        #expect(colours.allSatisfy { $0 != nil }, "cards with no colour: \(colours.filter { $0 == nil }.count)")
        #expect(colours.allSatisfy { $0?.layers(onLine: 0).contains(.lexical) == true })
    }

    /// `count` files, all modified, both sides present: an exact side count for the deadline test to wait on.
    private func serveModifiedCards(_ count: Int) -> [FilePair] {
        var left: [SourceEntry] = []
        var right: [SourceEntry] = []
        var pairs: [FilePair] = []
        for index in 0 ..< count {
            let lines = 300 + (index % 6) * 100
            let name = "ViewModel\(index)"
            let path = "\(name).swift"
            reader.blobContents["o\(index)"] = Self.viewModel(name, count: lines, changedAt: 3)
            reader.blobContents["n\(index)"] = Self.viewModel(name, count: lines, changedAt: lines / 2)
            left.append(SourceEntry(relativePath: path, blobID: "o\(index)", size: 1))
            right.append(SourceEntry(relativePath: path, blobID: "n\(index)", size: 1))
            pairs.append(
                FilePair(
                    path: path, old: SourceEntry(relativePath: path, blobID: "o\(index)", size: 1),
                    new: SourceEntry(relativePath: path, blobID: "n\(index)", size: 1)))
        }
        reader.entries[.directory(ModelTestHarness.leftURL)] = left
        reader.entries[.directory(ModelTestHarness.rightURL)] = right
        return pairs
    }

    @Test
    func `a refinement tier past its deadline still leaves every card its lexer's colour`() async throws {
        let clock = TestClock()
        let taskProvider = TaskProviderSpy.tolerant()
        let hanging = HangingTier(layer: .syntactic)
        let count = 24
        let sut = RenderPipeline(
            preparer: DiffPreparer(reader: reader, taskProvider: taskProvider), taskProvider: taskProvider,
            options: DiffRenderer.Options(sides: [.old, .new]),
            decorator: DiffDecorator(tiers: [LexicalTier(), hanging.tier], clock: clock))
        sut.render(
            .cards(serveModifiedCards(count)), left: .directory(ModelTestHarness.leftURL),
            right: .directory(ModelTestHarness.rightURL), granularity: .word, heuristics: DiffHeuristics(),
            keepingPublished: false)
        try await taskProvider.waitForAllTasks()
        for card in sut.cards { sut.decorateDisplayed(card.rendered.id) }
        // The lexer lands off the deadline's clock; the hanging tier's deadline, one per side, is the only sleeper.
        try await clock.waitForSleepers(count: 2 * count)
        clock.advance(by: .milliseconds(200))
        try await taskProvider.waitForAllTasks()

        let colours = Self.newColours(sut)
        #expect(colours.allSatisfy { $0 != nil }, "cards with no colour: \(colours.filter { $0 == nil }.count)")
        #expect(colours.allSatisfy { $0?.layers(onLine: 0) == [.lexical] })
    }

    @Test
    func `swift-syntax gated out on a malformed file still leaves every card its lexer's colour`() async throws {
        let (sut, _) = try await decorateAllCards(20, extraTiers: [SwiftSyntaxTier()])

        let colours = Self.newColours(sut)
        #expect(colours.allSatisfy { $0 != nil }, "cards with no colour: \(colours.filter { $0 == nil }.count)")
        #expect(colours.allSatisfy { $0?.layers(onLine: 0).contains(.lexical) == true })
    }
}
