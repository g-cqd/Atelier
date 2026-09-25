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

    /// The commits `to` has that `from` has not, newest first, with the files each changed, `limit` at most: one page
    /// of `git log --raw -M`, renames detected per commit and copies read as additions.
    ///
    /// With `firstParent`, only `to`'s first-parent chain is walked, and each merge lists its whole diff against its
    /// first parent, so a merged branch reads as one commit. The next page is the same call with `to` set to the
    /// page's ``GitCommitPage/continuation``, which starts git's walk where this one ended; `--skip` would walk every
    /// listed commit again. Without `firstParent`, every commit is listed, parents before children
    /// (`--topo-order`), and a merge lists no files.
    ///
    /// The run goes through the client's hardened runner, with the isolation's pinned configuration: no signature
    /// program (`--no-show-signature`), no external diff or text conversion, no colour, no path made relative.
    /// - Throws: ``GitError/invalidArgument(_:)`` for a ref git could read as an option or a `limit` under 1, and
    ///   ``GitError`` when git fails.
    public func commitChanges(from: String, to: String, firstParent: Bool, limit: Int) async throws -> GitCommitPage {
        guard limit > 0 else { throw GitError.invalidArgument("a page of \(limit) commits") }
        let range = "\(try Self.checked(from))..\(try Self.checked(to))"
        let walk = firstParent ? ["--first-parent", "--diff-merges=first-parent"] : ["--topo-order"]
        let commits = GitParsers.commitChanges(
            try await run(
                [
                    "log", "--no-show-signature", "--no-ext-diff", "--no-textconv", "--no-color", "--no-relative",
                    "--no-abbrev", "--root", "--raw", "-M", "-z", GitParsers.commitChangesFormat
                ] + walk + ["-n", String(limit), "--end-of-options", range, "--"]))
        let oldestParent = commits.last?.parentIDs.first
        let isComplete = commits.count < limit || oldestParent == nil
        return GitCommitPage(
            commits: commits, isComplete: isComplete, continuation: firstParent && !isComplete ? oldestParent : nil)
    }
}
