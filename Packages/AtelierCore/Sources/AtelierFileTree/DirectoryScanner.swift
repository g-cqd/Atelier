public import AemiRuntime
import Foundation
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
    ///   - withinRoot: The symlink containment boundary: an entry whose resolved
    ///     path escapes it is skipped. Defaults to `path`; recursive scans of
    ///     subdirectories pass the workspace root so deep symlinks are checked
    ///     against the workspace.
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

    /// Directories ``scanAsync(_:maxDepth:maxEntries:visibility:withinRoot:pool:)`` lists at once: a wide tree queues
    /// a few listings on the pool instead of starting a task for every directory.
    public static let listingConcurrency = 4

    /// Scans `path` as ``scan(_:maxDepth:maxEntries:visibility:withinRoot:)`` does, a level at a time: the directories
    /// of a level are listed side by side on `pool`, at most ``listingConcurrency`` at once, so that no directory read
    /// blocks a cooperative thread. The entry cap is spent level by level, so a capped scan keeps the shallow entries.
    ///
    /// - Parameters:
    ///   - path: Absolute path of the directory to scan.
    ///   - maxDepth: Maximum recursion depth. `0` returns only direct children.
    ///   - maxEntries: Hard cap on the total number of entries listed.
    ///   - visibility: Hidden-file inclusion policy.
    ///   - withinRoot: See ``scan(_:maxDepth:maxEntries:visibility:withinRoot:)``.
    ///   - pool: The threads directories are read on: the app's pool.
    /// - Returns: Sorted entries — directories first, then files, each group
    ///   sorted case-insensitively by name.
    /// - Throws: `CancellationError` when the task is cancelled.
    public static func scanAsync(
        _ path: String,
        maxDepth: Int = defaultMaxDepth,
        maxEntries: Int = defaultMaxEntries,
        visibility: FileVisibility = .defaultHidden,
        withinRoot: String? = nil,
        pool: BlockingOffloadPool
    ) async throws -> [FileNode] {
        try await scanAsync(
            path, maxDepth: maxDepth, maxEntries: maxEntries, visibility: visibility, withinRoot: withinRoot,
            offload: pool)
    }

    /// ``scanAsync(_:maxDepth:maxEntries:visibility:withinRoot:pool:)`` over any ``BlockingOffload``; a test's spy
    /// counts the listings in flight.
    static func scanAsync(
        _ path: String,
        maxDepth: Int,
        maxEntries: Int,
        visibility: FileVisibility,
        withinRoot: String?,
        offload: any BlockingOffload
    ) async throws -> [FileNode] {
        let root = withinRoot ?? path
        var listings: [String: [Item]] = [:]
        var level = [path]
        var remaining = maxEntries
        var depth = 0
        while !level.isEmpty, remaining > 0 {
            try Task.checkCancellation()
            let listed = try await mapConcurrently(level, limit: listingConcurrency) { directory in
                try await offload.run { items(in: directory, root: root, visibility: visibility) }
            }
            var next: [String] = []
            for (directory, items) in zip(level, listed) where remaining > 0 {
                let kept = Array(items.prefix(remaining))
                remaining -= kept.count
                listings[directory] = kept
                if depth < maxDepth { next += kept.filter(\.isDirectory).map(\.path) }
            }
            level = next
            depth += 1
        }
        return nodes(in: path, listings: listings)
    }

    /// An entry a scan shows, before the tree is built.
    private struct Item: Sendable {
        let name: String
        let path: String
        let isDirectory: Bool
    }

    /// `directory`'s entries a scan shows, sorted by name: those `visibility` includes whose path resolves inside
    /// `root`. Blocks on the file system.
    private static func items(in directory: String, root: String, visibility: FileVisibility) -> [Item] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
        var items: [Item] = []
        for name in names.sorted() {
            let fullPath = FilePath(directory).appending(name).string
            guard visibility.shouldInclude(name: name, path: fullPath) else { continue }
            guard SecurePath.isValid(fullPath, root: root) else { continue }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            items.append(Item(name: name, path: fullPath, isDirectory: isDir.boolValue))
        }
        return items
    }

    /// The nodes of `directory`, from the listings a scan made: a directory it did not list has no children.
    private static func nodes(in directory: String, listings: [String: [Item]]) -> [FileNode] {
        sortEntries(
            (listings[directory] ?? [])
                .map { item in
                    FileNode(
                        name: item.name, path: item.path, isDirectory: item.isDirectory,
                        children: item.isDirectory ? nodes(in: item.path, listings: listings) : [])
                })
    }

    // MARK: - Synchronous

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

    // MARK: - Shared helpers

    /// Sorts entries: directories first, then files, case-insensitive within each group.
    private static func sortEntries(_ entries: [FileNode]) -> [FileNode] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
