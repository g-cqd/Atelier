import Foundation

/// Where a repository's git metadata lives. A linked worktree's `.git` is a file pointing (`gitdir:`) to a private
/// git dir holding its `HEAD`, which in turn points (`commondir`) to the refs every worktree shares.
package struct GitMetadataLocation: Equatable, Sendable {
    /// This worktree's own git dir, where its `HEAD` lives; in a plain repository, `<root>/.git` and equal to
    /// ``commonDir``.
    package let gitDir: String
    /// Where the refs every worktree of the same repository shares live.
    package let commonDir: String
}

extension GitMetadataLocation {
    /// Resolves `root`'s metadata from its `.git` entry and, for a linked worktree, the `commondir` file of the git
    /// dir it points to, touching storage only through `read`. A `.git` that is no `gitdir:` pointer resolves both
    /// locations to `<root>/.git`, and a worktree without a readable `commondir` shares its own git dir.
    ///
    /// - Parameters:
    ///   - root: The repository's absolute working-tree root.
    ///   - read: A file's full text, or nil when it is missing, a directory or unreadable.
    /// - Returns: The resolved locations, as absolute paths without a trailing `/`.
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

    /// The trimmed path after `gitdir:` on the first line starting with it, or nil when there is none.
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

    /// Collapses `.` and `..` components and drops a trailing slash, matching ``RepositoryFreshness``'s paths.
    private static func normalized(_ path: String) -> String {
        var normalized = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
        if normalized.count > 1, normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
