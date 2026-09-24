import AtelierDiff
public import AtelierGit
public import AtelierProcess
public import AtelierText
import Foundation
public import KittyFileTree
import Synchronization
import os

/// The working tree's git statuses and per-line change markers for open buffers, read through the core git
/// client under strict isolation, cached until the next refresh.
public final class GitStatusProvider: FileStatusProvider, RopeGitLineDecorationProvider, Sendable {
    private enum BaseContent: Sendable {
        case missing
        case text(String, lines: [Substring])
    }

    /// A base from the cache, or the read that will produce it and the refresh generation it started under.
    private enum BaseLookup: Sendable {
        case cached(BaseContent)
        case reading(Task<BaseContent, Never>, generation: UInt64)
    }

    private struct State: Sendable {
        var statuses: [String: FileStatus] = [:]
        var branch: String?
        var summary = FileStatusSummary()
        var baseContents: [String: BaseContent] = [:]
        /// The base reads in flight under `appliedGeneration`, which concurrent requests for a path join.
        var baseReads: [String: Task<BaseContent, Never>] = [:]
        var normalizedPaths: [String: String] = [:]
        var pathNormalizationCount = 0
        /// The last refresh started, and the newest whose result is applied: refreshes run concurrently, so an
        /// older one can finish after a newer one.
        var startedGeneration: UInt64 = 0
        var appliedGeneration: UInt64 = 0
    }

    /// A hung `git` must never freeze the editor: every run gets this long on the runner's clock.
    public static let gitTimeout: Duration = .seconds(10)

    private static let logger = Logger(subsystem: "com.kittytui", category: "git")

    private let rootPath: String
    private let client: GitClient
    private let lock: Mutex<State>

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
        let normalized = normalizedPath(path)
        return lock.withLock { $0.statuses[normalized] }
    }

    var _testPathNormalizationCount: Int { lock.withLock { $0.pathNormalizationCount } }

    public var branchName: String? {
        lock.withLock { $0.branch }
    }

    public var summary: FileStatusSummary {
        lock.withLock { $0.summary }
    }

    /// Reads the branch and every status in one `git status`. A failing git keeps the last statuses it read, and a
    /// refresh that finishes after a newer one is dropped, so neither can blank or roll back the decorations.
    public func refresh() async {
        let generation = lock.withLock { state in
            state.startedGeneration += 1
            return state.startedGeneration
        }
        let snapshot: GitStatusSnapshot
        do {
            snapshot = try await client.status()
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error(
                "git status failed; the last statuses stay: \(error.localizedDescription, privacy: .private)")
            return
        }
        let root = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var statuses: [String: FileStatus] = [:]
        var normalizedPaths: [String: String] = [:]
        for (relative, status) in snapshot.statusesByPath(includingDirectories: true) {
            let path = root + relative
            let normalized = Self.normalizePath(path)
            normalizedPaths[path] = normalized
            statuses[normalized] = status
        }
        lock.withLock { state in
            guard generation > state.appliedGeneration else { return }
            state.appliedGeneration = generation
            state.branch = snapshot.branch?.head
            state.statuses = statuses
            state.normalizedPaths = normalizedPaths
            state.pathNormalizationCount += normalizedPaths.count
            state.summary = snapshot.summary
            // HEAD may have moved: bases cached or still being read under the previous status are dropped.
            state.baseContents.removeAll(keepingCapacity: true)
            state.baseReads.removeAll(keepingCapacity: true)
        }
    }

    public func lineDecorations(for path: String, lines: [String]) async -> GitLineDecorations {
        let normalizedPath = normalizedPath(path)
        let status = lock.withLock { $0.statuses[normalizedPath] }
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

    public func lineDecorations(for path: String, rope: Rope) async -> GitLineDecorations {
        let normalizedPath = normalizedPath(path)
        let status = lock.withLock { $0.statuses[normalizedPath] }
        if status == .untracked { return Self.addedLineDecorations(for: rope, color: .untracked) }
        guard let relativePath = relativePath(for: normalizedPath) else { return .empty }

        switch await readBaseContent(for: normalizedPath, relativePath: relativePath) {
            case .missing:
                guard status == .added else { return .empty }
                return Self.addedLineDecorations(for: rope, color: .added)
            case .text(_, let baseLines):
                return Self.lineDecorations(baseLines: baseLines, currentRope: rope, addedColor: .added)
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
        lineDecorations(baseLines: old, current: SubstringLines(new), lineAt: { new[$0] }, addedColor: addedColor)
    }

    static func lineDecorations(baseLines old: [Substring], currentRope new: Rope, addedColor: FileStatusColor)
        -> GitLineDecorations
    {
        guard let source = RopeLineSource(rope: new) else { return .empty }
        return lineDecorations(
            baseLines: old, current: source, lineAt: { source.line(at: $0) }, addedColor: addedColor)
    }

    private static func lineDecorations(
        baseLines old: [Substring], current: some DiffSource, lineAt: (Int) -> Substring,
        addedColor: FileStatusColor
    ) -> GitLineDecorations {
        guard !Task.isCancelled else { return .empty }
        let edits = LineDiff.diffLines(old: SubstringLines(old), new: current)
        guard !Task.isCancelled else { return .empty }
        let markers = LineChangeMarkers(edits: edits, newLineCount: current.lineCount)
        guard !markers.isEmpty else { return .empty }
        var emphasis: [Int: [ClosedRange<Int>]] = [:]
        for pair in LineChangeMarkers.modifiedPairs(edits: edits) {
            guard !Task.isCancelled else { return .empty }
            let newLine = lineAt(pair.new)
            guard let ranges = IntralineDiff.emphasis(old: old[pair.old], new: newLine, granularity: .word)?.new,
                !ranges.isEmpty
            else { continue }
            emphasis[pair.new] = Self.characterRanges(ranges, in: newLine)
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

    /// The base of `normalizedPath` from the cache, else from a read, joined if one is in flight. A read that a
    /// refresh overtakes is returned to its callers but never cached, since HEAD may have moved under it.
    private func readBaseContent(for normalizedPath: String, relativePath: String) async -> BaseContent {
        let lookup = lock.withLock { state -> BaseLookup in
            if let cached = state.baseContents[normalizedPath] { return .cached(cached) }
            if let read = state.baseReads[normalizedPath] {
                return .reading(read, generation: state.appliedGeneration)
            }
            let read = Task<BaseContent, Never> { await self.loadBaseContent(relativePath: relativePath) }
            state.baseReads[normalizedPath] = read
            return .reading(read, generation: state.appliedGeneration)
        }
        switch lookup {
            case .cached(let content):
                return content
            case .reading(let read, let generation):
                let content = await read.value
                lock.withLock { state in
                    guard state.appliedGeneration == generation else { return }
                    state.baseContents[normalizedPath] = content
                    if state.baseReads[normalizedPath] == read { state.baseReads[normalizedPath] = nil }
                }
                return content
        }
    }

    private func loadBaseContent(relativePath: String) async -> BaseContent {
        guard let data = try? await client.content(of: relativePath, at: "HEAD") else { return .missing }
        let content = String(decoding: data, as: UTF8.self)
        // Split once: every debounced refresh diffs against these lines.
        return .text(content, lines: Self.splitLines(content))
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

    private func normalizedPath(_ path: String) -> String {
        if let cached = lock.withLock({ $0.normalizedPaths[path] }) { return cached }
        let normalized = Self.normalizePath(path)
        return lock.withLock { state in
            if let cached = state.normalizedPaths[path] { return cached }
            if state.normalizedPaths.count >= 16_384 { state.normalizedPaths.removeAll(keepingCapacity: true) }
            state.normalizedPaths[path] = normalized
            state.pathNormalizationCount += 1
            return normalized
        }
    }

    /// The lines of `content`, each ended by LF, CRLF or a lone CR, as a buffer holds its file's text: a final line
    /// break leaves an empty last line. Swift folds CRLF into one `Character`, so the split runs on UTF-8 bytes.
    /// - Complexity: O(n) in the UTF-8 length of `content`.
    static func splitLines(_ content: String) -> [Substring] {
        let utf8 = content.utf8
        var lines: [Substring] = []
        var lineStart = utf8.startIndex
        var index = utf8.startIndex
        while index < utf8.endIndex {
            let byte = utf8[index]
            guard byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") else {
                index = utf8.index(after: index)
                continue
            }
            lines.append(content[lineStart ..< index])
            index = utf8.index(after: index)
            if byte == UInt8(ascii: "\r"), index < utf8.endIndex, utf8[index] == UInt8(ascii: "\n") {
                index = utf8.index(after: index)
            }
            lineStart = index
        }
        lines.append(content[lineStart...])
        return lines
    }

    static func addedLineDecorations(for lines: [String], color: FileStatusColor) -> GitLineDecorations {
        guard !lines.isEmpty else { return .empty }
        return GitLineDecorations(markers: Dictionary(uniqueKeysWithValues: lines.indices.map { ($0, color) }))
    }

    static func addedLineDecorations(for rope: Rope, color: FileStatusColor) -> GitLineDecorations {
        var markers: [Int: FileStatusColor] = [:]
        markers.reserveCapacity(rope.lineCount)
        for line in 0 ..< rope.lineCount {
            if line.isMultiple(of: RopeLineSource.chunkSize), Task.isCancelled { return .empty }
            markers[line] = color
        }
        return GitLineDecorations(markers: markers)
    }
}
