import Foundation
import Testing

@testable import AtelierGit

/// `GitParsers.commitChanges` and `rawChanges` over `log -z --raw` bytes shaped as git prints them.
struct GitParsersCommitChangesTests {
    private static let first = String(repeating: "1", count: 40)
    private static let second = String(repeating: "2", count: 40)
    private static let parent = String(repeating: "3", count: 40)
    private static let blobA = String(repeating: "a", count: 40)
    private static let blobB = String(repeating: "b", count: 40)
    private static let zero = String(repeating: "0", count: 40)

    /// A commit header as the ``GitParsers/commitChangesFormat`` prints it, NUL-terminated by `-z`.
    private static func header(
        _ id: String, parents: [String], time: Int = 1_790_000_000, author: String = "Tess",
        subject: String
    ) -> String {
        "\u{1e}\(id)\0\(parents.joined(separator: " "))\0\(time)\0\(author)\0\(subject)\0"
    }

    /// A raw record; the first of a commit carries the newline git puts before it.
    private static func record(
        _ status: String, _ paths: String..., old: String = blobA, new: String = blobB,
        first: Bool = false
    ) -> String {
        (first ? "\n" : "") + ":100644 100644 \(old) \(new) \(status)\0" + paths.map { "\($0)\0" }.joined()
    }

    @Test
    func `a commit reads its id, parents, author, date, subject and changes`() {
        let output =
            Self.header(Self.first, parents: [Self.parent], time: 1_790_324_815, author: "Tess Ter", subject: "Add")
            + Self.record("M", "a.swift", first: true) + Self.record("A", "b.swift", old: Self.zero)

        let commits = GitParsers.commitChanges(Data(output.utf8))

        #expect(
            commits == [
                GitCommitChanges(
                    id: Self.first, parentIDs: [Self.parent], authorName: "Tess Ter",
                    authorDate: Date(timeIntervalSince1970: 1_790_324_815), subject: "Add",
                    changes: [
                        GitFileChange(status: .modified, path: "a.swift", oldBlobID: Self.blobA, newBlobID: Self.blobB),
                        GitFileChange(status: .added, path: "b.swift", newBlobID: Self.blobB)
                    ])
            ])
    }

    @Test
    func `a merge keeps both parents and its first-parent changes`() throws {
        let output =
            Self.header(Self.first, parents: [Self.parent, Self.second], subject: "Merge branch 'feature'")
            + Self.record("A", "x.swift", old: Self.zero, first: true)

        let commit = try #require(GitParsers.commitChanges(Data(output.utf8)).first)

        #expect(commit.isMerge)
        #expect(commit.parentIDs == [Self.parent, Self.second])
        #expect(commit.changes.map(\.path) == ["x.swift"])
    }

    @Test
    func `a rename reads both paths and a copy reads as an addition`() {
        let output =
            Self.header(Self.first, parents: [Self.parent], subject: "Move")
            + Self.record("R087", "old/a.swift", "new/a.swift", first: true)
            + Self.record("C100", "b.swift", "copy of b.swift")

        let changes = GitParsers.commitChanges(Data(output.utf8)).first?.changes

        #expect(
            changes == [
                GitFileChange(
                    status: .renamed, path: "new/a.swift", oldPath: "old/a.swift", oldBlobID: Self.blobA,
                    newBlobID: Self.blobB),
                GitFileChange(status: .added, path: "copy of b.swift", newBlobID: Self.blobB)
            ])
    }

    @Test
    func `a deletion keeps the deleted path and its old blob only`() {
        let output =
            Self.header(Self.first, parents: [Self.parent], subject: "Remove")
            + Self.record("D", "gone.swift", new: Self.zero, first: true)

        #expect(
            GitParsers.commitChanges(Data(output.utf8)).first?.changes == [
                GitFileChange(status: .deleted, path: "gone.swift", oldBlobID: Self.blobA)
            ])
    }

    @Test
    func `an empty commit between two others lists no changes and keeps its neighbours apart`() {
        let output =
            Self.header(Self.first, parents: [Self.second], subject: "Later")
            + Self.record("M", "a.swift", first: true)
            + Self.header(Self.second, parents: [Self.parent], subject: "")
            + Self.header(Self.parent, parents: [], subject: "Root") + Self.record("A", "a.swift", first: true)

        let commits = GitParsers.commitChanges(Data(output.utf8))

        #expect(commits.map(\.id) == [Self.first, Self.second, Self.parent])
        #expect(commits.map(\.changes.count) == [1, 0, 1])
        #expect(commits[1].subject.isEmpty)
        #expect(commits[2].parentIDs.isEmpty)
    }

    @Test
    func `paths with spaces, newlines, separators and non-ASCII read intact`() {
        let paths = ["with space.swift", "line\nbreak.swift", "\u{1e}record.swift", "caf\u{e9}/\u{65e5}\u{672c}.swift"]
        let output =
            Self.header(Self.first, parents: [Self.parent], subject: "Names")
            + paths.enumerated().map { Self.record("M", $1, first: $0 == 0) }.joined()

        #expect(GitParsers.commitChanges(Data(output.utf8)).first?.changes.map(\.path) == paths)
    }

    @Test
    func `a subject or an author holding the unit and record separators reads intact`() {
        let subject = "Split\u{1f}fields\u{1e}and records"
        let output =
            Self.header(Self.first, parents: [Self.parent], author: "A\u{1f}B", subject: subject)
            + Self.record("M", "a.swift", first: true)

        let commit = GitParsers.commitChanges(Data(output.utf8)).first

        #expect(commit?.subject == subject)
        #expect(commit?.authorName == "A\u{1f}B")
        #expect(commit?.changes.count == 1)
    }

    @Test
    func `a header cut short ends the listing and a malformed record is skipped`() {
        let output =
            Self.header(Self.first, parents: [Self.parent], subject: "Whole")
            + "\n:garbage\0" + Self.record("M", "a.swift")
            + "\u{1e}\(Self.second)\0\(Self.parent)\0"

        let commits = GitParsers.commitChanges(Data(output.utf8))

        #expect(commits.map(\.id) == [Self.first])
        #expect(commits.first?.changes.map(\.path) == ["a.swift"])
    }

    @Test
    func `raw changes without headers read the same records`() {
        let output =
            Self.record("M", "a.swift", new: Self.zero) + Self.record("R100", "b.swift", "c.swift")
            + Self.record("A", "d.swift", old: Self.zero, new: Self.zero)

        #expect(
            GitParsers.rawChanges(Data(output.utf8)) == [
                GitFileChange(status: .modified, path: "a.swift", oldBlobID: Self.blobA),
                GitFileChange(
                    status: .renamed, path: "c.swift", oldPath: "b.swift", oldBlobID: Self.blobA, newBlobID: Self.blobB),
                GitFileChange(status: .added, path: "d.swift")
            ])
    }
}
