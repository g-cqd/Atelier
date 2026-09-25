import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// Gap handle drags through the window model: a drag only reveals, each handle grows its own change, and a drag
/// renders the card it drags alone (book DIFF-02; GDV B7).
@MainActor
@Suite(.mainActorLane)
struct DiffViewerModelGapDragTests {
    private let harness = ModelTestHarness()

    /// Cards for a.swift and b.swift, each thirty lines changed at lines 5 and 25: a leading gap, a gap between the
    /// two changes, and a trailing gap.
    private func loadTwoChangesPerFile(_ sut: DiffViewerModel) async throws {
        let lines = (1 ... 30).map { "line \($0)" }
        var changed = lines
        changed[4] = "line five"
        changed[24] = "line twenty-five"
        harness.reader.blobContents["old"] = lines.joined(separator: "\n") + "\n"
        harness.reader.blobContents["new"] = changed.joined(separator: "\n") + "\n"
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "old"), harness.entry("b.swift", "old")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "new"), harness.entry("b.swift", "new")
        ]
        try await harness.load(sut)
    }

    private func gaps(ofCard index: Int, in sut: DiffViewerModel) -> [GapMarker] {
        sut.renderedFiles[index].rendered.new?.gaps.map(\.marker) ?? []
    }

    @Test
    func `dragging a top-of-file gap down, against its reveal direction, reveals nothing`() async throws {
        let sut = harness.makeSUT()
        try await loadTwoChangesPerFile(sut)
        let before = sut.renderedFiles[0].rendered.id
        let top = try #require(gaps(ofCard: 0, in: sut).first)
        #expect(top.isLeading)

        harness.drag(sut, .extendsChangeBelow, of: top, rows: -4)

        #expect(sut.expansion(of: top.key) == GapExpansion())
        #expect(sut.renderedFiles[0].rendered.id == before)
    }

    @Test
    func `each handle of a gap between two changes reveals its own change's side`() async throws {
        let sut = harness.makeSUT()
        try await loadTwoChangesPerFile(sut)
        let between = try #require(gaps(ofCard: 0, in: sut).first { !$0.isLeading && !$0.isTrailing })
        #expect(between.handles == [.extendsChangeAbove, .extendsChangeBelow])

        harness.drag(sut, .extendsChangeAbove, of: between, rows: 2)
        harness.drag(sut, .extendsChangeBelow, of: between, rows: 3)

        #expect(sut.expansion(of: between.key) == GapExpansion(below: 2, above: 3))
        let after = try #require(gaps(ofCard: 0, in: sut).first { $0.key == between.key })
        #expect(after.hiddenRows == between.hiddenRows - 5)
    }

    @Test
    func `a drag renders the card it drags alone`() async throws {
        let sut = harness.makeSUT()
        try await loadTwoChangesPerFile(sut)
        let before = sut.renderedFiles.map(\.rendered.id)
        let between = try #require(gaps(ofCard: 1, in: sut).first { !$0.isLeading && !$0.isTrailing })

        harness.drag(sut, .extendsChangeBelow, of: between, rows: 3)

        #expect(sut.renderedFiles[0].rendered.id == before[0])
        #expect(sut.renderedFiles[1].rendered.id != before[1])
    }
}
