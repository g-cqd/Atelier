import Foundation
import Testing

@testable import AtelierGit

/// A repository without a commit yet, the state `git init` leaves: its `HEAD` has the empty tree and no history, and
/// it is still a repository.
struct GitUnbornBranchTests {
    @Test
    func `HEAD of a repository without commits lists an empty tree`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }
        try repository.write("a.txt", "a\n")

        let entries = try await repository.client().tree(at: "HEAD", isSupported: { _ in true })

        #expect(entries.isEmpty)
    }

    @Test
    func `the unborn branch's own name lists an empty tree too`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }

        let entries = try await repository.client().tree(at: "main", isSupported: { _ in true })

        #expect(entries.isEmpty)
    }

    @Test
    func `a repository without commits has an empty history`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }

        let info = try await repository.client().info()

        #expect(info.commits.isEmpty)
    }

    @Test
    func `a ref that names nothing still fails in a repository without commits`() async throws {
        let repository = try GitHistoryRepository()
        defer { repository.remove() }

        await #expect(throws: GitError.self) {
            try await repository.client().tree(at: "nope", isSupported: { _ in true })
        }
    }
}
