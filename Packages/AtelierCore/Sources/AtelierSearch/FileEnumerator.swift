import Foundation

/// The files a workspace search reads under `rootPath`, listed without being opened: the search's own read skips
/// binary and oversized files, so that each file is opened once.
/// - Parameters:
///   - rootPath: The folder to walk.
///   - excludeGlobs: Names of directories and files left out wherever they appear.
///   - includeHidden: Whether names starting with a dot are listed.
///   - gitIgnoredPaths: Absolute paths of the files git ignores.
/// - Returns: Absolute paths, symbolic links resolved.
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

        results.append(absolutePath)
    }

    return results
}
