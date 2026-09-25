import AtelierProcess
import Foundation

/// How two states of one repository relate in its history: which is an ancestor of which, where they meet, and how
/// many commits lie between them.
extension GitClient {
    /// Whether `ancestor` is an ancestor of `descendant`, a commit counting as its own ancestor, through
    /// `git merge-base --is-ancestor`, which answers with its exit status: 0 for yes, 1 for no.
    /// - Throws: ``GitError/invalidArgument(_:)`` for a ref git could read as an option, and ``GitError`` when git
    ///   fails otherwise, for example on a ref that names no commit (exit 128).
    public func isAncestor(_ ancestor: String, of descendant: String) async throws -> Bool {
        let output = try await runReadingStatus([
            "merge-base", "--is-ancestor", "--end-of-options", try Self.checked(ancestor),
            try Self.checked(descendant)
        ])
        switch output.terminationStatus {
            case 0: return true
            case 1: return false
            default: throw GitError.commandFailed(output.errorText)
        }
    }

    /// The best common ancestor of `first` and `second`, as a full commit id, or nil when their histories share no
    /// commit (`git merge-base` exits with 1 and prints nothing). Of several equally good bases, git's first is
    /// returned.
    /// - Throws: ``GitError/invalidArgument(_:)`` for a ref git could read as an option, and ``GitError`` when git
    ///   fails otherwise, for example on a ref that names no commit.
    public func mergeBase(_ first: String, _ second: String) async throws -> String? {
        let output = try await runReadingStatus([
            "merge-base", "--end-of-options", try Self.checked(first), try Self.checked(second)
        ])
        switch output.terminationStatus {
            case 0:
                let id = String(decoding: output.standardOutput, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { throw GitError.commandFailed("merge-base printed no commit") }
                return id
            case 1 where output.standardError.isEmpty:
                return nil
            default:
                throw GitError.commandFailed(output.errorText)
        }
    }

    /// How many commits `to` has that `from` has not (`git rev-list --count from..to`); with `firstParent`, only
    /// those on `to`'s first-parent chain, one per mainline commit, a merge counting once for its whole branch.
    /// - Throws: ``GitError/invalidArgument(_:)`` for a ref git could read as an option, and ``GitError`` when git
    ///   fails or prints something other than a count.
    public func commitCount(from: String, to: String, firstParent: Bool) async throws -> Int {
        let range = "\(try Self.checked(from))..\(try Self.checked(to))"
        let data = try await run(
            ["rev-list", "--count"] + (firstParent ? ["--first-parent"] : []) + ["--end-of-options", range])
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(text), count >= 0 else {
            throw GitError.commandFailed("could not parse a commit count from: \(text)")
        }
        return count
    }
}
