public import AtelierGit
import Foundation

extension SourceLoader {
    /// Git's status of a folder inside a repository, through the hardened ``GitClient/status(includingIgnored:)``:
    /// every path relative to the folder, every entry outside it left out. Nil for any other source, and for a
    /// folder outside every repository. Ignored files are left out: a status is read for badges, which draw none,
    /// and listing them makes git walk every ignored directory.
    /// - Throws: ``GitError`` when git fails; `CancellationError` when the task is cancelled, which terminates git.
    public func workingTreeStatus(of source: ComparisonSource) async throws -> [GitStatusEntry]? {
        guard case .directory(let folder) = source,
            let root = await GitClient.repositoryRoot(containing: folder, runner: runner),
            let prefix = Self.prefix(of: folder, under: root)
        else { return nil }
        let status = try await GitClient(repository: root, runner: runner).status(includingIgnored: false)
        return Self.entries(status.entries, under: prefix)
    }

    /// The paths among `paths`, relative to the folder `source` names, that git ignores, through one
    /// ``GitClient/ignored(among:)`` run in that folder. Empty for any other source.
    /// - Throws: ``GitError`` when git fails, for example for a folder outside every repository.
    public func ignoredPaths(among paths: [String], in source: ComparisonSource) async throws -> Set<String> {
        guard case .directory(let folder) = source else { return [] }
        return try await GitClient(repository: folder, runner: runner).ignored(among: paths)
    }

    /// `folder`'s path below `root`, ending in `/`, or empty for `root` itself; nil when `folder` lies outside it.
    /// Both sides are compared with their symbolic links resolved, since git names the root by its real path:
    /// `/private/tmp/repo` for a folder chosen as `/tmp/repo`.
    static func prefix(of folder: URL, under root: URL) -> String? {
        let folderComponents = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard folderComponents.starts(with: rootComponents) else { return nil }
        let below = folderComponents.dropFirst(rootComponents.count)
        return below.isEmpty ? "" : below.joined(separator: "/") + "/"
    }

    /// `entries`, which git names from the repository root, as seen from the folder `prefix` names: a path below
    /// the folder loses the prefix, an original path outside it becomes nil, and every other entry, the folder's
    /// own included, is left out.
    /// - Complexity: O(entries)
    static func entries(_ entries: [GitStatusEntry], under prefix: String) -> [GitStatusEntry] {
        guard !prefix.isEmpty else { return entries }
        func relative(_ path: String) -> String? {
            guard path.hasPrefix(prefix), path != prefix else { return nil }
            return String(path.dropFirst(prefix.count))
        }
        return entries.compactMap { entry in
            guard let path = relative(entry.path) else { return nil }
            return GitStatusEntry(
                path: path, originalPath: entry.originalPath.flatMap(relative), status: entry.status,
                isSubmodule: entry.isSubmodule, indexStatus: entry.indexStatus, worktreeStatus: entry.worktreeStatus)
        }
    }
}
