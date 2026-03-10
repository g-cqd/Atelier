import Foundation

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

        return entries.sorted { lhs, rhs in
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
