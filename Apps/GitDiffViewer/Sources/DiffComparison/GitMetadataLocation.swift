import Foundation

/// Where a repository's git metadata actually lives, resolved from its root's `.git` entry: an ordinary
/// repository's `.git` is a directory holding everything (`HEAD`, `refs`, `packed-refs`, objects); a linked
/// worktree's `.git` is instead a *file* naming its own private git dir elsewhere (`gitdir: <path>`) -- that
/// private dir holds the worktree's own `HEAD` and index, and in turn names the common dir every worktree of the
/// same repository shares (`commondir: <path>`, usually relative) for `refs`, `packed-refs` and objects.
///
/// A watcher that only ever looks under `<root>/.git` never sees a linked worktree's real `HEAD` or refs moving:
/// both live outside `root` entirely.
package struct GitMetadataLocation: Equatable, Sendable {
    /// This worktree's own git dir: where its private `HEAD` lives. The repository root's `.git` directory itself
    /// for a plain (non-worktree) repository, so `gitDir == commonDir` there.
    package let gitDir: String
    /// Where the refs every worktree of the same repository shares live.
    package let commonDir: String
}

extension GitMetadataLocation {
    /// Resolves `root`'s actual git metadata locations by reading its `.git` entry and, for a linked worktree,
    /// the `commondir` file inside the git dir it points to. Pure and disk-access-free -- `read` is the only seam
    /// touching storage, so a test substitutes an in-memory map instead of real files -- and every returned path
    /// is absolute and slash-normalized (no trailing `/`), matching ``RepositoryFreshness``'s own path convention.
    ///
    /// Falls back to treating `.git` as an ordinary directory (`gitDir == commonDir == "<root>/.git"`) whenever
    /// `.git` cannot be read as a worktree pointer file: it truly is a directory, it does not exist yet, or its
    /// first line is not a `gitdir:` pointer. The same fallback applies one level in when a resolved worktree git
    /// dir has no readable `commondir` file, so a repository layout this cannot make sense of never loses its
    /// working-tree watch entirely, only the (best-effort) worktree-specific correction.
    ///
    /// - Parameters:
    ///   - root: The repository's working-tree root, absolute, whose `.git` entry is resolved.
    ///   - read: Returns a file's full text contents, or nil when it cannot be read (missing, a directory,
    ///     unreadable) — the same seam ``RepositoryFreshness``'s production resolver backs with
    ///     `String(contentsOfFile:)`.
    /// - Returns: Where this repository's metadata actually lives, per the fallbacks described above.
    package static func resolve(root: String, read: (String) -> String?) -> GitMetadataLocation {
        let dotGitPath = Self.normalized(root + "/.git")
        guard let pointer = Self.gitdirPointer(in: read(dotGitPath)) else {
            return GitMetadataLocation(gitDir: dotGitPath, commonDir: dotGitPath)
        }
        let gitDir = Self.resolved(pointer, relativeTo: dotGitPath)
        guard let commonPointer = read(gitDir + "/commondir")?.trimmingCharacters(in: .whitespacesAndNewlines),
            !commonPointer.isEmpty
        else {
            return GitMetadataLocation(gitDir: gitDir, commonDir: gitDir)
        }
        let commonDir = Self.resolved(commonPointer, relativeTo: gitDir)
        return GitMetadataLocation(gitDir: gitDir, commonDir: commonDir)
    }

    /// The path after `gitdir:` on the first line that starts with it, trimmed -- or nil when `contents` is nil
    /// (unreadable, or `.git` is a plain directory) or has no such line (an unrecognized `.git` file, treated the
    /// same as a plain directory rather than guessed at).
    private static func gitdirPointer(in contents: String?) -> String? {
        guard let contents else { return nil }
        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("gitdir:") else { continue }
            let path = trimmed.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            return path.isEmpty ? nil : path
        }
        return nil
    }

    /// `path` resolved against `base` (its directory, when `path` is relative) and slash-normalized.
    private static func resolved(_ path: String, relativeTo base: String) -> String {
        path.hasPrefix("/")
            ? Self.normalized(path)
            : Self.normalized(base + "/" + path)
    }

    /// Collapses `.`/`..` components and drops a trailing slash, the way ``RepositoryFreshness``'s own
    /// `normalizedPath(_:)` does for every other path it compares — every path this resolves is compared against
    /// (or used to build children of) paths normalized that same way.
    private static func normalized(_ path: String) -> String {
        var normalized = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
        if normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
