import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// Folding a scope (DIFF-03) goes where gap expansions and disclosed changes go: into the render stamp, carried across
/// a reload by path. The file renders again with the scope folded, and takes its colour, emphasis and ribbon back at
/// once, since they are kept by source line.
@MainActor
@Suite(.mainActorLane)
struct ScopeFoldPipelineTests {
    private let reader = FakeSourceReader()
    private let taskProvider = TaskProviderSpy.tolerant()
    private let store = SyntaxFactsStore()
    private let sut: RenderPipeline
    private static let pair = FilePair(
        path: "a.swift", old: SourceEntry(relativePath: "a.swift", blobID: "old", size: 1),
        new: SourceEntry(relativePath: "a.swift", blobID: "new", size: 1))
    /// The whole of `S`, lines 0 to 10 of the new side.
    private static let s = ScopeFoldKey(fileIndex: 0, isOld: false, firstLine: 0)
    private static let revealed = GapKey(fileIndex: 0, gapIndex: 0)

    init() {
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider, store: store)
        let options = DiffRenderer.Options(sides: [.unified])
        sut = RenderPipeline(
            preparer: preparer, taskProvider: taskProvider, options: options,
            decorator: DiffDecorator(tiers: DiffDecorations.tiers(store: store), clock: TestClock(), store: store))
        sut.configure(options: options, context: 1, isolatesChanges: true)
        reader.blobContents["old"] = ScopeFoldRenderingTests.old
        reader.blobContents["new"] = ScopeFoldRenderingTests.new
    }

    private func render() async throws -> RenderedDiff {
        sut.render(
            .file(Self.pair), left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .word, heuristics: DiffHeuristics(), keepingPublished: false)
        try await taskProvider.waitForAllTasks()
        return try #require(sut.file)
    }

    @Test
    func `a fold renders the file again, keeps its gaps' keys and revealed lines, and its decorations come back`()
        async throws
    {
        _ = try await render()
        sut.setExpansion(GapExpansion(above: 1), for: Self.revealed)
        let shown = try #require(sut.file)
        let open = try #require(shown.unified)
        sut.decorateDisplayed(shown.id)
        try await taskProvider.waitForAllTasks()
        let jobs = sut.decorator.started

        sut.changeFolds(.fold([Self.s: 10]))

        let folded = try #require(sut.file?.unified)
        #expect(folded.folds.map(\.key) == [Self.s])
        let decorations = try #require(sut.decorations(forText: folded.id))
        #expect(decorations.new.colors != nil)
        #expect(decorations.new.scopes != nil)
        #expect(sut.decorator.started == jobs)

        sut.changeFolds(.unfold([Self.s]))

        let unfolded = try #require(sut.file?.unified)
        #expect(unfolded.folds.isEmpty)
        #expect(unfolded.gaps.map(\.marker.key) == open.gaps.map(\.marker.key))
        #expect(unfolded.rows.first?.newNumber == 1)
        #expect(sut.expansion(of: Self.revealed) == GapExpansion(above: 1))
    }

    @Test
    func `a fold is carried through a reload of the same file`() async throws {
        _ = try await render()
        sut.setExpansion(GapExpansion(above: 1), for: Self.revealed)
        sut.changeFolds(.fold([Self.s: 10]))

        let reloaded = try await render()

        #expect(sut.foldedScopes == [Self.s: 10])
        #expect(reloaded.unified?.folds.map(\.key) == [Self.s])
    }
}
