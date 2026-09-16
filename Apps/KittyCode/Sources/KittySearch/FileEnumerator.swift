import Foundation

public func enumerateSearchableFiles(
    rootPath: String,
    excludeGlobs: [String] = [".git", ".build", "build"],
    includeHidden: Bool = false,
    gitIgnoredPaths: Set<String> = []
) -> [String] {
    let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true).resolvingSymlinksInPath()
    let fm = FileManager.default

    guard
        let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: includeHidden ? [] : [.skipsHiddenFiles]
        )
    else {
        return []
    }

    let excludeSet = Set(excludeGlobs)
    var results: [String] = []

    for case let fileURL as URL in enumerator {
        let fileName = fileURL.lastPathComponent

        // Skip excluded directory names
        if excludeSet.contains(fileName) {
            enumerator.skipDescendants()
            continue
        }

        let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues?.isRegularFile == true else { continue }

        let absolutePath = fileURL.resolvingSymlinksInPath().path

        // Skip gitignored paths
        if gitIgnoredPaths.contains(absolutePath) { continue }

        // Skip binary files (check first 8KB for null bytes)
        if isBinaryFile(at: absolutePath) { continue }

        results.append(absolutePath)
    }

    return results
}

private func isBinaryFile(at path: String) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else { return false }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 8192) else { return false }
    return data.contains(0)
}
