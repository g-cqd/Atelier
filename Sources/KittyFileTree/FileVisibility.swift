import Foundation

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
    public static func ignoredPaths(in rootPath: String) async -> Set<String> {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let result = computeIgnoredPaths(in: rootPath)
                continuation.resume(returning: result)
            }
        }
    }

    private static func computeIgnoredPaths(in rootPath: String) -> Set<String> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", rootPath, "ls-files", "--others", "--ignored", "--exclude-standard", "--directory"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            var paths = Set<String>()
            for line in output.split(separator: "\n") where !line.isEmpty {
                var relative = String(line)
                if relative.hasSuffix("/") { relative.removeLast() }
                let fullPath = (rootPath as NSString).appendingPathComponent(relative)
                paths.insert(fullPath)
            }
            return paths
        } catch {
            return []
        }
    }
}
