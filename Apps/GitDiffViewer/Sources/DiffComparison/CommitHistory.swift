package import DiffGit
package import Foundation

/// The git history a commit grouping reads, over any repository: ancestry, pages of commits and the working tree's
/// own changes, each through a ``GitClient`` on the app's hardened runner (GIT-06).
package struct CommitHistory: Sendable {
    /// The budget of one git run, as the source loader gives its own.
    package static let timeout: Duration = .seconds(60)

    private let runner: any ProcessRunner
    private let gate: GitConfigGate

    /// - Parameters:
    ///   - runner: How git is spawned; the app's runner, or a scripted one in a test.
    ///   - gate: Where each repository's configuration verdict is cached; the shared one unless a test wants its own.
    package init(runner: any ProcessRunner, gate: GitConfigGate = .shared) {
        self.runner = runner
        self.gate = gate
    }

    private func git(_ repository: URL) -> GitClient {
        GitClient(repository: repository, runner: runner, timeout: Self.timeout, gate: gate)
    }

    package func resolve(_ ref: String, in repository: URL) async throws -> String {
        try await git(repository).resolve(ref: ref)
    }

    /// How `base` and `tip` relate: `tip` descends from `base`, the reverse, a fork from their merge base, or nothing
    /// in common. Git's failures become ``CommitGroupingAncestry/unreadable(_:)``; a cancellation is thrown.
    package func ancestry(of base: String, and tip: String, in repository: URL) async throws -> CommitGroupingAncestry {
        let git = git(repository)
        do {
            if try await git.isAncestor(base, of: tip) { return .leftIsAncestor }
            if try await git.isAncestor(tip, of: base) { return .rightIsAncestor }
            guard let mergeBase = try await git.mergeBase(base, tip) else { return .unrelated }
            return .diverged(mergeBase: mergeBase)
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    package func commitCount(from base: String, to tip: String, in repository: URL) async throws -> Int {
        try await git(repository).commitCount(from: base, to: tip, firstParent: true)
    }

    package func commitChanges(
        from base: String, to tip: String, firstParent: Bool, limit: Int, in repository: URL
    ) async throws -> GitCommitPage {
        try await git(repository).commitChanges(from: base, to: tip, firstParent: firstParent, limit: limit)
    }

    package func uncommittedChanges(in repository: URL) async throws -> [GitFileChange] {
        try await git(repository).uncommittedChanges()
    }
}
