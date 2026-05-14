import Foundation
import KittySync
import System

/// Recursively scans a directory tree into an array of ``FileNode`` values.
///
/// Hidden entries (those whose names start with `.`) are skipped. The scan
/// is bounded by ``defaultMaxDepth`` and ``defaultMaxEntries`` to prevent
/// runaway traversal in very large trees. Symlinks that resolve outside the
/// root are silently skipped as a path-traversal defence.
public enum DirectoryScanner {
    /// Default maximum number of filesystem entries visited in a single scan.
    public static let defaultMaxEntries = 10_000

    /// Default maximum directory recursion depth.
    public static let defaultMaxDepth = 10

    /// Scans `path` and returns its contents as a sorted ``FileNode`` array.
    ///
    /// - Parameters:
    ///   - path: Absolute path of the directory to scan.
    ///   - maxDepth: Maximum recursion depth. `0` returns only direct children.
    ///   - maxEntries: Hard cap on the total number of entries visited.
    ///   - visibility: Hidden-file inclusion policy.
    ///   - withinRoot: Optional containment boundary used by the symlink-
    ///     traversal defence. Every entry whose resolved real path escapes
    ///     this root is silently skipped. Defaults to the scanned `path`
    ///     (treats the scan directory as its own root). When recursive
    ///     scans are launched for subdirectories, pass the workspace root
    ///     here so symlinks under nested subdirectories are still checked
    ///     against the workspace, not against the immediate parent.
    /// - Returns: Sorted entries — directories first, then files, each group
    ///   sorted case-insensitively by name.
    public static func scan(
        _ path: String,
        maxDepth: Int = defaultMaxDepth,
        maxEntries: Int = defaultMaxEntries,
        visibility: FileVisibility = .defaultHidden,
        withinRoot: String? = nil
    ) -> [FileNode] {
        var count = 0
        let root = withinRoot ?? path
        return scanDirectory(
            path, root: root, maxDepth: maxDepth, maxEntries: maxEntries, visibility: visibility,
            entryCount: &count)
    }

    /// Async variant that parallelizes subdirectory scanning using a TaskGroup.
    ///
    /// Top-level directory entries are enumerated sequentially (for entry count
    /// tracking), but subdirectory recursion is dispatched concurrently across
    /// cores. Falls back to sequential scanning for shallow depths.
    ///
    /// - Parameters:
    ///   - path: Absolute path of the directory to scan.
    ///   - maxDepth: Maximum recursion depth. `0` returns only direct children.
    ///   - maxEntries: Hard cap on the total number of entries visited.
    ///   - visibility: Hidden-file inclusion policy.
    ///   - withinRoot: See ``scan(_:maxDepth:maxEntries:visibility:withinRoot:)``.
    /// - Returns: Sorted entries — directories first, then files, each group
    ///   sorted case-insensitively by name.
    public static func scanAsync(
        _ path: String,
        maxDepth: Int = defaultMaxDepth,
        maxEntries: Int = defaultMaxEntries,
        visibility: FileVisibility = .defaultHidden,
        withinRoot: String? = nil
    ) async -> [FileNode] {
        let counter = EntryCounter(limit: maxEntries)
        let root = withinRoot ?? path
        return await scanDirectoryAsync(
            path, root: root, maxDepth: maxDepth, visibility: visibility, counter: counter)
    }

    // MARK: - Synchronous (original)

    private static func scanDirectory(
        _ path: String,
        root: String,
        maxDepth: Int,
        maxEntries: Int,
        visibility: FileVisibility,
        entryCount: inout Int
    ) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [FileNode] = []

        for item in items.sorted() {
            guard entryCount < maxEntries else { break }
            let fullPath = FilePath(path).appending(item).string

            guard visibility.shouldInclude(name: item, path: fullPath) else { continue }
            guard SecurePath.isValid(fullPath, root: root) else { continue }

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            entryCount += 1

            var children: [FileNode] = []
            if isDir.boolValue && maxDepth > 0 {
                children = scanDirectory(
                    fullPath,
                    root: root,
                    maxDepth: maxDepth - 1,
                    maxEntries: maxEntries,
                    visibility: visibility,
                    entryCount: &entryCount
                )
            }
            entries.append(
                FileNode(
                    name: item, path: fullPath, isDirectory: isDir.boolValue, children: children))
        }

        return sortEntries(entries)
    }

    // MARK: - Async parallel

    /// Thread-safe atomic counter for bounding total entries across tasks.
    private final class EntryCounter: Sendable {
        private let counterValue = StateLock(initialState: 0)
        private let _limit: Int

        var limit: Int { _limit }

        init(limit: Int) {
            self._limit = limit
        }

        /// Attempts to increment the counter. Returns `true` if under the limit.
        func tryIncrement() -> Bool {
            return counterValue.withLock { count in
                guard count < _limit else { return false }
                count += 1
                return true
            }
        }

        /// Returns the current count.
        var count: Int {
            return counterValue.withLock { $0 }
        }
    }

    private static func scanDirectoryAsync(
        _ path: String,
        root: String,
        maxDepth: Int,
        visibility: FileVisibility,
        counter: EntryCounter
    ) async -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        // Classify entries into files and directories
        var fileEntries: [FileNode] = []
        var dirItems: [(name: String, path: String)] = []

        for item in items.sorted() {
            guard counter.tryIncrement() else { break }
            let fullPath = FilePath(path).appending(item).string

            guard visibility.shouldInclude(name: item, path: fullPath) else { continue }
            guard SecurePath.isValid(fullPath, root: root) else { continue }

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            if isDir.boolValue {
                dirItems.append((name: item, path: fullPath))
            } else {
                fileEntries.append(FileNode(name: item, path: fullPath, isDirectory: false))
            }
        }

        // Scan subdirectories in parallel if depth allows
        var dirEntries: [FileNode] = []
        if maxDepth > 0 && !dirItems.isEmpty {
            dirEntries = await withTaskGroup(of: (Int, FileNode).self) { group in
                for (idx, dir) in dirItems.enumerated() {
                    group.addTask {
                        let children = await scanDirectoryAsync(
                            dir.path,
                            root: root,
                            maxDepth: maxDepth - 1,
                            visibility: visibility,
                            counter: counter
                        )
                        return (
                            idx,
                            FileNode(
                                name: dir.name, path: dir.path, isDirectory: true,
                                children: children)
                        )
                    }
                }

                var results: [(Int, FileNode)] = []
                for await result in group {
                    results.append(result)
                }
                // Sort by original index to maintain deterministic order
                return results.sorted { $0.0 < $1.0 }.map(\.1)
            }
        } else {
            // No recursion — just create empty-children directory nodes
            dirEntries = dirItems.map { FileNode(name: $0.name, path: $0.path, isDirectory: true) }
        }

        return sortEntries(dirEntries + fileEntries)
    }

    // MARK: - Shared helpers

    /// Sorts entries: directories first, then files, case-insensitive within each group.
    private static func sortEntries(_ entries: [FileNode]) -> [FileNode] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

}
