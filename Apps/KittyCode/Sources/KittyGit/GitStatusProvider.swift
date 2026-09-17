import AtelierDiff
public import AtelierGit
public import AtelierProcess
import Foundation
public import KittyFileTree
import Synchronization

/// The working tree's git statuses and per-line change markers for open buffers, read through the core git
/// client under strict isolation, cached until the next refresh.
public final class GitStatusProvider: FileStatusProvider, GitLineDecorationProvider, Sendable {
    private enum BaseContent: Sendable {
        case missing
        case text(String, lines: [Substring])
    }

    private struct State: Sendable {
        var statuses: [String: FileStatus] = [:]
        var branch: String?
        var summary = FileStatusSummary()
        var baseContents: [String: BaseContent] = [:]
    }

    /// A hung `git` must never freeze the editor: every run gets this long on the runner's clock.
    public static let gitTimeout: Duration = .seconds(10)

    private let rootPath: String
    private let client: GitClient
    private let lock: Mutex<State>
    private let inFlightLock = Mutex([String: Task<BaseContent, Never>]())

    /// - Parameters:
    ///   - rootPath: The repository root every git invocation runs in.
    ///   - runner: How `git` is spawned; the app owns the pool behind it, tests inject a fake.
    public init(rootPath: String, runner: any ProcessRunner) {
        let root = Self.normalizePath(rootPath)
        self.rootPath = root
        client = GitClient(
            repository: URL(filePath: root, directoryHint: .isDirectory), runner: runner, timeout: Self.gitTimeout,
            isolation: .strict)
        lock = Mutex(State())
    }

    public func status(for path: String) -> FileStatus? {
        let normalizedPath = Self.normalizePath(path)
        return lock.withLock { $0.statuses[normalizedPath] }
    }

    public var branchName: String? {
        lock.withLock { $0.branch }
    }

    public var summary: FileStatusSummary {
        lock.withLock { $0.summary }
    }

    /// Reads the branch and every status in one `git status`; a failing git leaves everything clean.
    public func refresh() async {
        let snapshot = (try? await client.status()) ?? GitStatusSnapshot(branch: nil, entries: [])
        let root = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var statuses: [String: FileStatus] = [:]
        for (relative, status) in snapshot.statusesByPath(includingDirectories: true) {
            statuses[Self.normalizePath(root + relative)] = status
        }
        lock.withLock { state in
            state.branch = snapshot.branch?.head
            state.statuses = statuses
            state.summary = snapshot.summary
            state.baseContents.removeAll(keepingCapacity: true)
        }
    }

    public func lineDecorations(for path: String, lines: [String]) async -> GitLineDecorations {
        let normalizedPath = Self.normalizePath(path)
        let status = status(for: normalizedPath)
        if lines.isEmpty { return .empty }
        if status == .untracked { return Self.addedLineDecorations(for: lines, color: .untracked) }
        guard let relativePath = relativePath(for: normalizedPath) else { return .empty }

        switch await readBaseContent(for: normalizedPath, relativePath: relativePath) {
            case .missing:
                guard status == .added else { return .empty }
                return Self.addedLineDecorations(for: lines, color: .added)
            case .text(_, let baseLines):
                return Self.lineDecorations(
                    baseLines: baseLines, currentLines: lines.map { Substring($0) }, addedColor: .added)
        }
    }

    /// The gutter marks of `current` against `base` and, for each modified line, the words that changed, both
    /// from the shared diff engine.
    static func lineDecorations(base: [String], current: [String], addedColor: FileStatusColor) -> GitLineDecorations {
        lineDecorations(
            baseLines: base.map { Substring($0) }, currentLines: current.map { Substring($0) }, addedColor: addedColor)
    }

    static func lineDecorations(baseLines old: [Substring], currentLines new: [Substring], addedColor: FileStatusColor)
        -> GitLineDecorations
    {
        let edits = LineDiff.diffLines(old: SubstringLines(old), new: SubstringLines(new))
        let markers = LineChangeMarkers(edits: edits, newLineCount: new.count)
        guard !markers.isEmpty else { return .empty }
        var emphasis: [Int: [ClosedRange<Int>]] = [:]
        for pair in LineChangeMarkers.modifiedPairs(edits: edits) {
            guard let ranges = IntralineDiff.emphasis(old: old[pair.old], new: new[pair.new], granularity: .word)?.new,
                !ranges.isEmpty
            else { continue }
            emphasis[pair.new] = Self.characterRanges(ranges, in: new[pair.new])
        }
        return GitLineDecorations(
            markers: markers.byLine.mapValues { change in
                switch change {
                    case .added: addedColor
                    case .modified: .modified
                    case .deleted: .deleted
                }
            },
            emphasis: emphasis)
    }

    /// UTF-16 offset ranges of `line` as closed character ranges, the unit the terminal columns are counted in.
    /// - Complexity: O(line length)
    static func characterRanges(_ utf16Ranges: [Range<Int>], in line: Substring) -> [ClosedRange<Int>] {
        var characterAtUTF16 = [Int](repeating: 0, count: line.utf16.count + 1)
        var offset = 0
        for (index, character) in line.enumerated() {
            for _ in 0 ..< character.utf16.count {
                characterAtUTF16[offset] = index
                offset += 1
            }
        }
        characterAtUTF16[offset] = line.count
        return utf16Ranges.compactMap { range in
            guard range.lowerBound < range.upperBound, range.upperBound <= line.utf16.count else { return nil }
            let start = characterAtUTF16[range.lowerBound]
            let end = characterAtUTF16[range.upperBound - 1]
            return start ... end
        }
    }

    // MARK: - Base contents

    private func readBaseContent(for normalizedPath: String, relativePath: String) async -> BaseContent {
        if let cached = lock.withLock({ $0.baseContents[normalizedPath] }) { return cached }
        let task: Task<BaseContent, Never> = inFlightLock.withLock { inFlight in
            if let existing = inFlight[normalizedPath] { return existing }
            let newTask = Task<BaseContent, Never> { await self.loadBaseContent(relativePath: relativePath) }
            inFlight[normalizedPath] = newTask
            return newTask
        }
        let content = await task.value
        lock.withLock { $0.baseContents[normalizedPath] = content }
        inFlightLock.withLock { $0[normalizedPath] = nil }
        return content
    }

    private func loadBaseContent(relativePath: String) async -> BaseContent {
        guard let data = try? await client.content(of: relativePath, at: "HEAD") else { return .missing }
        let content = String(decoding: data, as: UTF8.self)
        // Split once: every debounced refresh diffs against these lines.
        return .text(content, lines: Self.splitLines(content).map { Substring($0) })
    }

    private func relativePath(for normalizedPath: String) -> String? {
        guard normalizedPath != rootPath else { return nil }
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard normalizedPath.hasPrefix(rootPrefix) else { return nil }
        return String(normalizedPath.dropFirst(rootPrefix.count))
    }

    // MARK: - Repository detection

    public static func isGitRepository(_ path: String, runner: any ProcessRunner) async -> Bool {
        await repositoryRoot(for: path, runner: runner) != nil
    }

    public static func repositoryRoot(for path: String, runner: any ProcessRunner) async -> String? {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        guard let root = await GitClient.repositoryRoot(containing: url, runner: runner) else { return nil }
        return normalizePath(root.path(percentEncoded: false))
    }

    private static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func splitLines(_ content: String) -> [String] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.isEmpty ? [""] : lines
    }

    static func addedLineDecorations(for lines: [String], color: FileStatusColor) -> GitLineDecorations {
        guard !lines.isEmpty else { return .empty }
        return GitLineDecorations(markers: Dictionary(uniqueKeysWithValues: lines.indices.map { ($0, color) }))
    }
}
