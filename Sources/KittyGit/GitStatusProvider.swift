import Foundation
import KittyFileTree
import KittySync

public final class GitStatusProvider: FileStatusProvider, GitLineDecorationProvider,
    @unchecked Sendable
{
    private enum BaseContent: Sendable {
        case missing
        case text(String)
    }

    private struct State: Sendable {
        var statuses: [String: FileStatus] = [:]
        var branch: String?
        var summary: FileStatusSummary = FileStatusSummary()
        var baseContents: [String: BaseContent] = [:]
    }

    private let rootPath: String
    private let lock: StateLock<State>
    private let inFlightLock = StateLock(initialState: [String: Task<BaseContent, Never>]())

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
            state.baseContents.removeAll(keepingCapacity: true)
        }
    }

    public func lineDecorations(for path: String, lines: [String]) async -> GitLineDecorations {
        let normalizedPath = Self.normalizePath(path)
        let status = status(for: normalizedPath)

        if lines.isEmpty {
            return .empty
        }

        if status == .untracked {
            return Self.addedLineDecorations(for: lines, color: .untracked)
        }

        guard let relativePath = relativePath(for: normalizedPath) else {
            return .empty
        }

        let baseContent = await readBaseContent(for: normalizedPath, relativePath: relativePath)
        switch baseContent {
        case .missing:
            guard status == .added else {
                return .empty
            }
            return Self.addedLineDecorations(for: lines, color: .added)
        case .text(let content):
            let addedColor: FileStatusColor = status == .untracked ? .untracked : .added
            let baseLines = Self.splitLines(content)
            return makeLineDecorations(
                baseLines: baseLines, currentLines: lines, addedColor: addedColor)
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

    private func readBaseContent(for normalizedPath: String, relativePath: String) async
        -> BaseContent
    {
        if let cached = lock.withLock({ $0.baseContents[normalizedPath] }) {
            return cached
        }

        let task: Task<BaseContent, Never> = inFlightLock.withLock { inFlight in
            if let existing = inFlight[normalizedPath] {
                return existing
            }
            let newTask = Task<BaseContent, Never> {
                await loadBaseContent(relativePath: relativePath)
            }
            inFlight[normalizedPath] = newTask
            return newTask
        }

        let content = await task.value
        lock.withLock { $0.baseContents[normalizedPath] = content }
        inFlightLock.withLock { $0[normalizedPath] = nil }
        return content
    }

    private func loadBaseContent(relativePath: String) async -> BaseContent {
        guard let output = await runGit(arguments: ["show", "HEAD:\(relativePath)"]) else {
            return .missing
        }
        return .text(output)
    }

    // MARK: - Parsing

    func parseGitStatus(_ output: String, rootPath: String) -> (
        [String: FileStatus], FileStatusSummary
    ) {
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

    private func propagateToParents(
        _ path: String, status: FileStatus, root: String, into statuses: inout [String: FileStatus]
    ) {
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

    private func relativePath(for normalizedPath: String) -> String? {
        guard normalizedPath != rootPath else { return nil }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard normalizedPath.hasPrefix(rootPrefix) else {
            return nil
        }

        return String(normalizedPath.dropFirst(rootPrefix.count))
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

    static func splitLines(_ content: String) -> [String] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(
            String.init)
        return lines.isEmpty ? [""] : lines
    }

    static func addedLineDecorations(for lines: [String], color: FileStatusColor)
        -> GitLineDecorations
    {
        guard !lines.isEmpty else { return .empty }
        return GitLineDecorations(
            markers: Dictionary(uniqueKeysWithValues: lines.indices.map { ($0, color) })
        )
    }

    func makeLineDecorations(
        baseLines: [String],
        currentLines: [String],
        addedColor: FileStatusColor
    ) -> GitLineDecorations {
        guard !currentLines.isEmpty else {
            return .empty
        }

        let difference = currentLines.difference(from: baseLines)
        let removalOffsets = difference.removals.compactMap { change -> Int? in
            if case .remove(let offset, _, _) = change { return offset }
            return nil
        }.sorted()
        let insertionOffsets = difference.insertions.compactMap { change -> Int? in
            if case .insert(let offset, _, _) = change { return offset }
            return nil
        }.sorted()

        if removalOffsets.isEmpty, insertionOffsets.isEmpty {
            return .empty
        }

        var markers: [Int: FileStatusColor] = [:]
        var baseIndex = 0
        var currentIndex = 0
        var removalIndex = 0
        var insertionIndex = 0

        while baseIndex < baseLines.count || currentIndex < currentLines.count {
            let removalCount = Self.consumeConsecutiveOffsets(
                removalOffsets,
                index: &removalIndex,
                startingAt: baseIndex
            )
            let insertionCount = Self.consumeConsecutiveOffsets(
                insertionOffsets,
                index: &insertionIndex,
                startingAt: currentIndex
            )

            if removalCount == 0, insertionCount == 0 {
                if baseIndex < baseLines.count {
                    baseIndex += 1
                }
                if currentIndex < currentLines.count {
                    currentIndex += 1
                }
                continue
            }

            let modifiedCount = min(removalCount, insertionCount)
            for offset in 0..<modifiedCount {
                markers[currentIndex + offset] = .modified
            }

            if insertionCount > modifiedCount {
                for offset in modifiedCount..<insertionCount {
                    Self.mergeMarker(addedColor, into: &markers, at: currentIndex + offset)
                }
            }

            if removalCount > insertionCount {
                let anchor = min(currentIndex + modifiedCount, max(0, currentLines.count - 1))
                Self.mergeMarker(.deleted, into: &markers, at: anchor)
            }

            baseIndex += removalCount
            currentIndex += insertionCount
        }

        return GitLineDecorations(markers: markers)
    }

    private static func consumeConsecutiveOffsets(
        _ offsets: [Int],
        index: inout Int,
        startingAt start: Int
    ) -> Int {
        guard index < offsets.count, offsets[index] == start else {
            return 0
        }

        var count = 0
        var expected = start
        while index < offsets.count, offsets[index] == expected {
            count += 1
            index += 1
            expected += 1
        }
        return count
    }

    private static func mergeMarker(
        _ incoming: FileStatusColor,
        into markers: inout [Int: FileStatusColor],
        at index: Int
    ) {
        let existing = markers[index]
        if existing == nil || markerPriority(of: incoming) > markerPriority(of: existing!) {
            markers[index] = incoming
        }
    }

    private static func markerPriority(of color: FileStatusColor) -> Int {
        switch color {
        case .deleted: return 4
        case .modified: return 3
        case .added: return 2
        case .untracked: return 1
        case .conflicted: return 5
        case .clean: return 0
        }
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
