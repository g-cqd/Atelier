import AtelierGit
import Foundation
import Testing

@testable import AtelierSources

struct SourceDescriptorTests {
    private static let repository = RepositoryInfo(
        root: URL(filePath: "/tmp/Atelier", directoryHint: .isDirectory), branches: ["main"], tags: [],
        commits: [])

    @Test
    func `a git ref describes the repository as its context and the abbreviated ref as its primary text`() {
        let source = ComparisonSource.gitRef(repository: Self.repository.root, ref: "feature/long-branch-name")
        let described = source.descriptor(repository: Self.repository)
        #expect(described.symbol == .branch)
        #expect(described.context == "Atelier")
        #expect(described.primary == "feature/long-branch-name")
        #expect(described.detail == "feature/long-branch-name in /tmp/Atelier/")
    }

    @Test
    func `a directory at the repository root describes itself as the working tree, not a plain folder`() {
        let source = ComparisonSource.directory(Self.repository.root)
        let described = source.descriptor(repository: Self.repository)
        #expect(described.symbol == .workingTree)
        #expect(described.context == "Atelier")
        #expect(described.primary == "Working Tree")
    }

    @Test
    func `a directory that is not the repository root describes itself as a plain folder`() {
        let source = ComparisonSource.directory(Self.repository.root.appending(path: "Sources"))
        let described = source.descriptor(repository: Self.repository)
        #expect(described.symbol == .folder)
        #expect(described.context == "Atelier")
        #expect(described.primary == "Sources")
    }

    @Test
    func `a directory describes itself as a plain folder when there is no repository to compare it against`() {
        let source = ComparisonSource.directory(Self.repository.root)
        let described = source.descriptor(repository: nil)
        #expect(described.symbol == .folder)
    }

    @Test
    func `a file describes its parent folder as its context and its name as its primary text`() {
        let source = ComparisonSource.file(URL(filePath: "/tmp/Atelier/Sources/File.swift"))
        let described = source.descriptor(repository: nil)
        #expect(described.symbol == .file)
        #expect(described.context == "Sources")
        #expect(described.primary == "File.swift")
    }

    @Test
    func `each side of a patch names the file as its context and its side as its primary text`() {
        let url = URL(filePath: "/tmp/change.patch")
        let old = ComparisonSource.patch(url, side: .old).descriptor(repository: nil)
        let new = ComparisonSource.patch(url, side: .new).descriptor(repository: nil)
        #expect(old.symbol == .patch)
        #expect(old.context == "change.patch")
        #expect(old.primary == "before")
        #expect(new.primary == "after")
    }

    @Test
    func `displayName and detail are backed by the descriptor`() {
        let gitRef = ComparisonSource.gitRef(repository: Self.repository.root, ref: "main")
        #expect(gitRef.displayName == "Atelier @ main")
        #expect(gitRef.detail == "main in /tmp/Atelier/")

        let directory = ComparisonSource.directory(Self.repository.root)
        #expect(directory.displayName == "Atelier")

        let patch = ComparisonSource.patch(URL(filePath: "/tmp/change.patch"), side: .old)
        #expect(patch.displayName == "change.patch (before)")
    }
}
