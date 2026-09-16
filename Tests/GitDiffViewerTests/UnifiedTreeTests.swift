import AemiCore
import AemiTesting
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

@MainActor
struct UnifiedTreeTests {
    private let taskProvider = TaskProviderSpy()
    private let reader = FakeSourceReader()

    @Test
    func `the unified tree merges both sides and folders take the aggregate status of their files`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [
            entry("same/a.swift", "1"), entry("gone/b.swift", "2"), entry("mixed/c.swift", "3")
        ]
        reader.entries[.directory(Self.rightURL)] = [
            entry("same/a.swift", "1"), entry("new/d.swift", "4"), entry("mixed/c.swift", "9"),
            entry("mixed/e.swift", "5")
        ]

        try await load(sut)

        #expect(sut.unifiedTree.map(\.id) == ["gone", "mixed", "new", "same"])
        #expect(sut.status(ofPath: "same") == .same)
        #expect(sut.status(ofPath: "gone") == .onlyLeft)
        #expect(sut.status(ofPath: "new") == .onlyRight)
        #expect(sut.status(ofPath: "mixed") == .different)
        #expect(sut.status(ofPath: "mixed/e.swift") == .onlyRight)
    }

    @Test
    func `changed files only filters the unified tree too`() async throws {
        let sut = makeSUT()
        reader.entries[.directory(Self.leftURL)] = [entry("same/a.swift", "1"), entry("gone/b.swift", "2")]
        reader.entries[.directory(Self.rightURL)] = [entry("same/a.swift", "1")]
        try await load(sut)

        sut.settings.showsChangesOnly = true
        sut.rebuildTrees()

        #expect(sut.unifiedTree.map(\.id) == ["gone"])
    }

    private static let leftURL = URL(filePath: "/left", directoryHint: .isDirectory)
    private static let rightURL = URL(filePath: "/right", directoryHint: .isDirectory)

    private func makeSUT() -> DiffViewerModel {
        let suite = "GitDiffViewerTests.unified.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return DiffViewerModel(settings: ViewerSettings(defaults: defaults), reader: reader, taskProvider: taskProvider)
    }

    private func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    private func load(_ sut: DiffViewerModel) async throws {
        sut.left.load(.directory(Self.leftURL), repository: nil)
        sut.right.load(.directory(Self.rightURL), repository: nil)
        try await taskProvider.waitForAllTasks()
    }
}
