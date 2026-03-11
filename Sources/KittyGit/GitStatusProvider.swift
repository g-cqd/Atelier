import Foundation
import KittyFileTree
import KittySync

public final class GitStatusProvider: FileStatusProvider, @unchecked Sendable {
    private struct State: Sendable {
        var statuses: [String: FileStatus] = [:]
        var branch: String?
        var summary: FileStatusSummary = FileStatusSummary()
    }

    private let rootPath: String
    private let lock: StateLock<State>

    public init(rootPath: String) {
        self.rootPath = Self.normalizePath(rootPath)
        self.lock = StateLock(initialState: State())
    }

    public func status(for path: String) -> FileStatus? {
        let normalizedPath = Self.normalizePath(path)
        return lock.withLock { state in
            state.statuses[normalizedPath]
        }
    }

    public var branchName: String? {
        lock.withLock { $0.branch }
    }

    public var summary: FileStatusSummary {
        lock.withLock { $0.summary }
    }

    public func refresh() async {
        let branch = await readBranch()
        let (statuses, summary) = await readStatuses()
        lock.withLock { state in
            state.branch = branch
            state.statuses = statuses
            state.summary = summary
        }
    }

    // MARK: - Git commands

    private func readBranch() async -> String? {
        let output = await runGit(arguments: ["branch", "--show-current"])
        let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func readStatuses() async -> ([String: FileStatus], FileStatusSummary) {
        guard let output = await runGit(arguments: ["status", "--porcelain=v1"]) else {
            return ([:], FileStatusSummary())
        }
        return parseGitStatus(output, rootPath: rootPath)
    }

    private func runGit(arguments: [String]) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: rootPath)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Parsing

    func parseGitStatus(_ output: String, rootPath: String) -> ([String: FileStatus], FileStatusSummary) {
        var statuses: [String: FileStatus] = [:]
        var summary = FileStatusSummary()
        let normalizedRoot = Self.normalizePath(rootPath)
        let root = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.count >= 4 else { continue }
            let index = line.index(line.startIndex, offsetBy: 0)
            let worktree = line.index(line.startIndex, offsetBy: 1)
            let pathStart = line.index(line.startIndex, offsetBy: 3)
            let x = line[index]
            let y = line[worktree]
            var relativePath = String(line[pathStart...])

            // Handle renamed files: "R  old -> new"
            if let arrowRange = relativePath.range(of: " -> ") {
                relativePath = String(relativePath[arrowRange.upperBound...])
            }

            let absolutePath = Self.normalizePath(root + relativePath)
            let status = mapStatus(x: x, y: y)
            statuses[absolutePath] = status

            switch status {
            case .modified, .renamed: summary.modified += 1
            case .added: summary.added += 1
            case .untracked: summary.untracked += 1
            case .deleted: summary.deleted += 1
            case .conflicted: summary.conflicted += 1
            case .ignored, .clean: break
            }

            // Propagate status to parent directories
            propagateToParents(absolutePath, status: status, root: root, into: &statuses)
        }

        return (statuses, summary)
    }

    private func mapStatus(x: Character, y: Character) -> FileStatus {
        // Conflicts
        if (x == "U" || y == "U") || (x == "A" && y == "A") || (x == "D" && y == "D") {
            return .conflicted
        }
        // Untracked
        if x == "?" && y == "?" {
            return .untracked
        }
        // Ignored
        if x == "!" && y == "!" {
            return .ignored
        }
        // Renamed
        if x == "R" {
            return .renamed
        }
        // Added
        if x == "A" && y != "M" {
            return .added
        }
        // Deleted
        if x == "D" || y == "D" {
            return .deleted
        }
        // Modified (any other change)
        return .modified
    }

    private func propagateToParents(_ path: String, status: FileStatus, root: String, into statuses: inout [String: FileStatus]) {
        var current = (path as NSString).deletingLastPathComponent
        while current.hasPrefix(root) || current + "/" == root {
            if current.count < root.count { break }
            let existing = statuses[current]
            if existing == nil || severity(of: status) > severity(of: existing!) {
                statuses[current] = status
            }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current { break }
            current = parent
        }
    }

    private func severity(of status: FileStatus) -> Int {
        switch status {
        case .conflicted: return 5
        case .deleted: return 4
        case .modified, .renamed: return 3
        case .added: return 2
        case .untracked: return 1
        case .ignored, .clean: return 0
        }
    }

    // MARK: - Repository detection

    public static func isGitRepository(_ path: String) -> Bool {
        repositoryRoot(for: path) != nil
    }

    public static func repositoryRoot(for path: String) -> String? {
        let root = runGitSync(arguments: ["-C", path, "rev-parse", "--show-toplevel"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return nil }
        return normalizePath(root)
    }

    private static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func runGitSync(arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ""
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
