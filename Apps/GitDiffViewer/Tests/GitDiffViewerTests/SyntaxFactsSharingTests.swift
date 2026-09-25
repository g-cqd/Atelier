import AemiCore
import AemiTesting
import AtelierDocIndex
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// One swift-syntax parse per blob and side serves the intraline diff, the colour and hover (PERF-11 step 3).
@MainActor
struct SyntaxFactsSharingTests {
    private static let old = "/// Greets.\nfunc greet() { print(\"hello world\") }\nlet a = 1\n"
    private static let new = "/// Greets.\nfunc greet() { print(\"hello there\") }\nlet a = 2\n"

    private let reader = FakeSourceReader()
    private let taskProvider = TaskProviderSpy.tolerant()
    private let store = SyntaxFactsStore()
    private let sut: RenderPipeline

    init() {
        let preparer = DiffPreparer(reader: reader, taskProvider: taskProvider, store: store)
        sut = RenderPipeline(
            preparer: preparer, taskProvider: taskProvider, options: DiffRenderer.Options(sides: [.old, .new]),
            refinement: SwiftColorRefinement(tiers: RefinedSides.tiers(store: store), clock: TestClock()))
        reader.blobContents["old"] = Self.old
        reader.blobContents["new"] = Self.new
    }

    private static func revision(_ blob: String) -> SourceRevision {
        SourceRevision(documentID: "a.swift", language: .swift, key: .content(blob))
    }

    @Test
    func `a side is parsed once for its intraline boundaries, its colour and its hover documentation`() async throws {
        let pair = FilePair(
            path: "a.swift", old: SourceEntry(relativePath: "a.swift", blobID: "old", size: 1),
            new: SourceEntry(relativePath: "a.swift", blobID: "new", size: 1))
        sut.render(
            .file(pair), left: .directory(ModelTestHarness.leftURL), right: .directory(ModelTestHarness.rightURL),
            granularity: .syntax, heuristics: DiffHeuristics(), keepingPublished: false)
        try await taskProvider.waitForAllTasks()
        let file = try #require(sut.file)
        #expect(store.extractions == 2)

        sut.refineDisplayed(file.id)
        try await taskProvider.waitForAllTasks()
        let index = DocCommentIndex(store: store)
        try await index.upsert([
            DocIndexFile(uri: "atelier-blob://old/a.swift", content: Self.old, blobID: "old", sides: .old),
            DocIndexFile(uri: "file:///a.swift", content: Self.new, blobID: "new", sides: .new)
        ])

        let new = try #require(file.new)
        #expect(store.extractions == 2)
        #expect(sut.refinedSides(forText: new.id) != nil)
        #expect(await index.documentation(forIdentifier: "greet", preferringURI: nil, side: .new).count == 1)
    }

    @Test
    func `the intraline emphasis read from the facts is the one the side's own parse gives`() {
        let stored = PreparedDiff(
            FileDiffInput(
                title: "a.swift", oldText: Self.old, newText: Self.new, language: .swift,
                oldRevision: Self.revision("old"), newRevision: Self.revision("new")),
            granularity: .syntax, store: store)
        let parsed = PreparedDiff(
            FileDiffInput(title: "a.swift", oldText: Self.old, newText: Self.new, language: .swift),
            granularity: .syntax)

        let emphasis = { (diff: PreparedDiff) in diff.model.splitRows.map { [$0.old?.emphasis, $0.new?.emphasis] } }
        #expect(emphasis(stored) == emphasis(parsed))
        #expect(emphasis(stored).joined().contains { !($0 ?? []).isEmpty })
        #expect(store.extractions == 2)
    }
}
