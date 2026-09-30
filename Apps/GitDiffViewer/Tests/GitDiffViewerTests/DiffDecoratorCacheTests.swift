import AtelierHighlighting
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffRendering

/// The colour cache's eviction (PERF-11): trimming to ``DiffDecorator/cacheCapacity`` only ever runs in
/// ``DiffDecorator/publish(_:)``, with the published set that call just set, so a burst of colour landing before the
/// decorator has ever been told what is published, as many cards' jobs finishing at once could, is not evicted before
/// it gets the chance to say so.
@MainActor
@Suite(.mainActorLane)
struct DiffDecoratorCacheTests {
    private static let count = DiffDecorator.cacheCapacity + 20

    private static func key(_ index: Int) -> DiffDecorator.ContentKey {
        .blob("b\(index)", .swift)
    }

    private static func update(_ index: Int) -> TierUpdate {
        TierUpdate(
            layer: .lexical, coverage: .complete,
            revision: SourceRevision(documentID: "f\(index)", language: .swift, key: .content("b\(index)")),
            lines: 0 ..< 1, tokens: LineTokens(emptyLines: 1))
    }

    private static func rendered(_ index: Int) -> RenderedDiff {
        DiffRenderer.render(oldText: "let a\(index) = 1\n", newText: "let a\(index) = 2\n", language: .swift)
    }

    @Test
    func `colour landed before the first publish is not evicted once every file publishes`() {
        let sut = DiffDecorator()
        var files: [(rendered: RenderedDiff, composition: DiffDecorator.Composition)] = []
        for index in 0 ..< Self.count {
            sut.land(Self.update(index), lineCount: 1, for: Self.key(index))
            files.append(
                (
                    Self.rendered(index),
                    DiffDecorator.Composition(preparation: UUID(), old: nil, new: Self.key(index))
                ))
        }

        sut.publish(files)

        let missing = files.filter { sut.byText[$0.rendered.new!.id] == nil }
        #expect(missing.isEmpty, "\(missing.count) of \(Self.count) files lost the colour landed before any publish")
    }
}
