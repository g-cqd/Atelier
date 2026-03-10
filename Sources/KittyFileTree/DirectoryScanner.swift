import Foundation
import KittySync

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
    /// - Returns: Sorted entries — directories first, then files, each group
    ///   sorted case-insensitively by name.
    public static func scan(
        _ path: String,
        maxDepth: Int = defaultMaxDepth,
        maxEntries: Int = defaultMaxEntries
    ) -> [FileNode] {
        var count = 0
        return scanDirectory(path, maxDepth: maxDepth, maxEntries: maxEntries, entryCount: &count)
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
    /// - Returns: Sorted entries — directories first, then files, each group
    ///   sorted case-insensitively by name.
    public static func scanAsync(
        _ path: String,
        maxDepth: Int = defaultMaxDepth,
        maxEntries: Int = defaultMaxEntries
    ) async -> [FileNode] {
        let counter = EntryCounter(limit: maxEntries)
        return await scanDirectoryAsync(path, maxDepth: maxDepth, counter: counter)
    }

    // MARK: - Synchronous (original)

    private static func scanDirectory(
        _ path: String,
        maxDepth: Int,
        maxEntries: Int,
        entryCount: inout Int
    ) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [FileNode] = []

        for item in items.sorted() where !item.hasPrefix(".") {
            guard entryCount < maxEntries else { break }
            let fullPath = (path as NSString).appendingPathComponent(item)

            guard isWithinRoot(fullPath, root: path) else { continue }

            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            entryCount += 1

            var children: [FileNode] = []
            if isDir.boolValue && maxDepth > 0 {
                children = scanDirectory(
                    fullPath,
                    maxDepth: maxDepth - 1,
                    maxEntries: maxEntries,
                    entryCount: &entryCount
                )
            }
            entries.append(FileNode(name: item, path: fullPath, isDirectory: isDir.boolValue, children: children))
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
        maxDepth: Int,
        counter: EntryCounter
    ) async -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }

        // Classify entries into files and directories
        var fileEntries: [FileNode] = []
        var dirItems: [(name: String, path: String)] = []

        for item in items.sorted() where !item.hasPrefix(".") {
            guard counter.tryIncrement() else { break }
            let fullPath = (path as NSString).appendingPathComponent(item)
            guard isWithinRoot(fullPath, root: path) else { continue }

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
                            maxDepth: maxDepth - 1,
                            counter: counter
                        )
                        return (idx, FileNode(name: dir.name, path: dir.path, isDirectory: true, children: children))
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

    /// Returns `true` when `path` resolves to a location inside `root`,
    /// guarding against symlink-based path traversal.
    private static func isWithinRoot(_ path: String, root: String) -> Bool {
        let resolved = (path as NSString).resolvingSymlinksInPath
        let resolvedRoot = (root as NSString).resolvingSymlinksInPath
        return resolved.hasPrefix(resolvedRoot)
    }
}
