public import AtelierProcess
import Foundation
import System

import struct AtelierGit.GitClient

/// Controls which files are shown in the file tree.
public enum FileVisibility: Sendable {
    /// Default: skip dotfiles.
    case defaultHidden
    /// Show dotfiles, but skip gitignored entries.
    case gitFiltered(ignoredPaths: Set<String>)
    /// Show everything including hidden and gitignored.
    case showAll

    public var label: String {
        switch self {
            case .defaultHidden: return "Default"
            case .gitFiltered: return "Git"
            case .showAll: return "All"
        }
    }

    /// Returns `true` if the entry with the given name and full path should be included.
    func shouldInclude(name: String, path: String) -> Bool {
        switch self {
            case .defaultHidden:
                return !name.hasPrefix(".")
            case .gitFiltered(let ignored):
                return !ignored.contains(path)
            case .showAll:
                return true
        }
    }
}

/// Computes the set of gitignored paths under a root directory using `git ls-files`.
public enum GitIgnoreChecker {
    /// - Parameters:
    ///   - rootPath: The repository root to scan.
    ///   - runner: How git is spawned; the app owns the pool behind it, tests inject a fake.
    /// - Returns: The absolute paths of every file git ignores under `rootPath`.
    public static func ignoredPaths(in rootPath: String, runner: any ProcessRunner) async -> Set<String> {
        let client = GitClient(repository: URL(fileURLWithPath: rootPath), runner: runner)
        guard let relativePaths = try? await client.ignoredPaths() else { return [] }
        var paths = Set<String>()
        for relative in relativePaths {
            var trimmed = relative
            if trimmed.hasSuffix("/") { trimmed.removeLast() }
            paths.insert(FilePath(rootPath).appending(trimmed).string)
        }
        return paths
    }
}
