import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit

/// ``DiffViewerModel/currentProjectRoot`` follows the comparison's current repository, including a later switch
/// through the source toolbar.
@MainActor
struct DiffViewerModelProjectRootTests {
    private let harness = ModelTestHarness()

    private func repository(_ root: URL) -> RepositoryInfo {
        RepositoryInfo(root: root, branches: ["main"], tags: [], commits: [])
    }

    @Test
    func `nil before either side resolves a repository`() {
        let sut = harness.makeSUT()
        #expect(sut.currentProjectRoot == nil)
    }

    @Test
    func `prefers the left side's repository when both resolved one`() {
        let sut = harness.makeSUT()
        let leftRoot = URL(filePath: "/repoLeft", directoryHint: .isDirectory)
        let rightRoot = URL(filePath: "/repoRight", directoryHint: .isDirectory)
        sut.left.load(.directory(ModelTestHarness.leftURL), repository: repository(leftRoot))
        sut.right.load(.directory(ModelTestHarness.rightURL), repository: repository(rightRoot))

        #expect(sut.currentProjectRoot == leftRoot)
    }

    @Test
    func `falls back to the right side's repository when only it resolved one`() {
        let sut = harness.makeSUT()
        let rightRoot = URL(filePath: "/repoRight", directoryHint: .isDirectory)
        sut.left.load(.directory(ModelTestHarness.leftURL), repository: nil)
        sut.right.load(.directory(ModelTestHarness.rightURL), repository: repository(rightRoot))

        #expect(sut.currentProjectRoot == rightRoot)
    }

    @Test
    func `switching a side to a different repository through the toolbar updates the current root`() {
        let sut = harness.makeSUT()
        let firstRoot = URL(filePath: "/repoA", directoryHint: .isDirectory)
        let secondRoot = URL(filePath: "/repoB", directoryHint: .isDirectory)
        sut.left.load(.directory(ModelTestHarness.leftURL), repository: repository(firstRoot))
        sut.right.load(.directory(ModelTestHarness.rightURL), repository: nil)
        #expect(sut.currentProjectRoot == firstRoot)

        // As picking another repository from the source toolbar does.
        sut.left.load(.directory(ModelTestHarness.leftURL), repository: repository(secondRoot))

        #expect(sut.currentProjectRoot == secondRoot)
    }

    @Test
    func `nil for a patch, which resolves no repository on either side`() {
        let sut = harness.makeSUT()
        sut.left.load(.patch(URL(filePath: "/x.patch"), side: .old), repository: nil)
        sut.right.load(.patch(URL(filePath: "/x.patch"), side: .new), repository: nil)

        #expect(sut.currentProjectRoot == nil)
    }
}
