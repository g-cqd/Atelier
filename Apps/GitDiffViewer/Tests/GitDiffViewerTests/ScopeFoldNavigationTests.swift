import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering

/// Change navigation through folded scopes (DIFF-03): a folded change keeps its place in the count, and moving to it
/// opens the fold that hides it, so the pane places it as it places any change.
@MainActor
@Suite(.mainActorLane)
struct ScopeFoldNavigationTests {
    private let harness = ModelTestHarness()
    /// The new side's `f`, lines 1 to 3, and `h`, lines 7 to 9, each holding a change.
    private static let f = ScopeFoldKey(fileIndex: 0, isOld: false, firstLine: 1)
    private static let h = ScopeFoldKey(fileIndex: 0, isOld: false, firstLine: 7)

    /// `a.swift` shown inline, with `folds` folded.
    private func showFolded(_ folds: [ScopeFoldKey: Int]) async throws -> DiffViewerModel {
        let sut = harness.makeSUT()
        sut.settings.mode = .inline
        harness.reader.blobContents["old"] = ScopeFoldRenderingTests.old
        harness.reader.blobContents["new"] = ScopeFoldRenderingTests.new
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [harness.entry("a.swift", "old")]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [harness.entry("a.swift", "new")]
        try await harness.load(sut)
        sut.select("a.swift")
        try await harness.taskProvider.waitForAllTasks()
        sut.changeFolds(.fold(folds))
        return sut
    }

    /// The row of the change at `index` in the file shown, with no fold over it.
    private func row(ofChange index: Int, in sut: DiffViewerModel) throws -> Int {
        try #require(sut.rendered?.unifiedChangeStarts[index])
    }

    @Test
    func `a folded change keeps its place in the count, starting on its fold's band`() async throws {
        let sut = try await showFolded([Self.f: 3])
        let unified = try #require(sut.rendered?.unified)

        #expect(sut.changeCount == 2)
        #expect(try row(ofChange: 0, in: sut) == unified.folds.first?.bandRow)
    }

    @Test
    func `moving to the next change opens the fold it lands in and asks for the change's row`() async throws {
        // Opening the file made its first change the current one: the next is `h`'s.
        let sut = try await showFolded([Self.h: 9])

        sut.goToNextChange()

        #expect(sut.foldedScopes.isEmpty)
        let row = try row(ofChange: 1, in: sut)
        #expect(sut.scrollRequest?.row == row)
        #expect(sut.rendered?.unified?.rows[row].oldNumber == 9)
    }

    @Test
    func `moving to the previous change opens the fold it lands in, and leaves the others as they are`()
        async throws
    {
        let sut = try await showFolded([Self.f: 3, Self.h: 9])
        sut.goToNextChange()
        #expect(sut.foldedScopes == [Self.f: 3])

        sut.goToPreviousChange()

        #expect(sut.foldedScopes.isEmpty)
        let row = try row(ofChange: 0, in: sut)
        #expect(sut.scrollRequest?.row == row)
        #expect(sut.rendered?.unified?.rows[row].oldNumber == 3)
    }
}
